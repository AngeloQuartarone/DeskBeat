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
                if LooperManager.shared.isLooperMode {
                    // Modalità Looper
                    LooperManager.shared.processTap(rawTap: rawTap)
                } else {
                    // Modalità Standard con selezione del Kit
                    let kit = MotionManager.shared.selectedKit
                    let isInverted = MotionManager.shared.isInverted
                    
                    // Se invertito, scambiamo il suono associato al lato fisico
                    let effectiveSide = isInverted ? (side == "LEFT" ? "RIGHT" : "LEFT") : side
                    
                    let sound: String
                    if kit == "Bongos" {
                        sound = (effectiveSide == "LEFT") ? "bongo1" : "bongo2"
                    } else {
                        sound = (effectiveSide == "LEFT") ? "snare" : "kick"
                    }
                    
                    AudioEngineManager.shared.playSample(named: sound)
                }
            }
            
            MotionManager.shared.startMonitoring()
        }
    }
}