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

    @State private var visualEffects: [VisualEffect] = []
    @State private var activeTab: AppTab = .play

    var body: some View {
        VStack(spacing: 0) {

            // Header Title
            HStack {
                Spacer()
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
                        LooperModeView(looper: looper, visualEffects: visualEffects)
                            .transition(.opacity)
                    }
                } else {
                    SettingsView(motionManager: motionManager, looper: looper)
                        .transition(.opacity)
                }
            }

            Divider().opacity(0.4)

            FooterView(motionManager: motionManager)
        }
        .frame(width: 290) // Leggermente allargato per far respirare la UI
        .background(.regularMaterial)
        .onAppear {
            motionManager.isMonitoring = true
            activeTab = .play
        }
        .onDisappear {
            if !motionManager.playInBackground {
                motionManager.isMonitoring = false
                looper.reset()
                AudioEngineManager.shared.stopAllSamples()
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
            AudioEngineManager.shared.stopAllSamples()
        }
        NSApplication.shared.hide(nil)
    }
}

// MARK: - Standard Mode

struct StandardModeView: View {
    @ObservedObject var motionManager: MotionManager
    let visualEffects: [VisualEffect]

    var body: some View {
        VStack(spacing: 16) {
            
            // Kit Selector
            HStack(spacing: 6) {
                ForEach(["Classic", "Custom"], id: \.self) { kit in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            motionManager.selectedKit = kit
                        }
                    } label: {
                        Text(kit)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(motionManager.selectedKit == kit ? Color.accentColor : Color.primary.opacity(0.05))
                            .foregroundStyle(motionManager.selectedKit == kit ? .white : .primary.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                            )
                            .shadow(color: motionManager.selectedKit == kit ? Color.accentColor.opacity(0.3) : .clear, radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }

            let isCustom = motionManager.selectedKit == "Custom"
            let leftSound  = isCustom ? motionManager.standardSideSound : "snare"
            let rightSound = isCustom ? motionManager.standardTopSound  : "kick"
            
            let leftLabel  = leftSound.uppercased()
            let rightLabel = rightSound.uppercased()

            HStack(spacing: 10) {
                DrumPadView(
                    label:      motionManager.isInverted ? rightLabel : leftLabel,
                    accent:     motionManager.isInverted ? .orange : .blue,
                    iconName:   "chevron.right",
                    isFlashing: visualEffects.contains { $0.source == (motionManager.isInverted ? "RIGHT" : "LEFT") },
                    isCustomizable: isCustom,
                    onSoundSelected: { sound in
                        if motionManager.isInverted {
                            motionManager.standardTopSound = sound
                        } else {
                            motionManager.standardSideSound = sound
                        }
                    }
                )
                DrumPadView(
                    label:      motionManager.isInverted ? leftLabel : rightLabel,
                    accent:     motionManager.isInverted ? .blue : .orange,
                    iconName:   "chevron.down",
                    isFlashing: visualEffects.contains { $0.source == (motionManager.isInverted ? "LEFT" : "RIGHT") },
                    isCustomizable: isCustom,
                    onSoundSelected: { sound in
                        if motionManager.isInverted {
                            motionManager.standardSideSound = sound
                        } else {
                            motionManager.standardTopSound = sound
                        }
                    }
                )
            }
            .frame(height: 65)

            MacToggleRow(label: "Invert sides", isOn: $motionManager.isInverted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

// MARK: - Looper Mode

struct LooperModeView: View {
    @ObservedObject var looper: LooperManager
    let visualEffects: [VisualEffect]

    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        VStack(spacing: 12) { // Ridotto da 14 a 12

            // Status chip
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.6), radius: 2)
                    .opacity(looper.state == .recording ? pulseOpacity : 1)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                            pulseOpacity = 0.2
                        }
                    }

                Text(looper.state.rawValue.capitalized)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.8))

                Spacer()

