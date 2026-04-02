import AVFoundation
import Foundation

final class AudioEngineManager {
    static let shared = AudioEngineManager()
    private let engine = AVAudioEngine()
    
    // Player nodes per il trigger live (bassa latenza)
    private var livePlayerNodes: [String: AVAudioPlayerNode] = [:]
    private var audioBuffers: [String: AVAudioPCMBuffer] = [:]
    
    private init() {
        loadSamples()
        
        do {
            engine.prepare()
            try engine.start()
            print("[MacBeat] 🔊 Motore Audio Pronto (Mono/Interrupt)")
        } catch {
            print("❌ Errore critico Audio Engine: \(error)")
        }
    }
    
    /// Scansiona i file audio in una specifica sottocartella di "Sounds"
    func getAvailableSoundFiles(in folderName: String) -> [String] {
        let fileManager = FileManager.default
        let currentDir = fileManager.currentDirectoryPath
        
        let basePaths = [
            "\(currentDir)/Sources/MacBeat/Resources/Sounds/\(folderName)",
            "\(currentDir)/Resources/Sounds/\(folderName)",
            "\(currentDir)/Sounds/\(folderName)"
        ]
        
        var foundFiles: [String] = []
        let extensions = ["mp3", "wav", "m4a"]
        
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

    private func loadSamples() {
        let standardSounds = getAvailableSoundFiles(in: "Standard")
        let looperSounds = getAvailableSoundFiles(in: "Looper")
        let allSounds = standardSounds + looperSounds
        
        for name in allSounds {
            setupNodeAndLoadBuffer(named: name)
        }
    }
    
    private func setupNodeAndLoadBuffer(named name: String) {
        if livePlayerNodes[name] != nil { return }
        
        let fileManager = FileManager.default
        let currentDir = fileManager.currentDirectoryPath
        let folders = ["Standard", "Looper"]
        let extensions = ["mp3", "wav", "m4a"]
        
        var foundURL: URL? = nil
        
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
}