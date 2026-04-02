import SwiftUI
import Cocoa

// MARK: - Data Model

struct VisualEffect: Identifiable {
    let id = UUID()
    let instrument: String
}

enum AppTab { case play, settings }

// MARK: - Main Content View

struct ContentView: View {
    @ObservedObject var motionManager: MotionManager
    @ObservedObject var looper = LooperManager.shared

    @State private var visualEffects: [VisualEffect] = []
    @State private var activeTab: AppTab = .play

    var body: some View {
        VStack(spacing: 0) {

            // Header Title
            HStack {
                Spacer()
                Text("MacBeat")
                    .font(.system(size: 16, weight: .black, design: .default))
                    .tracking(0.5) // Un tracking minore rende il testo un blocco unico e più solido
                    .foregroundStyle(Color.primary) // Colore pieno al 100%
                Spacer()
            }
            .padding(.top, 12)
            .padding(.bottom, 20) // Spazio extra sotto

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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        activeTab = activeTab == .settings ? .play : .settings
                    }
                } label: {
                    Image(systemName: activeTab == .settings ? "xmark.circle.fill" : "gearshape.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(
                            activeTab == .settings
                                ? Color(nsColor: .tertiaryLabelColor)
                                : Color(nsColor: .secondaryLabelColor)
                        )
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .padding(.top, 4)

            Divider().opacity(0.5)

            if activeTab == .play {
                if !looper.isLooperMode {
                    StandardModeView(motionManager: motionManager, visualEffects: visualEffects)
                } else {
                    LooperModeView(looper: looper, visualEffects: visualEffects)
                }
            } else {
                SettingsView(motionManager: motionManager, looper: looper)
            }

            Divider().opacity(0.5)

            FooterView(motionManager: motionManager)
        }
        .frame(width: 280)
        .background(.regularMaterial)
        // Focus Pause: Quando la tendina appare/scompare
        .onAppear {
            motionManager.isMonitoring = true
        }
        .onDisappear {
            if !motionManager.playInBackground {
                motionManager.isMonitoring = false
                // Reset totale del looper e silenzio immediato
                looper.reset()
                AudioEngineManager.shared.stopAllSamples()
            }
        }
        // Supporto per NSPopover (se usato via AppDelegate o altri wrapper)
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didShowNotification)) { _ in
            motionManager.isMonitoring = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification)) { _ in
            if !motionManager.playInBackground {
                motionManager.isMonitoring = false
                looper.reset()
                AudioEngineManager.shared.stopAllSamples()
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
            let effect = VisualEffect(instrument: instrument)
            visualEffects.append(effect)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                visualEffects.removeAll { $0.id == effect.id }
            }
        }
    }

    private func silenceIfNeeded() {
        if !motionManager.playInBackground {
            motionManager.isMonitoring = false
            looper.reset()
            AudioEngineManager.shared.stopAllSamples()
        }
        // Chiudi la finestra nascondendo l'app (comportamento popover)
        NSApplication.shared.hide(nil)
    }
}

// MARK: - Standard Mode

