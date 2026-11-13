// SPDX-License-Identifier: MPL-2.0

import Foundation
import PocketNutritionCore

/// Where the linked session is kept, behind a protocol so tests can use memory and the app the Keychain.
public protocol VaultSecretStoring: Sendable {
    func read() throws -> String?
    func write(_ secret: String) throws
    func delete() throws
}

/// Everything that makes this phone a linked, unlocked device of one vault account. Stored as ONE item so
/// the pieces can never disagree (a device key without its keys, or the reverse).
public struct VaultStoredSession: Codable, Equatable, Sendable {
    public let serverURL: URL
    public let username: String
    public let accountId: String
    /// This device's API key.
    public let apiKey: String
    public let keyId: String
    /// The KDF settings this account was linked with. Later operations must use THESE, never whatever
    /// the server says now: that is what stops a server from downgrading the derivation after the fact.
    public let kdf: VaultKdf
    public let userKey: Data
    public let inboxPublicKey: Data
    public let inboxSecretKey: Data

    public init(
        serverURL: URL, username: String, accountId: String, apiKey: String, keyId: String, kdf: VaultKdf,
        userKey: Data, inboxPublicKey: Data, inboxSecretKey: Data
    ) {
        self.serverURL = serverURL
        self.username = username
        self.accountId = accountId
        self.apiKey = apiKey
        self.keyId = keyId
        self.kdf = kdf
        self.userKey = userKey
        self.inboxPublicKey = inboxPublicKey
        self.inboxSecretKey = inboxSecretKey
    }

    public var keys: VaultUnlockedKeys {
        VaultUnlockedKeys(
            userKey: userKey, inbox: VaultCrypto.InboxKeyPair(publicKey: inboxPublicKey, secretKey: inboxSecretKey))
    }
}

public struct VaultSessionStore: Sendable {

    public let secrets: any VaultSecretStoring

    public init(secrets: any VaultSecretStoring) { self.secrets = secrets }

    public func load() -> VaultStoredSession? {
        guard let text = (try? secrets.read()) ?? nil, let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(VaultStoredSession.self, from: data)
    }

    public func save(_ session: VaultStoredSession) throws {
        let data = try JSONEncoder().encode(session)
        try secrets.write(String(decoding: data, as: UTF8.self))
    }

    public func clear() throws { try secrets.delete() }
}

/// Tells a fresh install from a relaunch. The Keychain outlives the app, so without this a reinstall (or a
/// phone restored from a backup) would silently resurrect a signed-in vault session nobody asked for.
public protocol VaultInstallMarking: Sendable {
    var hasLaunchedBefore: Bool { get }
    func markLaunched()
}
