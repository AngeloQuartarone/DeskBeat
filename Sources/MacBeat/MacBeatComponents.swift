import SwiftUI

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
            .transaction { $0.animation = nil }
        }
    }
}

// MARK: - Step Sequencer Components

struct StepSequencerRowView: View {
    let pad: InstrumentPad
    let steps: [Bool]
    let currentStep: Int
    let onStepToggle: (Int) -> Void
    let onPadTap: () -> Void
    let onMuteToggle: () -> Void
    let onClear: () -> Void
    let isSelected: Bool
    let isMuted: Bool

    var body: some View {
        HStack(spacing: 6) {
            // New Controls: Mute & Clear
            HStack(spacing: 4) {
                Button(action: onMuteToggle) {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isMuted ? .red : .secondary)
                        .frame(width: 20, height: 20)
                        .background(isMuted ? .red.opacity(0.15) : Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Mute/Unmute")

                Button(action: onClear) {
                    Image(systemName: "eraser.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Clear Line")
            }
            .padding(.trailing, 2)

            // Instrument Label / Mini Pad
            Button(action: onPadTap) {
                HStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(pad.color.opacity(isSelected ? 0.3 : 0.1))
                            .frame(width: 24, height: 24)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(pad.color.opacity(0.3), lineWidth: 0.5))
                        
                        Text(pad.letter)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(pad.color)
                            .opacity(isMuted ? 0.4 : 1.0)
                    }
                    
                    Text(pad.name)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .frame(width: 50, alignment: .leading)
                        .lineLimit(1)
                        .opacity(isMuted ? 0.4 : 1.0)
                }
            }
            .buttonStyle(.plain)

            // Step Grid
            HStack(spacing: 3) {
                ForEach(0..<steps.count, id: \.self) { index in
                    StepButton(
                        isOn: steps[index],
                        isCurrent: index == currentStep,
                        color: pad.color,
                        isMajor: index % 4 == 0,
                        onToggle: { onStepToggle(index) }
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct StepButton: View {
    let isOn: Bool
    let isCurrent: Bool
    let color: Color
    let isMajor: Bool // Every 4 steps
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(fillColor)
                    .frame(height: 18)
                    .frame(maxWidth: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(isCurrent ? Color.white.opacity(0.8) : Color.clear, lineWidth: 1.5)
                    )
                
                if isCurrent {
                    // Glow effect for playhead
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.3))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var fillColor: Color {
        if isOn {
            return color.opacity(isCurrent ? 1.0 : 0.8)
        } else {
            // Fondo grigio/scuro per step spenti, leggermente diverso ogni 4 per orientamento
            return isMajor ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06)
        }
    }
}

// MARK: - Footer

struct FooterView: View {
    @ObservedObject var motionManager: MotionManager

    var body: some View {
        HStack {
            Spacer()
            Button("Quit MacBeat") { exit(0) }
                .font(.system(size: 11, weight: .medium))
                .keyboardShortcut("q", modifiers: .command)
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
