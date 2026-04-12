import SwiftUI

struct LicenseView: View {
    @ObservedObject var licenseManager = LicenseManager.shared
    @State private var licenseKey: String = ""
    @Environment(\.openURL) var openURL
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 36))
                .foregroundStyle(
                    LinearGradient(colors: [.accentColor, .accentColor.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                )
                .padding(.top, 24)
            
            VStack(spacing: 6) {
                Text("Unlock the Desktop Studio")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                
                Text("Enter your DeskBeat license key to access the professional Looper engine and custom signal chain.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .lineSpacing(2)
            }
            
            VStack(spacing: 12) {
                TextField("License Key (e.g. XXXX-XXXX-XXXX-XXXX)", text: $licenseKey)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .font(.system(size: 12, design: .monospaced))
                    .disabled(licenseManager.isLoading)
                
                if let errorMessage = licenseManager.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Button(action: {
                    licenseManager.verifyLicense(key: licenseKey)
                }) {
                    ZStack {
                        if licenseManager.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Verify License")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(licenseKey.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.2) : Color.accentColor)
                    .foregroundColor(licenseKey.trimmingCharacters(in: .whitespaces).isEmpty ? .primary.opacity(0.5) : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || licenseManager.isLoading)
            }
            .padding(.horizontal, 24)
            
            Spacer(minLength: 4)
            
            VStack(spacing: 10) {
                Divider().opacity(0.5)
                
                HStack(spacing: 4) {
                    Text("Don't have a license?")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    
                    Button("Upgrade to Pro") {
                        // Change this URL to your actual Gumroad checkout link
                        if let url = URL(string: "https://gumroad.com/l/deskbeat") {
                            openURL(url)
                        }
                    }
                    .font(.system(size: 11, weight: .bold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .onHover { isHovered in
                        if isHovered {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .frame(minHeight: 320)
    }
}
