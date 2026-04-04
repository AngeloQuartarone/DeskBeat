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
    
    // Player nodes per il trigger live (Dual-Voice Polyphony per evitare click/pop)
    private var livePlayerNodes: [String: [AVAudioPlayerNode]] = [:]
    private var nodePointers: [String: Int] = [:] // Traccia quale voce usare (0 o 1)
    private var audioBuffers: [String: AVAudioPCMBuffer] = [:]
    
    /// Directory per i suoni caricati dall'utente
    let userSoundsDir: URL
    
    private init() {
        let fileManager = FileManager.default
        let appSupport = try! fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        userSoundsDir = appSupport.appendingPathComponent("com.macbeat.app/UserSounds", isDirectory: true)
        
        try? fileManager.createDirectory(at: userSoundsDir, withIntermediateDirectories: true)
        
        // Configura il limitatore sull'uscita master per prevenire il clipping digitale (distorsione)
        // Nota: AVAudioUnitEffect (PeakLimiter) non ha una proprietà .threshold diretta in Swift,
        // ma funge da brickwall limiter predefinito sullo 0dB.
        engine.attach(limiter)
        
        // Re-routing: Mixer -> Limiter -> Output
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(engine.mainMixerNode, to: limiter, format: format)
        engine.connect(limiter, to: engine.outputNode, format: format)

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
                for _ in 0..<2 {
                    let liveNode = AVAudioPlayerNode()
                    liveNode.volume = 0.85 // Headroom per la polifonia (evita di colpire troppo duro il limiter)
                    engine.attach(liveNode)
                    engine.connect(liveNode, to: engine.mainMixerNode, format: file.processingFormat)
                    nodes.append(liveNode)
                }
                
                livePlayerNodes[name] = nodes
                nodePointers[name] = 0
                audioBuffers[name] = buffer
                
                print("[MacBeat] ✅ Caricato: \(name).\(url.pathExtension)")
            } catch {
                print("❌ Errore caricamento \(name): \(error)")
            }
        }
    }

    /// Suona un campione in modalità live (Dual-Voice Polyphony per evitare click)
    func playSample(named name: String, source: String? = nil) {
        guard let nodes = livePlayerNodes[name], let buffer = audioBuffers[name] else { 
            setupNodeAndLoadBuffer(named: name)
            if let newNodes = livePlayerNodes[name], let newBuffer = audioBuffers[name] {
                let pointer = nodePointers[name] ?? 0
                playNode(newNodes[pointer], with: newBuffer)
                nodePointers[name] = (pointer + 1) % 2
            }
            return 
        }
        
        let pointer = nodePointers[name] ?? 0
        playNode(nodes[pointer], with: buffer)
        nodePointers[name] = (pointer + 1) % 2

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("MacBeatTriggeredEffect"),
                object: name,
                userInfo: source != nil ? ["source": source!] : nil
            )
        }
    }
    
    private func playNode(_ node: AVAudioPlayerNode, with buffer: AVAudioPCMBuffer) {
        if !engine.isRunning { 
            try? engine.start() 
            print("[MacBeat] 🔈 Motore Audio riavviato per riproduzione")
        }
        // Non fermiamo il nodo bruscamente per permettere polifonia ed evitare click.
        // scheduleBuffer con .interrupts pulisce eventuali playback precedenti sullo stesso nodo in modo sicuro.
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
            nodePointers.removeValue(forKey: name)
            audioBuffers.removeValue(forKey: name)
            print("[MacBeat] 🗑️ Rimosso: \(name)")
        }
        
        // Forza l'aggiornamento della lista (fuori da if let per coprire casi non caricati)
        refreshUserSounds()
    }
}