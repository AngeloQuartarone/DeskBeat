import Foundation
import SwiftUI

struct InstrumentPad: Identifiable {
    let id: String       // Es. "kick"
    let name: String     // Es. "Kick"
    let letter: String   // Es. "K"
    let color: Color
}

enum LooperState: String {
    case idle = "Ready"
    case recording = "Listening..."
    case looping = "Looping"
}

enum StepResolution: Int, CaseIterable {
    case eighth = 8
    case sixteenth = 16
    case thirtySecond = 32
    
    var stepsPerBeat: Int {
        switch self {
        case .eighth: return 2
        case .sixteenth: return 4
        case .thirtySecond: return 8
        }
    }
}

final class LooperManager: ObservableObject {
    static let shared = LooperManager()

    @Published var isLooperMode: Bool = false
    @Published var targetInput: String = UserDefaults.standard.string(forKey: "targetInput") ?? "TOP" {
        didSet { UserDefaults.standard.set(targetInput, forKey: "targetInput") }
    }
    @Published var currentInstrument: String = "kick"
    @Published var isQuantized: Bool = (UserDefaults.standard.object(forKey: "isQuantized") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(isQuantized, forKey: "isQuantized") }
    }
    @Published var mutedInstruments: Set<String> = []

    @Published var state: LooperState = .idle
    @Published var calculatedBPM: Double = 0
    @Published var currentStep: Int = -1
    
    @Published var availablePads: [InstrumentPad] = []
    
    // Griglia del sequencer: InstrumentID -> Array di Bool (lunghezza = totalSteps)
    @Published var grid: [String: [Bool]] = [:]
    
    // Configurazione Sequencer
    var resolution: StepResolution = .sixteenth
    var totalSteps: Int = 16 // Per ora fisso a 1 bar (16 step @ 1/16)

    private var rawEvents: [(name: String, time: TimeInterval)] = []
    
    private var loopStartTime: TimeInterval?
    private var loopDuration: TimeInterval = 0
    private var beatDuration: TimeInterval = 0
    private var stepDuration: TimeInterval = 0

    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.5
    private var playbackTimer: Timer?
    
    // Per gestire il trigger dei suoni in modo preciso
    private var lastTriggeredStep: Int = -1

    private init() {
        setupDefaultPads()
    }
    
    func setupDefaultPads() {
        let availableBase = AudioEngineManager.shared.getAvailableSoundFiles(in: "Base")
        let baseSet = ["bass", "clap", "hihat", "kick", "snare"]
        
        let looperSounds = availableBase.filter { baseSet.contains($0) }
        let userSounds = AudioEngineManager.shared.getUserAddedSounds()
        let allSounds = looperSounds + userSounds
        
        self.availablePads = allSounds.enumerated().map { index, filename in
            let id = filename
            let name = filename.replacingOccurrences(of: "_", with: " ").capitalized
            let letter = String(name.prefix(1)).uppercased()
            let color = deterministicColor(index: index)
            return InstrumentPad(id: id, name: name, letter: letter, color: color)
        }
        
        // Inizializza la griglia per tutti gli strumenti disponibili
        resetGrid()
        
        if !availablePads.contains(where: { $0.id == currentInstrument }) {
            if let first = availablePads.first {
                currentInstrument = first.id
            }
        }
    }
    
    func resetGrid() {
        grid.removeAll()
        for pad in availablePads {
            grid[pad.id] = Array(repeating: false, count: totalSteps)
        }
    }
    
    private func deterministicColor(index: Int) -> Color {
        let palette: [Color] = [
            .orange, .blue, .purple, .green, .pink, .mint, .teal, .yellow,
            .indigo, .cyan, .red, .brown
        ]
        return palette[index % palette.count]
    }

    // MARK: - Sequencer Actions

    func toggleStep(instrument: String, stepIndex: Int) {
        guard stepIndex >= 0 && stepIndex < totalSteps else { return }
        if grid[instrument] == nil {
            grid[instrument] = Array(repeating: false, count: totalSteps)
        }
        grid[instrument]?[stepIndex].toggle()
        
        // Se l'utente attiva manualmente, passiamo a uno stato di riproduzione fittizio se eravamo in idle
        if state == .idle {
            // Se non c'è un BPM, ne usiamo uno di default (120) per permettere il manual edit
            if calculatedBPM == 0 {
                setupManualSequencer(bpm: 120)
            }
        }
    }

    func clearInstrument(_ instrument: String) {
        grid[instrument] = Array(repeating: false, count: totalSteps)
        AudioEngineManager.shared.stopSample(named: instrument)
        
        // Se non ci sono più note attive, potremmo resettare ma solitamente si preferisce mantenere il BPM
        let hasAnyNote = grid.values.contains { $0.contains(true) }
        if !hasAnyNote && state == .looping {
            // Restiamo in looping ma col sequencer vuoto
        }
    }

    func toggleMute(instrument: String) {
        if mutedInstruments.contains(instrument) {
            mutedInstruments.remove(instrument)
        } else {
            mutedInstruments.insert(instrument)
            AudioEngineManager.shared.stopSample(named: instrument)
        }
    }

    // MARK: - Tap processing

    func processTap(rawTap: String) {
        guard rawTap == targetInput else { return }

        // Play feedback
        AudioEngineManager.shared.playSample(named: currentInstrument)

        let now = ProcessInfo.processInfo.systemUptime

        switch state {
        case .idle:
            state = .recording
            loopStartTime = now
            rawEvents = [(currentInstrument, 0.0)]
            resetSilenceTimer(now: now)

        case .recording:
            guard let startTime = loopStartTime else { return }
            let elapsed = now - startTime
            rawEvents.append((currentInstrument, elapsed))
            resetSilenceTimer(now: now)

        case .looping:
            guard let startTime = loopStartTime else { return }
            let elapsed = now - startTime
            
            // Quantizzazione immediata allo step più vicino
            let rawOffset = elapsed.truncatingRemainder(dividingBy: loopDuration)
            let stepIdx = Int(round(rawOffset / stepDuration)) % totalSteps
            
            // Accendiamo lo step
            if grid[currentInstrument] == nil {
                grid[currentInstrument] = Array(repeating: false, count: totalSteps)
            }
            grid[currentInstrument]?[stepIdx] = true
        }
    }

    // MARK: - Recording finalization

    private func resetSilenceTimer(now: TimeInterval) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            self?.finalizeRecording()
        }
    }

    private func finalizeRecording() {
        guard state == .recording else { return }
        guard rawEvents.count > 1 else { reset(); return }

        // Stima del BPM basata sui primi tap
        var intervals: [TimeInterval] = []
        for i in 1..<rawEvents.count {
            intervals.append(rawEvents[i].time - rawEvents[i-1].time)
        }
        intervals.sort()
        var roughBeat = intervals[intervals.count / 2]
        while roughBeat < 0.33 { roughBeat *= 2 }
        while roughBeat > 1.0  { roughBeat /= 2 }

        let totalTappedTime = rawEvents.last!.time
        let beatsInBar = 4.0 // Assumiamo 4/4
        let estimatedBeats = max(1.0, round(totalTappedTime / roughBeat))
        
        // Forziamo il loop duration a essere esattamente 1 battuta (4 beats) per ora
        // Ricalcoliamo il beatDuration basandoci sulla media per avere un BPM stabile
        let preciseBeat = totalTappedTime / estimatedBeats
        self.beatDuration = preciseBeat
        self.calculatedBPM = 60.0 / preciseBeat
        
        // Loop duration fisso a 4 beat (1 bar)
        self.loopDuration = 4.0 * preciseBeat
        self.stepDuration = loopDuration / Double(totalSteps)

        // Riempiamo la griglia dai tap registrati
        resetGrid()
        for event in rawEvents {
            let wrappedTime = event.time.truncatingRemainder(dividingBy: loopDuration)
            let stepIdx = Int(round(wrappedTime / stepDuration)) % totalSteps
            grid[event.name]?[stepIdx] = true
        }

        self.loopStartTime = ProcessInfo.processInfo.systemUptime
        self.state = .looping
        startPlayback()
    }
    
    private func setupManualSequencer(bpm: Double) {
        self.calculatedBPM = bpm
        self.beatDuration = 60.0 / bpm
        self.loopDuration = 4.0 * beatDuration
        self.stepDuration = loopDuration / Double(totalSteps)
        self.loopStartTime = ProcessInfo.processInfo.systemUptime
        self.state = .looping
        startPlayback()
    }

    // MARK: - Playback Loop
    
    func startPlayback() {
        playbackTimer?.invalidate()
        lastTriggeredStep = -1

        // Timer ad alta frequenza per scansionare la griglia
        let timer = Timer(timeInterval: 0.005, repeats: true) { [weak self] _ in
            guard let self = self, self.state == .looping else { return }

            let currentTime = ProcessInfo.processInfo.systemUptime
            guard let startTime = self.loopStartTime else { return }
            
            let elapsed = currentTime - startTime
            let currentOffset = elapsed.truncatingRemainder(dividingBy: self.loopDuration)
            let currentStepIdx = Int(floor(currentOffset / self.stepDuration)) % self.totalSteps

            // Aggiorna la playhead per la View
            if self.currentStep != currentStepIdx {
                DispatchQueue.main.async {
                    self.currentStep = currentStepIdx
                }
            }

            // Trigger dei suoni quando scatta il nuovo step
            if currentStepIdx != self.lastTriggeredStep {
                self.triggerStep(currentStepIdx)
                self.lastTriggeredStep = currentStepIdx
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        self.playbackTimer = timer
    }
    
    private func triggerStep(_ stepIndex: Int) {
        for (instrumentID, steps) in grid {
            if steps[stepIndex] && !mutedInstruments.contains(instrumentID) {
                AudioEngineManager.shared.playSample(named: instrumentID)
            }
        }
    }
    
    func stopPlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        currentStep = -1
    }

    // MARK: - Reset

    func reset() {
        silenceTimer?.invalidate()
        playbackTimer?.invalidate()
        rawEvents.removeAll()
        resetGrid()
        loopStartTime = nil
        calculatedBPM = 0
        state = .idle
        currentStep = -1
        AudioEngineManager.shared.stopAllSamples()
    }
}