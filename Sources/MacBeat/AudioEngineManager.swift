import AVFoundation
import AudioToolbox
import Foundation

final class AudioEngineManager: ObservableObject {
    static let shared = AudioEngineManager()
    @Published var userSounds: [String] = []
    private let engine = AVAudioEngine()
    private let limiter: AVAudioUnitEffect = {
        var description = AudioComponentDescription()
        description.componentType = kAudioUnitType_Effect
        description.componentSubType = kAudioUnitSubType_PeakLimiter
        description.componentManufacturer = kAudioUnitManufacturer_Apple
        description.componentFlags = 0
        description.componentFlagsMask = 0
        return AVAudioUnitEffect(audioComponentDescription: description)
    }()

    private let compressor: AVAudioUnitEffect = {
        var description = AudioComponentDescription()
        description.componentType = kAudioUnitType_Effect
        description.componentSubType = kAudioUnitSubType_DynamicsProcessor
        description.componentManufacturer = kAudioUnitManufacturer_Apple
        description.componentFlags = 0
        description.componentFlagsMask = 0
        return AVAudioUnitEffect(audioComponentDescription: description)
    }()

    private let instrumentMixer = AVAudioMixerNode()
    
    // Player nodes per il trigger live (8-Voice Polyphony per evitare click/pop)
    private var livePlayerNodes: [String: [AVAudioPlayerNode]] = [:]
    private var audioBuffers: [String: AVAudioPCMBuffer] = [:]
    
    /// Directory per i suoni caricati dall'utente
    let userSoundsDir: URL
    
