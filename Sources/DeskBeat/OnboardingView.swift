import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentStep = 0
    @AppStorage("hasShownOnboarding") var hasShownOnboarding: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .padding(16)
            }
            
            ZStack {
                if currentStep == 0 {
                    OnboardingStepView(
                        imageName: "square.grid.3x1.below.line.grid.1x2",
                        title: "Surface Stability",
                        description: "Position your MacBook on a firm, stable surface. Solid wood or metal desks provide the most accurate acoustic transmission."
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                } else if currentStep == 1 {
                    OnboardingStepView(
                        imageName: "hand.tap.fill",
                        title: "Kinetic Input Zones",
                        description: "Strike the desk area near the trackpad for the Kick drum, and the sides of the chassis for the Snare."
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                } else {
                    OnboardingStepView(
                        imageName: "slider.horizontal.3",
                        title: "Signal Calibration",
                        description: "Perform a few natural taps. Adjust the Sensitivity slider in Settings for a precise response."
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                }
            }
            .frame(height: 280)
            
            // Indicators
            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.bottom, 24)
            
            // Footer Action
            Button(action: {
                if currentStep < 2 {
                    withAnimation { currentStep += 1 }
                } else {
                    withAnimation {
                        hasShownOnboarding = true
                        isPresented = false
                    }
                }
            }) {
                Text(currentStep < 2 ? "Next" : "Start Playing")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .frame(width: 360, height: 440)
        .background(.regularMaterial)
    }
}

struct OnboardingStepView: View {
    let imageName: String
    let title: String
    let description: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: imageName)
                .font(.system(size: 54))
                .foregroundStyle(Color.accentColor)
                .frame(height: 80)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .lineSpacing(4)
            }
            Spacer()
        }
    }
}
