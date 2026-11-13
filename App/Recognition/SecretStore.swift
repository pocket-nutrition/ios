// SPDX-License-Identifier: MPL-2.0

import Foundation
import Security

/// Where the recognition server's API key lives, behind a protocol so it can be faked.
///
/// A key is a credential, so it goes in the Keychain and not in `UserDefaults` (where the plain-URL
/// `ApiSettings` override rightly lives).
protocol SecretStoring: Sendable {
    func read() throws -> String?
    func write(_ secret: String) throws
    func delete() throws
}

struct KeychainError: Error, LocalizedError, Sendable {
    let status: OSStatus

    var errorDescription: String? {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
    }
}

/// Generic-password Keychain item, readable only while the device is unlocked and never migrated to
/// another device or restored from a backup (`ThisDeviceOnly`).
struct KeychainSecretStore: SecretStoring {

    static let recognitionApiKey = KeychainSecretStore(
        service: "org.pocketnutrition.recognition", account: "api-key"
    )

    let service: String
    let account: String

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ secret: String) throws {
        let data = Data(secret.utf8)
        let update = SecItemUpdate(
            query as CFDictionary, [kSecValueData as String: data] as CFDictionary
        )
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError(status: update) }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}
