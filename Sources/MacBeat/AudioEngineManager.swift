import AVFoundation
import AudioToolbox
import Foundation

final class AudioEngineManager: ObservableObject {
    static let shared = AudioEngineManager()
    @Published var userSounds: [String] = []
    
    // 1. TRASFORmati in 'var' per poterli distruggere e ricreare
    private var engine = AVAudioEngine()
    private var limiter: AVAudioUnitEffect
    private var compressor: AVAudioUnitEffect
    private var instrumentMixer = AVAudioMixerNode()
    
    private var livePlayerNodes: [String: [AVAudioPlayerNode]] = [:]
    private var samplers: [String: AVAudioUnitSampler] = [:]
    private var audioBuffers: [String: AVAudioPCMBuffer] = [:]
    
    let userSoundsDir: URL
    
    private init() {
        let fileManager = FileManager.default
        let appSupport = try! fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        userSoundsDir = appSupport.appendingPathComponent("com.macbeat.app/UserSounds", isDirectory: true)
        
        try? fileManager.createDirectory(at: userSoundsDir, withIntermediateDirectories: true)
        
        // Inizializzazione corretta per superare il check di AVFoundation
        let limiterDesc = AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        self.limiter = AVAudioUnitEffect(audioComponentDescription: limiterDesc)
        
        let compDesc = AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_DynamicsProcessor, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        self.compressor = AVAudioUnitEffect(audioComponentDescription: compDesc)
        
        // Avvio il vero setup che simula il riavvio
        hardRebootSystem()
    }
    
    // MARK: - HARD REBOOT
    
    /// DISTRUGGE E RICREA COMPLETAMENTE L'AUDIO ENGINE (Simula l'apertura dell'app)
    func hardRebootSystem() {
        print("[MacBeat] 🔄 Riavvio completo dell'Audio Engine in corso...")
        
        // Ferma e svuota tutto
        if engine.isRunning { engine.stop() }
        samplers.removeAll()
        livePlayerNodes.removeAll()
        audioBuffers.removeAll()
        
        // Ricrea le istanze principali da zero (pulisce i "bug" zombie di memoria)
        engine = AVAudioEngine()
        instrumentMixer = AVAudioMixerNode()
        
        let limiterDesc = AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        limiter = AVAudioUnitEffect(audioComponentDescription: limiterDesc)
        
        let compDesc = AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_DynamicsProcessor, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        compressor = AVAudioUnitEffect(audioComponentDescription: compDesc)
        
        // Configura Parametri Compressore
        if let au = compressor.auAudioUnit.parameterTree {
            au.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_Threshold))?.value = -12.0
            au.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_HeadRoom))?.value = 2.0
            au.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_ExpansionRatio))?.value = 2.0
            au.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_AttackTime))?.value = 0.002
            au.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_ReleaseTime))?.value = 0.05
            au.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_OverallGain))?.value = 0.0
        }
        
        // Configura Parametri Limiter
        if let au = limiter.auAudioUnit.parameterTree {
            au.parameter(withAddress: 0)?.value = 0.001
            au.parameter(withAddress: 1)?.value = 0.010
            au.parameter(withAddress: 2)?.value = 0.0
        }
        
        instrumentMixer.outputVolume = 0.15 
        
        // Attacca e Connetti
        engine.attach(instrumentMixer)
        engine.attach(compressor)
        engine.attach(limiter)
        
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(instrumentMixer, to: compressor, format: format)
        engine.connect(compressor, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)

        // Ricarica tutti i campioni
        loadSamples()
        refreshUserSounds()
        
        do {
            engine.prepare()
            try engine.start()
            print("[MacBeat] ✅ Motore Audio Riavviato da zero e Pronto!")
        } catch {
            print("❌ Errore critico Riavvio Audio Engine: \(error)")
        }
    }
    
    // MARK: - CORE ENGINE FUNCS
    
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
        let extensions = ["mp3", "wav"]
        
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

    func refreshUserSounds() {
        let sounds = getAvailableSoundFiles(in: "UserSounds")
        DispatchQueue.main.async {
            self.userSounds = sounds
        }
    }

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
        let extensions = ["mp3", "wav"]
        var foundURL: URL? = nil
        
        for ext in extensions {
            let userPath = userSoundsDir.appendingPathComponent("\(name).\(ext)")
            if fileManager.fileExists(atPath: userPath.path) {
                foundURL = userPath
                break
            }
        }
        
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
                let sampler = AVAudioUnitSampler()
                engine.attach(sampler)
                engine.connect(sampler, to: instrumentMixer, format: nil)
                try sampler.loadAudioFiles(at: [url])
                
                if name.lowercased().contains("kick") {
                    var limit: UInt32 = 1
                    AudioUnitSetProperty(sampler.audioUnit, 28, kAudioUnitScope_Global, 0, &limit, UInt32(MemoryLayout<UInt32>.size))
                }
                
                samplers[name] = sampler
                
                let file = try AVAudioFile(forReading: url)
                let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
                try file.read(into: buffer)
                audioBuffers[name] = buffer
                
            } catch {
                print("❌ Errore caricamento Sampler \(name): \(error)")
            }
        }
    }

    func playSample(named name: String, source: String? = nil) {
        if let sampler = samplers[name] {
            if !engine.isRunning { try? engine.start() }
            sampler.stopNote(60, onChannel: 0)
            sampler.startNote(60, withVelocity: 100, onChannel: 0)
            triggerVisualEffect(named: name, source: source)
            return
        }

        guard let nodes = livePlayerNodes[name], let buffer = audioBuffers[name] else { 
            setupNodeAndLoadBuffer(named: name)
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
        if isKick {
            for node in nodes { if node.isPlaying { node.stop() } }
        }
        let idleNode = nodes.first { !$0.isPlaying }
        if let node = idleNode {
            node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            node.play()
        } else {
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

    func stopEngine() {
        if engine.isRunning {
            engine.stop()
            print("[MacBeat] 💤 Motore Audio fermato (Battery Save)")
        }
    }

    func stopAllSamples() {
        for nodeList in livePlayerNodes.values {
            for node in nodeList { node.stop() }
        }
        for sampler in samplers.values {
            sampler.stopNote(60, onChannel: 0)
        }
    }

    func stopSample(named name: String) {
        if let sampler = samplers[name] { sampler.stopNote(60, onChannel: 0) }
        if let nodes = livePlayerNodes[name] {
            for node in nodes { node.stop() }
        }
    }

    // MARK: - USER SOUND MANAGEMENT
    
    func addUserSound(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        guard ext == "wav" || ext == "mp3" else { return nil }
        
        let fileName = url.deletingPathExtension().lastPathComponent
        let destinationURL = userSoundsDir.appendingPathComponent("\(fileName).\(ext)")
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: url, to: destinationURL)
            
            // Invece di iniettare nel motore attivo, RIAVVIAMO L'INTERO SISTEMA!
            DispatchQueue.main.async {
                self.hardRebootSystem()
            }
            
            return fileName
        } catch {
            print("❌ Errore durante l'aggiunta del suono: \(error)")
            return nil
        }
    }

    func removeUserSound(named name: String) {
        let fileManager = FileManager.default
        let extensions = ["mp3", "wav"]
        
        for ext in extensions {
            let fileURL = userSoundsDir.appendingPathComponent("\(name).\(ext)")
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: fileURL)
            }
        }
        print("[MacBeat] 🗑️ Rimosso fisicamente: \(name)")
        
        // Eseguendo il reboot, il suono non verrà ricaricato e i vecchi nodi moriranno
        DispatchQueue.main.async {
            self.hardRebootSystem()
        }
    }
}