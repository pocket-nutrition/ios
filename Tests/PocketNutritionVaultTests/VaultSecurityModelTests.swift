// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

import PocketNutritionCore
@testable import PocketNutritionVault

// MARK: - Fakes

private final class SecuritySecrets: VaultSecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    func read() throws -> String? { lock.withLock { value } }
    func write(_ secret: String) throws { lock.withLock { value = secret } }
    func delete() throws { lock.withLock { value = nil } }
}

/// Holds one account's login hash and keyring, and checks what the model sends against them.
private final class FakeSecurityVault: VaultSecurityServing, @unchecked Sendable {
    private let lock = NSLock()
    var authHash: String
    var keyringBlob: String
    var keyringVersion = 1
    var devices: [VaultDevice]
    var twoFactorEnabled = false
    var revokedCurrent = false
    private(set) var resetCalls = 0
    /// Bumps the keyring version this many times right before a reset, as another device writing first.
    var conflictsBeforeReset = 0
    private(set) var lastReset: VaultPassphraseResetRequest?
    private(set) var revoked: [String] = []

    init(authHash: String, keyringBlob: String, devices: [VaultDevice]) {
        self.authHash = authHash
        self.keyringBlob = keyringBlob
        self.devices = devices
    }

    private func check(_ apiKey: String) throws {
        if revokedCurrent { throw VaultError.outcome(.unauthorized) }
    }

    func listDevices(apiKey: String) async throws -> [VaultDevice] {
        try check(apiKey)
        return lock.withLock { devices }
    }

    func revokeDevice(apiKey: String, id: String) async throws {
        try check(apiKey)
        lock.withLock { revoked.append(id) }
    }

    func keyring(apiKey: String) async throws -> VaultKeyring {
        try check(apiKey)
        return lock.withLock { VaultKeyring(blob: keyringBlob, version: keyringVersion) }
    }

