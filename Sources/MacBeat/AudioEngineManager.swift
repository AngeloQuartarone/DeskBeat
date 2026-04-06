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
    private var samplers: [String: AVAudioUnitSampler] = [:]
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
        
        // Configurazione del Peak Limiter per evitare distorsione
        if let au = limiter.auAudioUnit.parameterTree {
            // Parametri tipici: Attack 0.001s, Release 0.010, Pre-gain 0.0dB
            let attackParam = au.parameter(withAddress: 0) // kPeakLimiterParam_AttackTime
            let releaseParam = au.parameter(withAddress: 1) // kPeakLimiterParam_ReleaseTime
            let preGainParam = au.parameter(withAddress: 2) // kPeakLimiterParam_PreGain
            
            attackParam?.value = 0.001
            releaseParam?.value = 0.010
            preGainParam?.value = 0.0
        }
        
        // Configurazione del Sub-Mixer: riceve tutti gli strumenti e li scala prima degli effetti
        // V3 (Ottimizzato): 0.15 = Headroom strutturale elevata per evitare summing clip nelle basse frequenze
        instrumentMixer.outputVolume = 0.15 
        
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
        if samplers[name] != nil || livePlayerNodes[name] != nil { return }
        
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
                // Nuova Architettura: Utilizzo di AVAudioUnitSampler (Migliore per Kick/Drum Machine)
                let sampler = AVAudioUnitSampler()
                engine.attach(sampler)
                
                let format = engine.mainMixerNode.outputFormat(forBus: 0)
                engine.connect(sampler, to: instrumentMixer, format: format)
                
                try sampler.loadAudioFiles(at: [url])
                
                // Configurazione Monofonia se è un Kick (per eliminare clipping di somma)
                if name.lowercased().contains("kick") {
                    var limit: UInt32 = 1
                    let propertyID: AudioUnitPropertyID = 28 // kAudioUnitProperty_GroupPolyphonyLimit
                    AudioUnitSetProperty(sampler.audioUnit, 
                                        propertyID, 
                                        kAudioUnitScope_Global, 0, 
                                        &limit, 
                                        UInt32(MemoryLayout<UInt32>.size))
                }
                
                samplers[name] = sampler
                print("[MacBeat] ✅ Caricato (Sampler): \(name).\(url.pathExtension)")
                
                // Fallback per Buffers se servissero ancora altrove
                let file = try AVAudioFile(forReading: url)
                let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
                try file.read(into: buffer)
                audioBuffers[name] = buffer
                
            } catch {
                print("❌ Errore caricamento Sampler \(name): \(error)")
            }
        }
    }

    /// Suona un campione cercando una voce libera (Usa Sampler o PlayerNodes)
    func playSample(named name: String, source: String? = nil) {
        if let sampler = samplers[name] {
            if !engine.isRunning { try? engine.start() }
            // Ferma la nota precedente per sicurezza (evita droni/"uuuu")
            sampler.stopNote(60, onChannel: 0)
            // Trigger della nota con Velocity alta
            sampler.startNote(60, withVelocity: 100, onChannel: 0)
            triggerVisualEffect(named: name, source: source)
            return
        }

        guard let nodes = livePlayerNodes[name], let buffer = audioBuffers[name] else { 
            setupNodeAndLoadBuffer(named: name)
            // Se caricato ora come sampler nel giro sopra, riproviamo trigger ricorsivo (o usciamo se fallito)
            if samplers[name] != nil || livePlayerNodes[name] != nil {
                playSample(named: name, source: source)
            }
            return 
        }
        
        let isKick = name.lowercased().contains("kick")
        selectAndPlay(nodes: nodes, buffer: buffer, isKick: isKick)
        triggerVisualEffect(named: name, source: source)
    }

    private func selectAndPlay(nodes: [AVAudioPlayerNode], buffer: AVAudioPCMBuffer, isKick: Bool = false) {
        if !engine.isRunning { try? engine.start() }

        // Gestione MONOFONICA per il Kick (evita clipping basse frequenze e mud)
        if isKick {
            // Ferma TUTTI i nodi del Kick in riproduzione PRIMA di farne partire uno nuovo
            // Questo garantisce che non ci sia mai energia residua sommata (Voice Stealing)
            for node in nodes {
                if node.isPlaying {
                    node.stop()
                }
            }
        }

        // Trova il primo nodo libero (idle) per suonare
        let idleNode = nodes.first { !$0.isPlaying }
        
        if let node = idleNode {
            node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            node.play()
        } else {
            // Se tutti occupati (fallback raro per polyphony), usiamo il primo e lo interrompiamo
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
        for sampler in samplers.values {
            sampler.stopNote(60, onChannel: 0)
        }
    }

    /// Ferma un campione specifico immediatamente
    func stopSample(named name: String) {
        if let sampler = samplers[name] {
            sampler.stopNote(60, onChannel: 0)
        }
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