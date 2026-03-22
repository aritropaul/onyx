import Foundation
import Security

@Observable
final class ProfileManager {
    var profile: UserProfile
    var isAuthenticated: Bool { authToken != nil }

    private static let profileDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Onyx", isDirectory: true)
    }()

    private static let profileURL: URL = {
        profileDirectory.appendingPathComponent("profile.json")
    }()

    private static let keychainService = "com.onyx.auth"
    private static let keychainAccount = "jwt"

    init() {
        self.profile = Self.loadProfile() ?? Self.createDefaultProfile()
    }

    // MARK: - Profile Persistence

    func save() {
        let dir = Self.profileDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(profile) {
            try? data.write(to: Self.profileURL, options: .atomic)
        }
    }

    func updateDisplayName(_ name: String) {
        profile.displayName = name
        save()
    }

    func updateProfile(_ updated: UserProfile) {
        profile = updated
        save()
    }

    // MARK: - Auth Token (Keychain)

    var authToken: String? {
        get { Self.readKeychain() }
        set {
            if let token = newValue {
                Self.writeKeychain(token)
            } else {
                Self.deleteKeychain()
            }
        }
    }

    func logout() {
        authToken = nil
        profile.email = nil
        save()
    }

    // MARK: - Private

    private static func loadProfile() -> UserProfile? {
        guard let data = try? Data(contentsOf: profileURL),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else {
            return nil
        }
        return profile
    }

    private static func createDefaultProfile() -> UserProfile {
        let profile = UserProfile(
            id: UUID().uuidString,
            displayName: NSFullUserName()
        )
        let dir = profileDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(profile) {
            try? data.write(to: profileURL, options: .atomic)
        }
        return profile
    }

    // MARK: - Keychain Helpers

    private static func writeKeychain(_ token: String) {
        deleteKeychain()
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
