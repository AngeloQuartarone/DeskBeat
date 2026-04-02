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

// MARK: - Footer

struct FooterView: View {
    @ObservedObject var motionManager: MotionManager

    var body: some View {
        HStack {
            Spacer()
            Button("Quit MacBeat") { NSApplication.shared.terminate(nil) }
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
