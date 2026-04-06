import SwiftUI

struct LooperModeView: View {
    @ObservedObject var looper: LooperManager
    let visualEffects: [VisualEffect]

    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        VStack(spacing: 12) {

            // Status chip & BPM information
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

                if looper.calculatedBPM > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "metronome.fill")
                            .font(.system(size: 10))
                        Text("\(Int(looper.calculatedBPM)) BPM")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.green.opacity(0.1))
                    .clipShape(Capsule())
                } else if looper.state == .idle {
                    Text("Physical Tap to Start")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))

            // Step Sequencer Track List
            VStack(spacing: 6) {
                ForEach(looper.availablePads) { pad in
                    StepSequencerRowView(
                        pad: pad,
                        steps: looper.grid[pad.id] ?? Array(repeating: false, count: looper.totalSteps),
                        currentStep: looper.currentStep,
                        onStepToggle: { stepIdx in
                            looper.toggleStep(instrument: pad.id, stepIndex: stepIdx)
                        },
                        onPadTap: {
                            looper.currentInstrument = pad.id
                            // Feedback audio immediato
                            AudioEngineManager.shared.playSample(named: pad.id)
                        },
                        onMuteToggle: {
                            looper.toggleMute(instrument: pad.id)
                        },
                        onClear: {
                            looper.clearInstrument(pad.id)
                        },
                        isSelected: looper.currentInstrument == pad.id || visualEffects.contains { $0.instrument == pad.id },
                        isMuted: looper.mutedInstruments.contains(pad.id)
                    )
                }
            }
            .padding(.vertical, 4)

            // Bottom Actions
            HStack(spacing: 8) {
                // Clear all
                Button(action: { looper.reset() }) {
                    Label("Clear", systemImage: "trash.fill")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity).frame(height: 30)
                        .foregroundStyle(.red.opacity(0.9))
                        .background(.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.red.opacity(0.2), lineWidth: 0.5))

                // Quantization toggle
                Button(action: { looper.isQuantized.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: looper.isQuantized ? "grid" : "clock")
                        Text(looper.isQuantized ? "Quantized" : "Free")
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity).frame(height: 30)
                    .foregroundStyle(looper.isQuantized ? .blue : .secondary)
                    .background(looper.isQuantized ? Color.blue.opacity(0.1) : Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(looper.isQuantized ? .blue.opacity(0.2) : .primary.opacity(0.1), lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var statusColor: Color {
        switch looper.state {
        case .recording: return .red
        case .looping:   return .green
        default:         return Color(nsColor: .tertiaryLabelColor)
        }
    }
}
