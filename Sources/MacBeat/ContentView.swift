import SwiftUI
import Cocoa
import UniformTypeIdentifiers

// MARK: - Data Model

struct VisualEffect: Identifiable {
    let id = UUID()
    let instrument: String
    let source: String?
}

enum AppTab { case play, settings }

// MARK: - Main Content View

struct ContentView: View {
    @ObservedObject var motionManager: MotionManager
    @ObservedObject var looper = LooperManager.shared
    @StateObject private var licenseManager = LicenseManager.shared

    @State private var visualEffects: [VisualEffect] = []
    @State private var activeTab: AppTab = .play

    var body: some View {
        VStack(spacing: 0) {

            // Header Title
            HStack(spacing: 8) {
                Spacer()
                
                if let logoURL = Bundle.module.url(forResource: "logo", withExtension: "png", subdirectory: "images"),
                   let nsImage = NSImage(contentsOf: logoURL) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .cornerRadius(4)
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                }
                
                Text("MacBeat")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(
                        LinearGradient(colors: [.primary, .primary.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    )
                Spacer()
            }
            .padding(.top, 14)
            .padding(.bottom, 16)

            // Top bar
            HStack(spacing: 8) {
                if activeTab == .play {
                    Picker("", selection: $looper.isLooperMode) {
                        Text("Standard").tag(false)
                        Text("Looper").tag(true)
                    }
                    .pickerStyle(.segmented)
                } else {
                    Text("Settings")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.8))
                    Spacer()
                }

                Button {
                    // Switch istantaneo, niente withAnimation!
                    activeTab = activeTab == .settings ? .play : .settings
                } label: {
                    Image(systemName: activeTab == .settings ? "xmark.circle.fill" : "gearshape.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(
                            activeTab == .settings
                                ? Color.secondary
                                : Color.secondary.opacity(0.7)
                        )
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider().opacity(0.4)

            // Main Content Area
            ZStack {
                if activeTab == .play {
                    if !looper.isLooperMode {
                        StandardModeView(motionManager: motionManager, visualEffects: visualEffects)
                            .transition(.opacity)
                    } else {
                        if licenseManager.isUnlocked {
                            LooperModeView(looper: looper, visualEffects: visualEffects)
                                .transition(.opacity)
                        } else {
                            LicenseView()
                                .transition(.opacity)
                        }
                    }
                } else {
                    SettingsView(motionManager: motionManager, looper: looper)
                        .transition(.opacity)
                }
            }

            Divider().opacity(0.4)

            FooterView(motionManager: motionManager)
        }
        .frame(width: 360) // Leggermente allargato per far respirare la UI
        .background(.regularMaterial)
        .onAppear {
            motionManager.isMonitoring = true
            activeTab = .play
        }
        .onDisappear {
            if !motionManager.playInBackground {
                motionManager.isMonitoring = false
                looper.reset()
                AudioEngineManager.shared.silenceApp()
                AudioEngineManager.shared.pauseEngine()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didShowNotification)) { _ in
            motionManager.isMonitoring = true
            activeTab = .play
        }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification)) { _ in
            if !motionManager.playInBackground {
                motionManager.isMonitoring = false
                looper.reset()
                AudioEngineManager.shared.silenceApp()
                AudioEngineManager.shared.pauseEngine()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            silenceIfNeeded()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)) { _ in
            silenceIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MacBeatTriggeredEffect"))) { notification in
            guard let instrument = notification.object as? String else { return }
            let source = notification.userInfo?["source"] as? String
            let effect = VisualEffect(instrument: instrument, source: source)
            visualEffects.append(effect)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                visualEffects.removeAll { $0.id == effect.id }
            }
        }
        .onChange(of: activeTab) { oldValue, newValue in
            motionManager.isShowingSettings = (newValue == .settings)
        }
    }

    private func silenceIfNeeded() {
        if !motionManager.playInBackground {
            motionManager.isMonitoring = false
            looper.reset()
            AudioEngineManager.shared.silenceApp()
            AudioEngineManager.shared.pauseEngine()
        }
        NSApplication.shared.hide(nil)
    }
}