// SPDX-License-Identifier: MPL-2.0

import Foundation
import PocketNutritionVault

/// The vault server the person last checked. A plain preference (`UserDefaults`): an address is not a
/// secret. The session that proves who they are lives in the Keychain, never here.
enum VaultSettings {

    static let defaultServerURL = "https://vault.pocketnutrition.org"
    static let defaultServerHost = "vault.pocketnutrition.org"

    private static let urlKey = "vaultServerURL"

    /// What the server field starts with: the last address checked, or the official vault.
    static var rawServerURL: String {
        UserDefaults.standard.string(forKey: urlKey) ?? defaultServerURL
    }

    /// The host of an address as typed, for display; the address itself when it has none.
    static func hostLabel(_ raw: String) -> String {
        URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines))?.host() ?? raw
    }

    static func remember(serverURL: String) {
        UserDefaults.standard.set(serverURL, forKey: urlKey)
    }
}

/// The linked vault session, as one Keychain item. `ThisDeviceOnly` and unlocked-only, like the
/// recognition key: it holds the user key, so it must never migrate or restore from a backup.
extension KeychainSecretStore: VaultSecretStoring {
    static let vaultSession = KeychainSecretStore(service: "org.pocketnutrition.vault", account: "session")
}

/// A fresh install starts with empty `UserDefaults` but not an empty Keychain, so a missing marker means
/// "this installation never linked anything".
struct UserDefaultsInstallMarker: VaultInstallMarking {

    private static let key = "vaultInstallMarker"

    var hasLaunchedBefore: Bool { UserDefaults.standard.bool(forKey: Self.key) }

    func markLaunched() { UserDefaults.standard.set(true, forKey: Self.key) }
}

extension VaultAccountModel {

    /// The production wiring: the real server client, the Keychain, and the saved address.
    convenience init(deviceLabel: String) {
        self.init(
            deviceLabel: deviceLabel,
            makeServer: { VaultClient(baseURL: $0) },
            sessions: VaultSessionStore(secrets: KeychainSecretStore.vaultSession),
            install: UserDefaultsInstallMarker(),
            rememberServerURL: { VaultSettings.remember(serverURL: $0) }
        )
    }
}

extension VaultInbox {

    /// The vault access of the session this phone is linked with, or nil when it is not linked (results
    /// then come back through the recognition ticket).
    static func live() -> VaultInbox? {
        guard let session = VaultSessionStore(secrets: KeychainSecretStore.vaultSession).load() else { return nil }
        return VaultInbox(session: session, server: VaultClient(baseURL: session.serverURL))
    }
}

extension VaultSecurityModel {

    /// The production wiring: the real server client and the Keychain session.
    static func live() -> VaultSecurityModel {
        VaultSecurityModel(
            makeServer: { VaultClient(baseURL: $0) },
            sessions: VaultSessionStore(secrets: KeychainSecretStore.vaultSession))
    }
}
