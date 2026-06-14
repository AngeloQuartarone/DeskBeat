import SwiftUI

@main
struct DeskBeatApp: App {
    @StateObject private var motionManager = MotionManager.shared

    private var menuBarIcon: NSImage? {
        guard let logoURL = Bundle.module.url(forResource: "logo", withExtension: "png", subdirectory: "images"),
              let image = NSImage(contentsOf: logoURL) else { return nil }
        
        // Resize per la menu bar
        let size = NSSize(width: 18, height: 18)
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        newImage.unlockFocus()
        
        // Se il logo è monocromatico o con trasparenze, impostare isTemplate a true aiuta col dark/light mode
        // ma lasciamo la scelta ai colori originali per ora.
        return newImage
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(motionManager: motionManager)
        } label: {
            if let icon = menuBarIcon {
                Image(nsImage: icon)
            } else {
                Image(systemName: "music.note")
                    .renderingMode(.template)
            }
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        
        if let logoURL = Bundle.module.url(forResource: "logo", withExtension: "png", subdirectory: "images"),
           let image = NSImage(contentsOf: logoURL) {
            NSApplication.shared.applicationIconImage = image
        }
        
        DispatchQueue.main.async {
            MotionManager.shared.onTapDetected = { side, rawTap in
                // 1. Looper mode
                if !MotionManager.shared.isShowingSettings && LooperManager.shared.isLooperMode {
                    LooperManager.shared.processTap(rawTap: rawTap)
                    return
                }

                // 2. Standard mode
                let effectiveKit = MotionManager.shared.selectedKit

                let isInverted = MotionManager.shared.isInverted
                let effectiveSide = isInverted ? (side == "LEFT" ? "RIGHT" : "LEFT") : side
                
                let sound: String
                if effectiveKit == "Custom" {
                    sound = (effectiveSide == "LEFT") ? MotionManager.shared.standardSideSound : MotionManager.shared.standardTopSound
                } else {
                    sound = (effectiveSide == "LEFT") ? "snare" : "kick"
                }
                
                AudioEngineManager.shared.playSample(named: sound, source: effectiveSide)
            }
            
            MotionManager.shared.startMonitoring()
        }
    }
}