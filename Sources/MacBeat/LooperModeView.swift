import SwiftUI

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
        .padding(.vertical, 12)
    }

    private var statusColor: Color {
        switch looper.state {
        case .recording: return .red
        case .looping:   return .green
        default:         return Color(nsColor: .tertiaryLabelColor)
        }
    }
}
