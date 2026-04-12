import SwiftUI

struct StandardModeView: View {
    @ObservedObject var motionManager: MotionManager
    let visualEffects: [VisualEffect]
    @ObservedObject var licenseManager = LicenseManager.shared

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
            
            if isCustom && !licenseManager.isUnlocked {
                LicenseView()
                    .padding(.top, 8)
            } else {
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}
