import SwiftUI

@main
struct MacBeatApp: App {
    @StateObject private var motionManager = MotionManager.shared

    var body: some Scene {
        MenuBarExtra {
            ContentView(motionManager: motionManager)
        } label: {
            Image(systemName: "music.note")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        
        DispatchQueue.main.async {
            MotionManager.shared.onTapDetected = { side, rawTap in
                // Se siamo nelle impostazioni, forziamo sempre la modalità Standard per testare la sensibilità
                if !MotionManager.shared.isShowingSettings && LooperManager.shared.isLooperMode {
                    // Modalità Looper (solo se non siamo in Settings)
                    LooperManager.shared.processTap(rawTap: rawTap)
                } else {
                    // Modalità Standard (come fallback o se siamo in Settings)
                    let kit = MotionManager.shared.selectedKit
                    let isInverted = MotionManager.shared.isInverted
                    
                    // Se invertito, scambiamo il suono associato al lato fisico
                    let effectiveSide = isInverted ? (side == "LEFT" ? "RIGHT" : "LEFT") : side
                    
                    let sound: String
                    if kit == "Custom" {
                        sound = (effectiveSide == "LEFT") ? MotionManager.shared.standardSideSound : MotionManager.shared.standardTopSound
                    } else {
                        // Default: Classic (snare on left/side, kick on right/top)
                        sound = (effectiveSide == "LEFT") ? "snare" : "kick"
                    }
                    
                    AudioEngineManager.shared.playSample(named: sound, source: effectiveSide)
                }
            }
            
            MotionManager.shared.startMonitoring()
        }
    }
}