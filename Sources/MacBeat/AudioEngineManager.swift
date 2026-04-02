import AVFoundation
import Foundation

final class AudioEngineManager {
    static let shared = AudioEngineManager()
    private let engine = AVAudioEngine()
    
    // Player nodes per il trigger live (bassa latenza)
    private var livePlayerNodes: [String: AVAudioPlayerNode] = [:]
    private var audioBuffers: [String: AVAudioPCMBuffer] = [:]
    
    /// Directory per i suoni caricati dall'utente
    let userSoundsDir: URL
    
    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        userSoundsDir = appSupport.appendingPathComponent("com.macbeat.app/UserSounds", isDirectory: true)
        
        try? fileManager.createDirectory(at: userSoundsDir, withIntermediateDirectories: true)
        
        loadSamples()
        
        do {
            engine.prepare()
            try engine.start()
            print("[MacBeat] 🔊 Motore Audio Pronto (Mono/Interrupt)")
        } catch {
            print("❌ Errore critico Audio Engine: \(error)")
        }
    }
    
    /// Scansiona i file audio in una specifica sottocartella di "Sounds" o nella cartella utente
    func getAvailableSoundFiles(in folderName: String) -> [String] {
        let fileManager = FileManager.default
        let currentDir = fileManager.currentDirectoryPath
        
        var basePaths = [
            "\(currentDir)/Sources/MacBeat/Resources/Sounds/\(folderName)",
            "\(currentDir)/Resources/Sounds/\(folderName)",
            "\(currentDir)/Sounds/\(folderName)"
        ]
        
        // Se cerchiamo i suoni utente, aggiungiamo il path dedicato
        if folderName == "UserSounds" {
            basePaths = [userSoundsDir.path]
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

    /// Ritorna la lista dei nomi dei suoni aggiunti dall'utente
    func getUserAddedSounds() -> [String] {
        return getAvailableSoundFiles(in: "UserSounds")
    }

    private func loadSamples() {
        let standardSounds = getAvailableSoundFiles(in: "Standard")
        let looperSounds = getAvailableSoundFiles(in: "Looper")
        let userSounds = getUserAddedSounds()
        let allSounds = standardSounds + looperSounds + userSounds
        
        for name in allSounds {
            setupNodeAndLoadBuffer(named: name)
        }
    }
    
    private func setupNodeAndLoadBuffer(named name: String) {
        if livePlayerNodes[name] != nil { return }
        
        let fileManager = FileManager.default
        let currentDir = fileManager.currentDirectoryPath
        let folders = ["Standard", "Looper"]
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
        
        // Se non trovato, cerchiamo nelle risorse predefinite
        if foundURL == nil {
            outerLoop: for folder in folders {
                for ext in extensions {
                    let pathsToTry = [
                        "\(currentDir)/Sources/MacBeat/Resources/Sounds/\(folder)/\(name).\(ext)",
                        "\(currentDir)/Resources/Sounds/\(folder)/\(name).\(ext)",
                        "\(currentDir)/\(folder)/\(name).\(ext)"
                    ]
                    
                    for path in pathsToTry {
                        if fileManager.fileExists(atPath: path) {
                            foundURL = URL(fileURLWithPath: path)
                            break outerLoop
                        }
                    }
                }
            }
        }

        if let url = foundURL {
            do {
                let file = try AVAudioFile(forReading: url)
                let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
                try file.read(into: buffer)
                
                let liveNode = AVAudioPlayerNode()
                engine.attach(liveNode)
                engine.connect(liveNode, to: engine.mainMixerNode, format: file.processingFormat)
                
                livePlayerNodes[name] = liveNode
                audioBuffers[name] = buffer
                
                print("[MacBeat] ✅ Caricato: \(name).\(url.pathExtension)")
            } catch {
                print("❌ Errore caricamento \(name): \(error)")
            }
        }
    }

    /// Suona un campione in modalità live (bassa latenza, prioritario)
    func playSample(named name: String) {
        guard let playerNode = livePlayerNodes[name], let buffer = audioBuffers[name] else { 
            setupNodeAndLoadBuffer(named: name)
            if let newNode = livePlayerNodes[name], let newBuffer = audioBuffers[name] {
                playNode(newNode, with: newBuffer)
            }
            return 
        }
        
        playNode(playerNode, with: buffer)

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("MacBeatTriggeredEffect"),
                object: name
            )
        }
    }
    
    private func playNode(_ node: AVAudioPlayerNode, with buffer: AVAudioPCMBuffer) {
        if !engine.isRunning { try? engine.start() }
        node.stop() // Interrompe il suono precedente (Mono mode)
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        node.play()
    }

    /// Ferma immediatamente tutti i campioni in riproduzione
    func stopAllSamples() {
        for node in livePlayerNodes.values {
            node.stop()
        }
    }

    /// Ferma un campione specifico immediatamente
    func stopSample(named name: String) {
        livePlayerNodes[name]?.stop()
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
        if let node = livePlayerNodes[name] {
            node.stop()
            engine.detach(node)
            livePlayerNodes.removeValue(forKey: name)
            audioBuffers.removeValue(forKey: name)
            print("[MacBeat] 🗑️ Rimosso: \(name)")
        }
    }
}