                // Usiamo un Group o semplicemente le condition
                if looper.state == .looping {
                    Text("\(Int(looper.calculatedBPM)) BPM")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.green.opacity(0.15))
                        .clipShape(Capsule())
                } else if looper.state == .idle {
                    Text("Start tapping a beat")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36) // <-- ECCO IL FIX: Blocchiamo l'altezza in modo rigido
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))

            // Instrument pad grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) { // Spaziatura verticale ridotta da 10 a 6
                ForEach(looper.availablePads) { pad in
                    VStack(spacing: 4) { // Spazio tra pad e bottone clear ridotto da 6 a 4
                        LooperPadView(
                            letter:     pad.letter,
                            name:       pad.name,
                            accent:     pad.color,
                            isSelected: looper.currentInstrument == pad.id,
                            isFlashing: visualEffects.contains { $0.instrument == pad.id },
                            onTap:      { looper.currentInstrument = pad.id }
                        )
                        .frame(height: 60) // Altezza pad compattata (era 65)

                        if looper.recordedInstrumentsTracker.contains(pad.id) && looper.state == .looping {
                            Button {
                                looper.clearInstrument(pad.id)
                            } label: {
                                Text("clear")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .textCase(.uppercase)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 16) // Altezza tasto compattata da 18 a 16
                                    .background(Color.primary.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear.frame(height: 16) // Coerente con il tasto clear
                        }
                    }
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: looper.state)

            // Reset all
            Button { looper.reset() } label: {
                Label("Clear all", systemImage: "trash.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity).frame(height: 30)
                    .foregroundStyle(.red.opacity(0.9))
                    .background(.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.red.opacity(0.2), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12) // Tolto un po' di padding generale per stringere tutto
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
                // Sfondo con gradiente leggero per un look più moderno
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [padFillStart, padFillEnd],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(padStroke, lineWidth: isSelected ? 1.5 : 0.5)
                    )
                    .shadow(color: isSelected ? accent.opacity(0.2) : .clear, radius: 3, y: 1)

                if isFlashing {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accent.opacity(0.4))
                        .transition(.opacity.animation(.easeOut(duration: 0.1)))
                }

                VStack(spacing: 2) {
                    Text(letter)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(isSelected ? accent : accent.opacity(0.7))

                    Text(name)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .textCase(.uppercase)
                        .tracking(0.5)
                        // Aggiungi esplicitamente "Color." prima di primary e secondary
                        .foregroundStyle(isSelected ? Color.primary.opacity(0.8) : Color.secondary.opacity(0.8))
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isFlashing ? 0.92 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: isFlashing)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var padFillStart: Color {
        isSelected ? accent.opacity(0.2) : accent.opacity(0.05)
    }
    
    private var padFillEnd: Color {
        isSelected ? accent.opacity(0.1) : accent.opacity(0.1)
    }

    private var padStroke: Color {
        isSelected ? accent.opacity(0.8) : accent.opacity(0.2)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var motionManager: MotionManager
    @ObservedObject var looper: LooperManager
    @ObservedObject var audioEngine = AudioEngineManager.shared
    
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
                        Text("Low").tag(1)
                        Text("Med").tag(2)
                        Text("High").tag(3)
                        Text("Extra").tag(4)
                        Text("Max").tag(5)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .transaction { $0.animation = nil }
                }

                Divider().opacity(0.3)

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

// Support view for consistent settings sections
struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.8)

            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
                .keyboardShortcut("q", modifiers: .command) // Aggiunta scorciatoia da tastiera nativa
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
            Spacer()
        }
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.02))
    }
}

// MARK: - Reusable Components

struct DrumPadView: View {
    let label: String
    let accent: Color
    let iconName: String
    let isFlashing: Bool
    
    var isCustomizable: Bool = false
    var onSoundSelected: ((String) -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        ZStack {
            // Sfondo con gradiente per profondità
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(isFlashing ? 0.35 : 0.08),
                            accent.opacity(isFlashing ? 0.45 : 0.15)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(accent.opacity(isFlashing ? 0.7 : 0.25), lineWidth: 0.5)
                )

            if isFlashing {
                RoundedRectangle(cornerRadius: 8)
                    .fill(accent.opacity(0.4))
                    .transition(.opacity.animation(.easeOut(duration: 0.1)))
            }

            if isCustomizable && isHovered {
                Menu {
                    let baseSounds = AudioEngineManager.shared.getAvailableSoundFiles(in: "Base")
                    let userSounds = AudioEngineManager.shared.userSounds
                    
                    Section("Base Sounds") {
                        ForEach(baseSounds, id: \.self) { sound in
                            Button(sound.capitalized) { onSoundSelected?(sound) }
                        }
                    }
                    
                    if !userSounds.isEmpty {
                        Section("User Sounds") {
                            ForEach(userSounds, id: \.self) { sound in
                                Button(sound) { onSoundSelected?(sound) }
                            }
                        }
                    }
                } label: {
                    ZStack {
                        Color.white.opacity(0.001)
                        Text("MODIFY")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(1.0)
                            .foregroundStyle(accent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            } else {
                VStack(spacing: 6) {
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accent.opacity(0.9))

                    Text(label)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        .onHover { hovering in
            withAnimation { isHovered = hovering }
        }
        .scaleEffect(isFlashing ? 0.94 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: isFlashing)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MacToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
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
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize()
            
            Spacer()
            
            Picker("", selection: $selection) {
                ForEach(options, id: \.0) { value, title in
                    Text(title).tag(value)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 120)
            .transaction { $0.animation = nil } // <-- AGGIUNGI QUESTO
        }
    }
}