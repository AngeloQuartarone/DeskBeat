import SwiftUI
import Cocoa
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var motionManager: MotionManager
    @ObservedObject var looper: LooperManager
    @ObservedObject var audioEngine = AudioEngineManager.shared
    @Binding var showingOnboarding: Bool
    
    @State private var refreshID = UUID()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                SettingsSection(title: "SENSITIVITY") {
                    HStack {
                        Text("Level")
                            .font(.system(size: 12))
                        Spacer()
                        Text("\(motionManager.sensitivityLevel)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Picker("Level", selection: $motionManager.sensitivityLevel) {
                        Text("Rigid").tag(1)
                        Text("Balanced").tag(2)
                        Text("Resonant").tag(3)
                        Text("Agile").tag(4)
                        Text("Hyper").tag(5)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .transaction { $0.animation = nil }
                }

                Divider().opacity(0.3)

                Group {
                    SettingsSection(title: "LOOPER") {
                        MacToggleRow(label: "Quantize rhythm", isOn: $looper.isQuantized)
                        MacMenuRow(label: "Trigger with", selection: $looper.targetInput, options: [
                            ("TOP",  "Top hit"),
                            ("SIDE", "Side hit"),
                        ])
                    }

                    Divider().opacity(0.3)

                    SettingsSection(title: "USER SOUNDS") {
                        HStack {
                            Spacer()
                            Button(action: addSound) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Sounds")
                                }
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.bottom, 4)

                        let userSounds = audioEngine.userSounds
                        
                        if userSounds.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "waveform.badge.plus")
                                    .foregroundStyle(.secondary)
                                Text("Add your .wav or .mp3 samples")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(Color.primary.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            VStack(spacing: 6) {
                                ForEach(userSounds, id: \.self) { sound in
                                    HStack {
                                        Image(systemName: "waveform")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                        
                                        Text(sound)
                                            .font(.system(size: 11, weight: .medium))
                                            .lineLimit(1)
                                        
                                        Spacer()
                                        
                                        Button {
                                            AudioEngineManager.shared.removeUserSound(named: sound)
                                            looper.setupDefaultPads()
                                            refreshID = UUID()
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.red.opacity(0.8))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 10)
                                    .background(Color.primary.opacity(0.04))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                    .id(refreshID)

                    Divider().opacity(0.3)

                    SettingsSection(title: "ADVANCED") {
                        MacToggleRow(label: "Play in background", isOn: $motionManager.playInBackground)
                        
                        HStack {
                            Text("Setup Guide")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Button("Show Guide") {
                                showingOnboarding = true
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                        }
                        .padding(.top, 4)
                    }
                }

                Spacer(minLength: 24)
            }
        }
        .frame(height: 380) // Altezza leggermente ridotta grazie alle spaziature ottimizzate
    }

    private func addSound() {
        NSApp.activate(ignoringOtherApps: true)
        
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.wav, .mp3]
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                _ = AudioEngineManager.shared.addUserSound(from: url)
            }
            looper.setupDefaultPads()
            refreshID = UUID()
        }
        
        NSApp.activate(ignoringOtherApps: true)
    }
}
