import Foundation
import Security
import Combine

class LicenseManager: ObservableObject {
    static let shared = LicenseManager()
    
    @Published var isUnlocked: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    // The Gumroad product ID
    private let productId = "ITtkGZGt3UZvT1guTx787Q=="
    private let keychainService = "com.macbeat.license"
    private let keychainAccount = "gumroad_license"
    
    private init() {
        checkLocalLicense()
    }
    
    /// Checks the Keychain for an existing valid license flag/token.
    /// If found, unlocks the app immediately without network calls (Offline Mode).
    private func checkLocalLicense() {
        if let key = loadLicenseFromKeychain() {
            print("🔐 [Gumroad] Local license found in keychain: \(key.prefix(8))... Unlocking!")
            self.isUnlocked = true
        } else {
            print("🔐 [Gumroad] No local license found in keychain.")
        }
    }
    
    /// Verifies the given license key with Gumroad API.
    func verifyLicense(key: String) {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            self.errorMessage = "Please enter a valid license key."
            return
        }
        
        self.isLoading = true
        self.errorMessage = nil
        print("🔧 [Gumroad] Starting API verification for key: \(trimmedKey)")
        
        guard let url = URL(string: "https://api.gumroad.com/v2/licenses/verify") else {
            self.errorMessage = "Invalid API URL."
            self.isLoading = false
            print("❌ [Gumroad] Invalid API URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Prepare body
        let bodyParameters = [
            "product_id": productId,
            "license_key": trimmedKey,
            "increment_uses_count": "true"
        ]
        
        print("🔧 [Gumroad] URL: \(url.absoluteString)")
        print("🔧 [Gumroad] Body Parameters: \(bodyParameters)")
        
        let bodyString = bodyParameters.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                
                if let error = error {
                    print("❌ [Gumroad] Network error: \(error.localizedDescription)")
                    self.errorMessage = "Network error: \(error.localizedDescription)"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("🔧 [Gumroad] HTTP Status Code: \(httpResponse.statusCode)")
                }
                
                guard let data = data else {
                    print("❌ [Gumroad] No data received from server.")
                    self.errorMessage = "No data received from server."
                    return
                }
                
                let dataString = String(data: data, encoding: .utf8) ?? "Unable to decode string from data"
                print("🔧 [Gumroad] Raw Response Data:\n\(dataString)")
                
                do {
                    let decoder = JSONDecoder()
                    let gumroadResponse = try decoder.decode(GumroadResponse.self, from: data)
                    
                    if gumroadResponse.success == true {
                        print("✅ [Gumroad] API returned success. Checking purchase status...")
                        
                        // Check if it's refunded or chargebacked
                        let refunded = gumroadResponse.purchase?.refunded ?? false
                        let chargebacked = gumroadResponse.purchase?.chargebacked ?? false
                        
                        if refunded {
                            print("❌ [Gumroad] License was refunded.")
                            self.errorMessage = "This license has been refunded and is no longer valid."
                        } else if chargebacked {
                            print("❌ [Gumroad] License was chargebacked.")
                            self.errorMessage = "This license has been chargebacked."
                        } else {
                            
                            #if !DEBUG
                            // Production Mode: Strict 1-use limit to prevent piracy
                            let uses = gumroadResponse.uses ?? 1
                            if uses > 1 {
                                print("❌ [Gumroad] License already in use (uses: \(uses)).")
                                self.errorMessage = "This license key is already in use on another Mac."
                                return
                            }
                            #else
                            // Debug Mode: Ignore uses count for Developer testing
                            print("⚠️ [Gumroad] Debug Mode: Ignoring uses count (uses: \(gumroadResponse.uses ?? 1)).")
                            #endif
                            
                            // Valid license!
                            print("✅ [Gumroad] License is valid! Saving to keychain...")
                            self.saveLicenseToKeychain(key: trimmedKey)
                            self.isUnlocked = true
                        }
                    } else {
                        let msg = gumroadResponse.message ?? "Invalid license key."
                        print("❌ [Gumroad] API returned failure: \(msg)")
                        self.errorMessage = msg
                    }
                    
                } catch {
                    print("❌ [Gumroad] Failed to parse JSON response: \(error)")
                    self.errorMessage = "Failed to parse verification response."
                }
            }
        }.resume()
    }
    
    // MARK: - Keychain Methods
    
    private func saveLicenseToKeychain(key: String) {
        guard let data = key.data(using: .utf8) else { return }
        
        // Remove strictly any previous item to avoid errSecDuplicateItem
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data
        ]
        
        SecItemAdd(addQuery as CFDictionary, nil)
    }
    
    private func loadLicenseFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    #if DEBUG
    // Useful for testing / resetting the state locally during development
    func clearLicense() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        self.isUnlocked = false
    }
    #endif
}

// MARK: - API Response Models

struct GumroadResponse: Codable {
    let success: Bool
    let uses: Int?
    let purchase: GumroadPurchase?
    let message: String?
}

struct GumroadPurchase: Codable {
    let id: String?
    let refunded: Bool?
    let chargebacked: Bool?
    
    // Use CodingKeys in case we need more fields later, we gracefully ignore unspecified fields
}