    private init() {
        let fileManager = FileManager.default
        let appSupport = try! fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        userSoundsDir = appSupport.appendingPathComponent("com.macbeat.app/UserSounds", isDirectory: true)
        
        try? fileManager.createDirectory(at: userSoundsDir, withIntermediateDirectories: true)
        
        // Configura il compressore via AudioUnit parameters
        if let au = compressor.auAudioUnit.parameterTree {
            // Parametri tipici per un compressore "soft"
            let thresholdParam = au.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_Threshold))
            let headRoomParam = au.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_HeadRoom))
            let expansionRatioParam = au.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_ExpansionRatio))
            let attackTimeParam = au.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_AttackTime))
            let releaseTimeParam = au.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_ReleaseTime))
            let masterGainParam = au.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_OverallGain))
            
            thresholdParam?.value = -12.0
            headRoomParam?.value = 2.0
            expansionRatioParam?.value = 2.0
            attackTimeParam?.value = 0.002
            releaseTimeParam?.value = 0.05
            masterGainParam?.value = 0.0
        }
        
        // Configurazione del Sub-Mixer: riceve tutti gli strumenti e li scala prima degli effetti
        instrumentMixer.outputVolume = 0.25 // Headroom strutturale (V3: 0.25 = somma di 4 full-power kick)
        
        engine.attach(instrumentMixer)
        engine.attach(compressor)
        engine.attach(limiter)
        
        // Re-routing: InstrumentMixer -> Compressor -> Limiter -> Output
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(instrumentMixer, to: compressor, format: format)
        engine.connect(compressor, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)

        loadSamples()
        refreshUserSounds()
        
        do {
            engine.prepare()
            try engine.start()
            print("[MacBeat] 🔊 Motore Audio Pronto (Mono/Interrupt)")
        } catch {
            print("❌ Errore critico Audio Engine: \(error)")
        }
    }
    
    /// Scansiona i file audio nella directory "Sounds" o nella cartella utente
    func getAvailableSoundFiles(in folderName: String) -> [String] {
        let fileManager = FileManager.default
        let currentDir = fileManager.currentDirectoryPath
        
        var basePaths: [String]
        
        if folderName == "UserSounds" {
            basePaths = [userSoundsDir.path]
        } else {
            var paths: [String] = []
            if let soundsURL = Bundle.module.url(forResource: "Sounds", withExtension: nil) {
                paths.append(soundsURL.path)
            }
            paths.append("\(currentDir)/Sources/MacBeat/Resources/Sounds")
            paths.append("\(currentDir)/Resources/Sounds")
            paths.append("\(currentDir)/Sounds")
            basePaths = paths
        }
        
        var foundFiles: [String] = []
        let extensions = ["mp3", "wav"] // Solo wav e mp3 come richiesto
        
        for basePath in basePaths {
            if let files = try? fileManager.contentsOfDirectory(atPath: basePath) {
                for file in files {
                    let url = URL(fileURLWithPath: file)
                    if extensions.contains(url.pathExtension.lowercased()) {
                        foundFiles.append(url.deletingPathExtension().lastPathComponent)
                    }
                }
                if !foundFiles.isEmpty { break }
            }
        }
        
        return Array(Set(foundFiles)).sorted()
    }

    /// Forza il rinfresco della lista suoni utente (chiamata dai metodi di aggiunta/rimozione)
    func refreshUserSounds() {
        let sounds = getAvailableSoundFiles(in: "UserSounds")
        DispatchQueue.main.async {
            self.userSounds = sounds
        }
    }

    /// Ritorna la lista dei nomi dei suoni aggiunti dall'utente
    func getUserAddedSounds() -> [String] {
        return getAvailableSoundFiles(in: "UserSounds")
    }

    private func loadSamples() {
        let baseSounds = getAvailableSoundFiles(in: "Base")
        let userSounds = getUserAddedSounds()
        let allSounds = baseSounds + userSounds
        
        for name in allSounds {
            setupNodeAndLoadBuffer(named: name)
        }
    }
    
    private func setupNodeAndLoadBuffer(named name: String) {
        if livePlayerNodes[name] != nil { return }
        
        let fileManager = FileManager.default
        let currentDir = fileManager.currentDirectoryPath
        let extensions = ["mp3", "wav"] // Solo wav e mp3
        
        var foundURL: URL? = nil
        
        // Prima cerchiamo nei suoni utente (hanno la priorità in caso di omonimia)
        for ext in extensions {
            let userPath = userSoundsDir.appendingPathComponent("\(name).\(ext)")
            if fileManager.fileExists(atPath: userPath.path) {
                foundURL = userPath
                break
            }
        }
        
        // Se non trovato, cerchiamo nella radice di Sounds
        if foundURL == nil {
            outerLoop: for ext in extensions {
                if let moduleURL = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Sounds") {
                    foundURL = moduleURL
                    break outerLoop
                }
                
                let pathsToTry = [
                    "\(currentDir)/Sources/MacBeat/Resources/Sounds/\(name).\(ext)",
                    "\(currentDir)/Resources/Sounds/\(name).\(ext)",
                    "\(currentDir)/Sounds/\(name).\(ext)"
                ]
                
                for path in pathsToTry {
                    if fileManager.fileExists(atPath: path) {
                        foundURL = URL(fileURLWithPath: path)
                        break outerLoop
                    }
                }
            }
        }

        if let url = foundURL {
            do {
                let file = try AVAudioFile(forReading: url)
                let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
                try file.read(into: buffer)
                
                var nodes: [AVAudioPlayerNode] = []
                for _ in 0..<8 { // Aumentata polifonia a 8 voci per evitare click su restart
                    let liveNode = AVAudioPlayerNode()
                    liveNode.volume = 0.80 // Volume interno alto, l'headroom è gestita dal sub-mixer (V3)
                    engine.attach(liveNode)
                    engine.connect(liveNode, to: instrumentMixer, format: file.processingFormat)
                    nodes.append(liveNode)
                }
                
                livePlayerNodes[name] = nodes
                audioBuffers[name] = buffer
                
                print("[MacBeat] ✅ Caricato: \(name).\(url.pathExtension)")
            } catch {
                print("❌ Errore caricamento \(name): \(error)")
            }
        }
    }

    /// Suona un campione cercando una voce libera (8-Voice Polyphony)
    func playSample(named name: String, source: String? = nil) {
        guard let nodes = livePlayerNodes[name], let buffer = audioBuffers[name] else { 
            setupNodeAndLoadBuffer(named: name)
            // Se non caricato ora, usciamo
            guard let retryNodes = livePlayerNodes[name], let retryBuffer = audioBuffers[name] else { return }
            selectAndPlay(nodes: retryNodes, buffer: retryBuffer)
            triggerVisualEffect(named: name, source: source)
            return 
        }
        
        let isKick = name.lowercased().contains("kick")
        selectAndPlay(nodes: nodes, buffer: buffer, isKick: isKick)
        triggerVisualEffect(named: name, source: source)
    }

    private func selectAndPlay(nodes: [AVAudioPlayerNode], buffer: AVAudioPCMBuffer, isKick: Bool = false) {
        if !engine.isRunning { try? engine.start() }

        // Trova il primo nodo non in riproduzione
        let idleNode = nodes.first { !$0.isPlaying }
        
        if let node = idleNode {
            // Se è un Kick e ci sono troppe voci attive, limitiamo a 2 per evitare clip di frequenze basse
            if isKick {
                let playingNodes = nodes.filter { $0.isPlaying }
                if playingNodes.count >= 2 {
                    // Ferma la più vecchia
                    playingNodes[0].stop()
                }
            }
            node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            node.play()
        } else {
            // Se tutti occupati, usiamo il primo e lo interrompiamo
            let busyNode = nodes[0]
            busyNode.stop()
            busyNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            busyNode.play()
        }
    }

    private func triggerVisualEffect(named name: String, source: String?) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("MacBeatTriggeredEffect"),
                object: name,
                userInfo: source != nil ? ["source": source!] : nil
            )
        }
    }
    
    private func playNode(_ node: AVAudioPlayerNode, with buffer: AVAudioPCMBuffer) {
        // Metodo mantenuto per retrocompatibilità interna se necessario, ma selectAndPlay è prioritario ora
        if !engine.isRunning { try? engine.start() }
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        node.play()
    }

    /// Ferma il motore audio completamente per risparmiare batteria
    func stopEngine() {
        if engine.isRunning {
            engine.stop()
            print("[MacBeat] 💤 Motore Audio fermato (Battery Save)")
        }
    }

    /// Ferma immediatamente tutti i campioni in riproduzione
    func stopAllSamples() {
        for nodeList in livePlayerNodes.values {
            for node in nodeList {
                node.stop()
            }
        }
    }

    /// Ferma un campione specifico immediatamente
    func stopSample(named name: String) {
        if let nodes = livePlayerNodes[name] {
            for node in nodes {
                node.stop()
            }
        }
    }

    // MARK: - User Sound Management

    /// Aggiunge un nuovo suono utente copiandolo nella directory dedicata
    func addUserSound(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        guard ext == "wav" || ext == "mp3" else { return nil }
        
        let fileName = url.deletingPathExtension().lastPathComponent
        let destinationURL = userSoundsDir.appendingPathComponent("\(fileName).\(ext)")
        
        do {
            // Se esiste già, lo rimuoviamo per sovrascriverlo
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: url, to: destinationURL)
            
            // Carica immediatamente il nuovo suono nel motore audio
            setupNodeAndLoadBuffer(named: fileName)
            refreshUserSounds()
            return fileName
        } catch {
            print("❌ Errore durante l'aggiunta del suono: \(error)")
            return nil
        }
    }

    /// Rimuove un suono utente
    func removeUserSound(named name: String) {
        let fileManager = FileManager.default
        let extensions = ["mp3", "wav"]
        
        for ext in extensions {
            let fileURL = userSoundsDir.appendingPathComponent("\(name).\(ext)")
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: fileURL)
            }
        }
        
        // Rimuovi dal motore audio
        if let nodes = livePlayerNodes[name] {
            for node in nodes {
                node.stop()
                engine.detach(node)
            }
            livePlayerNodes.removeValue(forKey: name)
            audioBuffers.removeValue(forKey: name)
            print("[MacBeat] 🗑️ Rimosso: \(name)")
        }
        
        // Forza l'aggiornamento della lista (fuori da if let per coprire casi non caricati)
        refreshUserSounds()
    }
}