    func resetPassphrase(
        apiKey: String, _ request: VaultPassphraseResetRequest
    ) async throws -> VaultPassphraseChanged {
        try check(apiKey)
        return try lock.withLock {
            resetCalls += 1
            lastReset = request
            if twoFactorEnabled {
                guard request.totpCode != nil || request.recoveryCode != nil else {
                    throw VaultError.outcome(.twoFactorRequired)
                }
                guard request.totpCode == "123456" else { throw VaultError.outcome(.invalidTwoFactor) }
            }
            if conflictsBeforeReset > 0 {
                conflictsBeforeReset -= 1
                keyringVersion += 1
            }
            guard request.baseVersion == keyringVersion else { throw VaultError.outcome(.keyringConflict) }
            authHash = request.newAuthHash
            keyringBlob = request.keyring
            keyringVersion += 1
            return try JSONDecoder().decode(
                VaultPassphraseChanged.self,
                from: Data(#"{"version":\#(keyringVersion),"revoked_devices":1}"#.utf8))
        }
    }

    func twoFactorStatus(apiKey: String) async throws -> VaultTwoFactorStatus {
        VaultTwoFactorStatus(enabled: twoFactorEnabled, recoveryCodesLeft: twoFactorEnabled ? 10 : 0)
    }

    func setUpTwoFactor(apiKey: String, authHash: String) async throws -> VaultTwoFactorSetup {
        guard authHash == self.authHash else { throw VaultError.outcome(.invalidCredentials) }
        return VaultTwoFactorSetup(secret: "JBSWY3DPEHPK3PXP", otpauthURI: "otpauth://totp/x?secret=JBSWY3DPEHPK3PXP")
    }

    func enableTwoFactor(apiKey: String, code: String) async throws -> VaultRecoveryCodes {
        guard code == "123456" else { throw VaultError.outcome(.invalidCode) }
        twoFactorEnabled = true
        return try JSONDecoder().decode(
            VaultRecoveryCodes.self, from: Data(#"{"recovery_codes":["aaaa-bbbb-cccc","dddd-eeee-ffff"]}"#.utf8))
    }

    func disableTwoFactor(apiKey: String, authHash: String, code: String) async throws {
        guard authHash == self.authHash else { throw VaultError.outcome(.invalidCredentials) }
        guard code == "123456" else { throw VaultError.outcome(.invalidCode) }
        twoFactorEnabled = false
    }
}

private let oldPassphrase = "correct horse battery staple"

// MARK: - Tests

@Suite("vault security model")
@MainActor
struct VaultSecurityModelTests {

    private let crypto = VaultCrypto()

    /// A linked phone and a server that agree on one freshly created account.
    private func linked() throws -> (VaultSecurityModel, FakeSecurityVault, VaultSessionStore, VaultNewAccount) {
        let account = try crypto.createAccount(passphrase: oldPassphrase)
        let server = FakeSecurityVault(
            authHash: account.authHash, keyringBlob: account.keyringBlob,
            devices: [
                VaultDevice(id: "kid-1", label: "iPhone", createdAt: "2026-11-01T10:00:00.123456Z"),
                VaultDevice(id: "kid-2", label: "iPad", createdAt: "2026-11-01T11:00:00+00:00"),
                VaultDevice(
                    id: "kid-3", label: "Old", createdAt: "2026-10-01T10:00:00Z", revokedAt: "2026-10-02T10:00:00Z"),
            ])
        let store = VaultSessionStore(secrets: SecuritySecrets())
        try store.save(
            VaultStoredSession(
                serverURL: URL(string: "https://vault.example")!, username: "alice", accountId: "acc-1",
                apiKey: "key-1", keyId: "kid-1", kdf: account.kdf, userKey: account.keys.userKey,
                inboxPublicKey: account.keys.inbox.publicKey, inboxSecretKey: account.keys.inbox.secretKey))
        let model = VaultSecurityModel(makeServer: { _ in server }, sessions: store)
        return (model, server, store, account)
    }

    @Test("lists only active devices and never revokes this one")
    func devices() async throws {
        let (model, server, _, _) = try linked()
        await model.loadDevices()
        #expect(model.devices.map(\.id) == ["kid-1", "kid-2"])
        #expect(model.currentDeviceId == "kid-1")

        await model.revokeDevice(id: "kid-1")
        #expect(server.revoked.isEmpty)
        await model.revokeDevice(id: "kid-2")
        #expect(server.revoked == ["kid-2"])
        #expect(model.devices.map(\.id) == ["kid-1"])
    }

    @Test("a revoked device is reported as such, not as a wrong passphrase")
    func revokedDevice() async throws {
        let (model, server, _, _) = try linked()
        server.revokedCurrent = true
        await model.loadDevices()
        #expect(model.error == .deviceRevoked)
    }

    @Test("two-factor: setup, confirm with a code, recovery codes shown once, then off again")
    func twoFactor() async throws {
        let (model, server, _, _) = try linked()
        await model.startTwoFactorSetup(passphrase: oldPassphrase)
        guard case .confirming(let setup) = model.twoFactorStep else { Issue.record("no setup"); return }
        #expect(setup.groupedSecret == "JBSW Y3DP EHPK 3PXP")

        await model.confirmTwoFactor(code: "000000")
        #expect(model.error == .invalidTwoFactor)
        await model.confirmTwoFactor(code: "123 456")
        #expect(model.twoFactorStep == .showingRecoveryCodes(["aaaa-bbbb-cccc", "dddd-eeee-ffff"]))
        #expect(model.twoFactor?.enabled == true)
        model.finishTwoFactorStep()

        await model.disableTwoFactor(passphrase: oldPassphrase, code: "123456")
        #expect(model.error == nil)
        #expect(server.twoFactorEnabled == false)
    }

    @Test("the fingerprint phrase is five words, stable for the same keys")
    func fingerprint() throws {
        let (model, _, _, _) = try linked()
        let phrase = try #require(model.fingerprintPhrase)
        #expect(phrase.split(separator: "-").count == 5)
        #expect(model.fingerprintPhrase == phrase)
        let other = crypto.fingerprintPhrase(accountId: "acc-2", inboxPublicKey: Data(repeating: 1, count: 32))
        #expect(other?.joined(separator: "-") != phrase)
    }

    // MARK: - Change the passphrase (through the reset endpoint, no old passphrase)

    private let resetPassphrase = "maple-orbit-fjord-lantern-cobalt"

    @Test("a reset wraps the same user key under a new passphrase and a new recovery key")
    func resetPassphraseFlow() async throws {
        let (model, server, store, account) = try linked()
        let before = try #require(VaultKeyringBlob.decode(server.keyringBlob))
        let phrase = resetPassphrase
        let reset = try #require(await model.changePassphrase(.own(phrase, confirmation: phrase)))
        #expect(model.error == nil)
        #expect(reset.passphrase == phrase)
        #expect(!reset.isGenerated)
        #expect(reset.recoveryKey != account.recoveryKey)
        #expect(reset.revokedDevices == 1)
        #expect(server.keyringVersion == 2)
        #expect(server.lastReset?.baseVersion == 1)

        let blob = try #require(VaultKeyringBlob.decode(server.keyringBlob))
        #expect(blob.inboxPublicKey == before.inboxPublicKey)
        #expect(blob.inboxWrappedSecretKey == before.inboxWrappedSecretKey)
        let credentials = try crypto.credentials(passphrase: phrase, kdf: blob.kdf)
        #expect(credentials.authHash.base64EncodedString() == server.authHash)
        #expect(try crypto.unlock(keyring: blob, credentials: credentials) == account.keys)
        #expect(try crypto.unlock(keyring: blob, recoveryKey: reset.recoveryKey) == account.keys)
        #expect(throws: VaultCryptoError.decryptionFailed) {
            try crypto.unlock(keyring: blob, recoveryKey: account.recoveryKey)
        }

        // The phone stays linked, with the new KDF and the same keys.
        let stored = try #require(store.load())
        #expect(stored.kdf == blob.kdf)
        #expect(stored.apiKey == "key-1")
        #expect(stored.keys == account.keys)
    }

    @Test("a reset retries once on a keyring conflict, then gives up")
    func resetConflict() async throws {
        let (model, server, _, _) = try linked()
        server.conflictsBeforeReset = 1
        let phrase = resetPassphrase
        #expect(await model.changePassphrase(.own(phrase, confirmation: phrase)) != nil)
        #expect(server.resetCalls == 2)

        let (other, busy, store, account) = try linked()
        busy.conflictsBeforeReset = 5
        #expect(await other.changePassphrase(.own(phrase, confirmation: phrase)) == nil)
        #expect(other.error == .keyringConflict)
        #expect(busy.resetCalls == 2)
        #expect(store.load()?.kdf == account.kdf)
    }

    @Test("with two-factor on, a reset needs a valid code")
    func resetTwoFactor() async throws {
        let (model, server, store, account) = try linked()
        server.twoFactorEnabled = true
        let phrase = resetPassphrase
        #expect(await model.changePassphrase(.own(phrase, confirmation: phrase)) == nil)
        #expect(model.error == .twoFactorRequired)
        #expect(await model.changePassphrase(.own(phrase, confirmation: phrase), twoFactorCode: "000000") == nil)
        #expect(model.error == .invalidTwoFactor)
        #expect(await model.changePassphrase(.own(phrase, confirmation: phrase), twoFactorCode: "not a code") == nil)
        #expect(model.error == .invalidTwoFactor)
        #expect(store.load()?.kdf == account.kdf)

        #expect(await model.changePassphrase(.own(phrase, confirmation: phrase), twoFactorCode: "123 456") != nil)
        #expect(server.lastReset?.totpCode == "123456")
    }

    @Test("a keyring that is not this phone's is never reset")
    func resetForeignKeyring() async throws {
        let (model, server, store, account) = try linked()
        server.keyringBlob = try crypto.createAccount(passphrase: oldPassphrase).keyringBlob
        let phrase = resetPassphrase
        #expect(await model.changePassphrase(.own(phrase, confirmation: phrase)) == nil)
        #expect(model.error == .keyringUnreadable)
        #expect(server.resetCalls == 0)
        #expect(store.load()?.kdf == account.kdf)
    }

    @Test("a generated passphrase goes in the kit and opens the same user key")
    func changeToGenerated() async throws {
        let (model, server, _, account) = try linked()
        let reset = try #require(await model.changePassphrase(.generated))
        #expect(reset.isGenerated)
        // Not a word count: a few EFF words carry their own hyphen ("t-shirt", "yo-yo").
        #expect(isAcceptableVaultPassphrase(reset.passphrase))
        let blob = try #require(VaultKeyringBlob.decode(server.keyringBlob))
        let credentials = try crypto.credentials(passphrase: reset.passphrase, kdf: blob.kdf)
        #expect(try crypto.unlock(keyring: blob, credentials: credentials) == account.keys)
    }

    @Test("a passphrase of one's own follows the registration rules, checked before anything is sent")
    func changeToOwnRules() async throws {
        let (model, server, store, account) = try linked()
        #expect(await model.changePassphrase(.own("short", confirmation: "short")) == nil)
        #expect(model.error == .passphraseTooShort)
        let phrase = resetPassphrase
        #expect(await model.changePassphrase(.own(phrase, confirmation: phrase + "x")) == nil)
        #expect(model.error == .passphraseMismatch)
        #expect(server.resetCalls == 0)
        #expect(store.load()?.kdf == account.kdf)
    }

    @Test("an account locked by failed attempts is reported as such")
    func resetLocked() async throws {
        #expect(mapVaultAccountError(VaultError.outcome(classifyVaultHTTP(
            status: 429, errorCode: "account_locked", retryAfter: "120"))) == .tooManyAttempts(120))
        #expect(mapVaultAccountError(VaultError.outcome(classifyVaultHTTP(
            status: 401, errorCode: "two_factor_required"))) == .twoFactorRequired)
        #expect(mapVaultAccountError(VaultError.outcome(classifyVaultHTTP(
            status: 401, errorCode: "invalid_two_factor"))) == .invalidTwoFactor)
    }
}
