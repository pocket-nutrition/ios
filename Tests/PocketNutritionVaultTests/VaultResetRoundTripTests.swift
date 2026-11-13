// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

import PocketNutritionCore
@testable import PocketNutritionVault

// The forgotten-passphrase reset against a REAL vault server, end to end. Opt-in: it runs only when
// `VAULT_ROUNDTRIP_URL` names a loopback server, for example
//
//     cd ../pocket-nutrition-vault && VAULT_DATABASE_URL=sqlite:///:memory: VAULT_PRELOGIN_SECRET=x \
//         .venv/bin/python -m uvicorn app.main:build --factory --port 8765
//     VAULT_ROUNDTRIP_URL=http://127.0.0.1:8765 swift test --filter VaultResetRoundTrip
//
// Anything but 127.0.0.1 or localhost is refused, so this can never touch a real account.

private let roundTripURL: URL? = {
    guard let raw = ProcessInfo.processInfo.environment["VAULT_ROUNDTRIP_URL"],
          let url = URL(string: raw), ["127.0.0.1", "localhost"].contains(url.host() ?? "")
    else { return nil }
    return url
}()

private final class MemorySecrets: VaultSecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    func read() throws -> String? { lock.withLock { value } }
    func write(_ secret: String) throws { lock.withLock { value = secret } }
    func delete() throws { lock.withLock { value = nil } }
}

@Suite("vault reset round trip", .enabled(if: roundTripURL != nil))
@MainActor
struct VaultResetRoundTripTests {

    @Test("register, link a second device, reset from the first: new passphrase in, old out, second unlinked")
    func roundTrip() async throws {
        let url = try #require(roundTripURL)
        let client = VaultClient(baseURL: url)
        let crypto = VaultCrypto()
        let username = "reset-\(UUID().uuidString.prefix(8).lowercased())"
        let oldPassphrase = "correct horse battery staple"

        // Device 1 registers.
        let account = try crypto.createAccount(passphrase: oldPassphrase)
        let first = try await client.register(
            VaultRegisterRequest(
                username: username, kdf: account.kdf, authHash: account.authHash,
                keyring: account.keyringBlob, deviceLabel: "first"))

        // Device 2 logs in with the passphrase.
        let second = try await client.login(
            VaultLoginRequest(username: username, authHash: account.authHash, deviceLabel: "second"))
        _ = try await client.sync(apiKey: second.apiKey, since: 0)

        // Device 1 changes the passphrase without the old one (forgotten).
        let store = VaultSessionStore(secrets: MemorySecrets())
        try store.save(
            VaultStoredSession(
                serverURL: url, username: username, accountId: first.accountId, apiKey: first.apiKey,
                keyId: first.keyId, kdf: account.kdf, userKey: account.keys.userKey,
                inboxPublicKey: account.keys.inbox.publicKey, inboxSecretKey: account.keys.inbox.secretKey))
        let model = VaultSecurityModel(makeServer: { VaultClient(baseURL: $0) }, sessions: store)
        let reset = try #require(await model.changePassphrase(.generated))
        #expect(model.error == nil)
        #expect(reset.revokedDevices == 1)

        // Old passphrase: refused.
        let oldKdf = try await client.prelogin(username: username)
        let oldAttempt = try crypto.credentials(passphrase: oldPassphrase, kdf: oldKdf)
        await #expect(throws: VaultError.outcome(.invalidCredentials)) {
            _ = try await client.login(
                VaultLoginRequest(
                    username: username, authHash: oldAttempt.authHash.base64EncodedString(), deviceLabel: "old"))
        }

        // New passphrase: accepted, and it opens the same user key. The recovery key too; the old one no more.
        let newKdf = try await client.prelogin(username: username)
        #expect(newKdf == store.load()?.kdf)
        let credentials = try crypto.credentials(passphrase: reset.passphrase, kdf: newKdf)
        let third = try await client.login(
            VaultLoginRequest(
                username: username, authHash: credentials.authHash.base64EncodedString(), deviceLabel: "third"))
        let blob = try #require(third.keyring.blob.flatMap(VaultKeyringBlob.decode))
        #expect(try crypto.unlock(keyring: blob, credentials: credentials) == account.keys)
        #expect(try crypto.unlock(keyring: blob, recoveryKey: reset.recoveryKey) == account.keys)
        #expect(throws: VaultCryptoError.decryptionFailed) {
            try crypto.unlock(keyring: blob, recoveryKey: account.recoveryKey)
        }

        // Device 2 was unlinked; device 1 still works with its key.
        await #expect(throws: VaultError.outcome(.unauthorized)) {
            _ = try await client.sync(apiKey: second.apiKey, since: 0)
        }
        _ = try await client.sync(apiKey: first.apiKey, since: 0)

        // Clean up the throwaway account.
        try await client.deleteAccount(apiKey: first.apiKey, authHash: credentials.authHash.base64EncodedString())
    }
}