struct StandardModeView: View {
    @ObservedObject var motionManager: MotionManager
    let visualEffects: [VisualEffect]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(["Classic", "Bongos"], id: \.self) { kit in
                    Button { motionManager.selectedKit = kit } label: {
                        Text(kit)
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                            .background(motionManager.selectedKit == kit ? Color.accentColor : Color.primary.opacity(0.06))
                            .foregroundStyle(motionManager.selectedKit == kit ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            let leftSound  = motionManager.selectedKit == "Bongos" ? "bongo1" : "snare"
            let rightSound = motionManager.selectedKit == "Bongos" ? "bongo2" : "kick"
            
            let leftLabel  = motionManager.selectedKit == "Bongos" ? "BONGO 1" : "SNARE"
            let rightLabel = motionManager.selectedKit == "Bongos" ? "BONGO 2" : "KICK"

            HStack(spacing: 6) {
                DrumPadView(
                    label:      motionManager.isInverted ? rightLabel : leftLabel,
                    accent:     motionManager.isInverted ? .orange : .blue,
                    iconName:   "chevron.right",
                    isFlashing: visualEffects.contains { $0.instrument == (motionManager.isInverted ? rightSound : leftSound) }
                )
                DrumPadView(
                    label:      motionManager.isInverted ? leftLabel : rightLabel,
                    accent:     motionManager.isInverted ? .blue : .orange,
                    iconName:   "chevron.down",
                    isFlashing: visualEffects.contains { $0.instrument == (motionManager.isInverted ? leftSound : rightSound) }
                )
            }
            .frame(height: 60)

            MacToggleRow(label: "Invert sides", isOn: $motionManager.isInverted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Looper Mode

struct LooperModeView: View {
    @ObservedObject var looper: LooperManager
    let visualEffects: [VisualEffect]

    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        VStack(spacing: 10) {

            // Status chip
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .opacity(looper.state == .recording ? pulseOpacity : 1)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                            pulseOpacity = 0.2
                        }
                    }

                Text(looper.state.rawValue)
                    .font(.system(size: 12, weight: .medium))

                Spacer()

                if looper.state == .looping {
                    Text("\(Int(looper.calculatedBPM)) BPM")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.green.opacity(0.12))
                        .clipShape(Capsule())
                } else if looper.state == .idle {
                    Text("Start tapping a beat")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 20)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))

            // Instrument pad grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 4), spacing: 8) {
                ForEach(looper.availablePads) { pad in
                    VStack(spacing: 4) {
                        LooperPadView(
                            letter:     pad.letter,
                            name:       pad.name,
                            accent:     pad.color,
                            isSelected: looper.currentInstrument == pad.id,
                            isFlashing: visualEffects.contains { $0.instrument == pad.id },
                            onTap:      { looper.currentInstrument = pad.id }
                        )
                        .frame(height: 60) // Altezza fissa per il pad

                        // Clear button — only visible when the instrument has recorded events
                        if looper.recordedInstrumentsTracker.contains(pad.id) && looper.state == .looping {
                            Button {
                                looper.clearInstrument(pad.id)
                            } label: {
                                Text("clear")
                                    .font(.system(size: 11, weight: .semibold)) 
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 18)
                                    .background(Color.primary.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.plain)
                        } else {
                            // Placeholder to keep layout stable
                            Color.clear.frame(height: 18)
                        }
                    }
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: looper.state)

            // Reset all
            Button { looper.reset() } label: {
                Label("Clear all", systemImage: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity).frame(height: 26)
                    .foregroundStyle(.red)
                    .background(.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.red.opacity(0.3), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var statusColor: Color {
        switch looper.state {
        case .recording: return .red
        case .looping:   return .green
        default:         return Color(nsColor: .tertiaryLabelColor)
        }
    }
}

// MARK: - Looper Pad View

struct LooperPadView: View {
    let letter:     String
    let name:       String
    let accent:     Color
    let isSelected: Bool
    let isFlashing: Bool
    let onTap:      () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Base background
                RoundedRectangle(cornerRadius: 8)
                    .fill(padFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(padStroke, lineWidth: isSelected ? 1.5 : 0.5)
                    )

                // Flash layer — independent from selection state
                if isFlashing {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accent.opacity(0.38))
                        .transition(.opacity.animation(.easeOut(duration: 0.05)))
                }

                // Content
                VStack(spacing: 3) {
                    Text(letter)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? accent : accent.opacity(0.6))

                    Text(name)
                        .font(.system(size: 8.5, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(isSelected ? .secondary : Color(nsColor: .tertiaryLabelColor))
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isFlashing ? 0.94 : 1)
        .animation(.spring(response: 0.1, dampingFraction: 0.6), value: isFlashing)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var padFill: Color {
        if isSelected { return accent.opacity(0.18) }
        return accent.opacity(0.09)
    }

    private var padStroke: Color {
        if isSelected { return accent.opacity(0.7) }
        return accent.opacity(0.2)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var motionManager: MotionManager
    @ObservedObject var looper: LooperManager

    var body: some View {
        VStack(spacing: 0) {

            VStack(alignment: .leading, spacing: 8) {
                Text("SENSITIVITY")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .tracking(0.6)

                HStack {
                    Text("Sensitivity")
                        .font(.system(size: 12))
                    Spacer()
                    Text("Level \(motionManager.sensitivityLevel)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }

                Picker("Level", selection: $motionManager.sensitivityLevel) {
                    Text("Low").tag(1)
                    Text("Med").tag(2)
                    Text("High").tag(3)
                    Text("Extra").tag(4)
                    Text("Max").tag(5)
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 8) {
                Text("LOOPER")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .tracking(0.6)

                MacToggleRow(label: "Quantize rhythm", isOn: $looper.isQuantized)

                MacMenuRow(label: "Trigger with", selection: $looper.targetInput, options: [
                    ("TOP",  "Top hit"),
                    ("SIDE", "Side hit"),
                ])
            }
            .padding(.horizontal, 12).padding(.vertical, 10)

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 8) {
                Text("SOUNDS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .tracking(0.6)

                HStack(spacing: 10) {
                    Image(systemName: "waveform.badge.plus")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upload your own sounds")
                            .font(.system(size: 12))
                        Text("Coming soon")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }

                    Spacer()

                    Text("Soon")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                }
                .padding(.vertical, 2)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 8) {
                Text("ADVANCED")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .tracking(0.6)

                MacToggleRow(label: "Play in background", isOn: $motionManager.playInBackground)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
    }
}

// MARK: - Footer

struct FooterView: View {
    @ObservedObject var motionManager: MotionManager

    var body: some View {
        HStack {
            Spacer()
            Button("Quit MacBeat") { NSApplication.shared.terminate(nil) }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
            Spacer()
        }
        .padding(.vertical, 10)
        .background(.primary.opacity(0.02))
    }
}

// MARK: - Reusable Components

struct DrumPadView: View {
    let label: String
    let accent: Color
    let iconName: String
    let isFlashing: Bool

    var body: some View {
        ZStack {
            // Base background
            RoundedRectangle(cornerRadius: 9)
                .fill(accent.opacity(isFlashing ? 0.25 : 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(accent.opacity(isFlashing ? 0.6 : 0.22), lineWidth: 0.5)
                )

            // Flash layer
            if isFlashing {
                RoundedRectangle(cornerRadius: 9)
                    .fill(accent.opacity(0.35))
                    .transition(.opacity.animation(.easeOut(duration: 0.05)))
            }

            VStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent.opacity(0.8))

                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
        }
        .scaleEffect(isFlashing ? 0.95 : 1)
        .animation(.spring(response: 0.1, dampingFraction: 0.6), value: isFlashing)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MacToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label).font(.system(size: 12))
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
    }
}

struct MacMenuRow<T: Hashable>: View {
    let label: String
    @Binding var selection: T
    let options: [(T, String)]

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize()
            Picker("", selection: $selection) {
                ForEach(options, id: \.0) { value, title in
                    Text(title).tag(value)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
    }
}