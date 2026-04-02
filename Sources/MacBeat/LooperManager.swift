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

final class LooperManager: ObservableObject {
    static let shared = LooperManager()

    @Published var isLooperMode: Bool = false
    @Published var targetInput: String = "TOP"
    @Published var currentInstrument: String = "kick"
    @Published var isQuantized: Bool = true // Nuovo: Attiva/Disattiva la quantizzazione

    @Published var state: LooperState = .idle
    @Published var calculatedBPM: Double = 0

    @Published var recordedInstrumentsTracker: Set<String> = []
    
    @Published var availablePads: [InstrumentPad] = []

    private var rawEvents: [(name: String, time: TimeInterval)] = []
    private var activeLoopEvents: [(offset: TimeInterval, instrument: String)] = []

    private var loopStartTime: TimeInterval?
    private var loopDuration: TimeInterval = 0
    private var beatDuration: TimeInterval = 0 // Servirà per la griglia di quantizzazione

    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.5
    private var playbackTimer: Timer?
    private var lastPlayedOffset: TimeInterval = -1.0

    private init() {
        setupDefaultPads()
    }
    
    func setupDefaultPads() {
        let looperSounds = AudioEngineManager.shared.getAvailableSoundFiles(in: "Looper")
        let userSounds = AudioEngineManager.shared.getUserAddedSounds()
        
        let allSounds = looperSounds + userSounds
        
        self.availablePads = allSounds.enumerated().map { index, filename in
            let id = filename
            let name = filename.replacingOccurrences(of: "_", with: " ").capitalized
            let letter = String(name.prefix(1)).uppercased()
            let color = deterministicColor(index: index)
            return InstrumentPad(id: id, name: name, letter: letter, color: color)
        }
        
        // Imposta il primo come default se presente e se quello attuale non è valido
        if !availablePads.contains(where: { $0.id == currentInstrument }) {
            if let first = availablePads.first {
                currentInstrument = first.id
            }
        }
    }
    
    private func deterministicColor(index: Int) -> Color {
        let palette: [Color] = [
            .orange, .blue, .purple, .green, .pink, .mint, .teal, .yellow,
            .indigo, .cyan, .red, .brown
        ]
        return palette[index % palette.count]
    }

    // MARK: - Clear instrument from loop

    /// Removes all events for this instrument from the active loop.
    /// The pad goes back to "empty" state — next tap will overdub it fresh.
    func clearInstrument(_ instrument: String) {
    activeLoopEvents.removeAll { $0.instrument == instrument }
    recordedInstrumentsTracker.remove(instrument)
    
    // Ferma immediatamente la riproduzione del campione per questo strumento specifico
    AudioEngineManager.shared.stopSample(named: instrument)

    // Se non ci sono più eventi nel loop, resetta tutto allo stato "idle"
    if activeLoopEvents.isEmpty {
        reset()
    }
}

    // MARK: - Tap processing

    func processTap(rawTap: String) {
        guard rawTap == targetInput else { return }

        AudioEngineManager.shared.playSample(named: currentInstrument)

        recordedInstrumentsTracker.insert(currentInstrument)
        let now = ProcessInfo.processInfo.systemUptime

        switch state {
        case .idle:
            state = .recording
            loopStartTime = now
            rawEvents = [(currentInstrument, 0.0)]
            resetSilenceTimer(now: now)

        case .recording:
            let elapsed = now - loopStartTime!
            rawEvents.append((currentInstrument, elapsed))
            resetSilenceTimer(now: now)

        case .looping:
            let elapsed = now - loopStartTime!
            let rawOffset = elapsed.truncatingRemainder(dividingBy: loopDuration)
            
            // Applica quantizzazione agli overdub se attiva
            let finalOffset = isQuantized ? quantize(rawOffset) : rawOffset
            activeLoopEvents.append((offset: finalOffset, instrument: currentInstrument))
        }
    }

    private func quantize(_ offset: TimeInterval) -> TimeInterval {
        // Griglia: 1/16th notes (4 per battito)
        let gridSize = beatDuration / 4.0
        let quantized = round(offset / gridSize) * gridSize
        
        // Evita che sfori la durata del loop (raro ma possibile per arrotondamento)
        return quantized >= loopDuration ? 0 : quantized
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

        var intervals: [TimeInterval] = []
        for i in 1..<rawEvents.count {
            intervals.append(rawEvents[i].time - rawEvents[i-1].time)
        }
        intervals.sort()
        var roughBeat = intervals[intervals.count / 2]
        while roughBeat < 0.33 { roughBeat *= 2 }
        while roughBeat > 1.0  { roughBeat /= 2 }

        let totalTappedTime = rawEvents.last!.time
        let beatsBetweenFirstAndLast = max(1.0, round(totalTappedTime / roughBeat))
        let preciseBeat = totalTappedTime / beatsBetweenFirstAndLast
        
        self.beatDuration = preciseBeat
        self.calculatedBPM = 60.0 / preciseBeat

        let totalBeats = beatsBetweenFirstAndLast + 1
        let barsCount = max(1, Int(round(totalBeats / 4.0)))
        self.loopDuration = Double(barsCount) * 4.0 * preciseBeat

        self.activeLoopEvents.removeAll()
        for event in rawEvents {
            var exactOffset = event.time
            if exactOffset >= loopDuration {
                exactOffset = exactOffset.truncatingRemainder(dividingBy: loopDuration)
            }
            
            // Applica quantizzazione se attiva
            let finalOffset = isQuantized ? quantize(exactOffset) : exactOffset
            self.activeLoopEvents.append((offset: finalOffset, instrument: event.name))
        }

        self.loopStartTime = ProcessInfo.processInfo.systemUptime
        self.state = .looping
        startPlayback()
    }

    // MARK: - Playback
    
    /// Avvia il playback del loop dal principio
    func startPlayback() {
        playbackTimer?.invalidate()
        self.lastPlayedOffset = -0.001

        let timer = Timer(timeInterval: 0.01, repeats: true) { [weak self] _ in
            guard let self = self, self.state == .looping else { return }

            let currentTime = ProcessInfo.processInfo.systemUptime
            let currentOffset = (currentTime - self.loopStartTime!).truncatingRemainder(dividingBy: self.loopDuration)

            if currentOffset < self.lastPlayedOffset {
                self.lastPlayedOffset = -0.001
            }

            for event in self.activeLoopEvents {
                guard event.offset > self.lastPlayedOffset && event.offset <= currentOffset else { continue }

                AudioEngineManager.shared.playSample(named: event.instrument)

            }

            self.lastPlayedOffset = currentOffset
        }

        RunLoop.main.add(timer, forMode: .common)
        self.playbackTimer = timer
    }
    
    /// Ferma il playback del loop
    func stopPlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    // MARK: - Reset

    func reset() {
        silenceTimer?.invalidate()
        playbackTimer?.invalidate()
        rawEvents.removeAll()
        activeLoopEvents.removeAll()
        loopStartTime = nil
        calculatedBPM = 0
        state = .idle
        recordedInstrumentsTracker.removeAll()
        
        // Ferma immediatamente tutti i suoni in riproduzione
        AudioEngineManager.shared.stopAllSamples()
    }
}