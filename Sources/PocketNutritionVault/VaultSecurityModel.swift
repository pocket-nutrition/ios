// SPDX-License-Identifier: MPL-2.0

import Foundation
import Observation
import PocketNutritionCore

/// Drives the "account security" part of the vault screen for the account this phone is linked to:
/// the linked devices, the fingerprint phrase, changing the passphrase, and two-factor login.
///
/// Like `VaultAccountModel`, it never sends the passphrase (only the login hash derived from it with the
/// KDF stored at link time) and keeps keys only in the Keychain item `VaultSessionStore` writes.
@MainActor
@Observable
public final class VaultSecurityModel {

    /// Where the two-factor setup stands on this screen.
    public enum TwoFactorStep: Equatable, Sendable {
        case idle
        /// A secret is waiting for its first code from the authenticator.
        case confirming(VaultTwoFactorSetup)
        /// Two-factor is now on: the recovery codes, shown once.
        case showingRecoveryCodes([String])
    }

    public private(set) var devices: [VaultDevice] = []
    public private(set) var twoFactor: VaultTwoFactorStatus?
    public private(set) var twoFactorStep: TwoFactorStep = .idle
    public private(set) var isWorking = false
    public private(set) var error: VaultAccountError?
    /// Set by a passphrase change: how many other devices the server unlinked.
    public private(set) var revokedByPassphraseChange: Int?

    @ObservationIgnored private let makeServer: @Sendable (URL) -> any VaultSecurityServing
    @ObservationIgnored private let crypto: VaultCrypto
    @ObservationIgnored private let sessions: VaultSessionStore

    public init(
        makeServer: @escaping @Sendable (URL) -> any VaultSecurityServing,
        crypto: VaultCrypto = VaultCrypto(),
        sessions: VaultSessionStore
    ) {
        self.makeServer = makeServer
        self.crypto = crypto
        self.sessions = sessions
    }

    public func clearError() { error = nil }

    /// This phone's key id, so the list can mark it and not offer to revoke it (that is "log out").
    public var currentDeviceId: String? { sessions.load()?.keyId }

    /// The five words naming this account's keys, nil when the phone is not linked.
    public var fingerprintPhrase: String? {
        guard let session = sessions.load(),
              let words = crypto.fingerprintPhrase(accountId: session.accountId, inboxPublicKey: session.inboxPublicKey)
        else { return nil }
        return words.joined(separator: "-")
    }

    // MARK: - Devices

    public func loadDevices() async {
        await withSession { session, server in
            let all = try await server.listDevices(apiKey: session.apiKey)
            devices = all.filter(\.isActive)
        }
    }

    public func revokeDevice(id: String) async {
        await withSession { session, server in
            guard id != session.keyId else { return }
            try await server.revokeDevice(apiKey: session.apiKey, id: id)
            devices.removeAll { $0.id == id }
        }
    }

    // MARK: - Passphrase

    /// Changes the passphrase from this linked phone, which holds the user key, so the current passphrase is
    /// never asked (it may be forgotten). Always through the reset endpoint: a new recovery key is made too,
    /// the same user key is wrapped under both, and this phone stays linked with the new KDF. Every other
    /// device is unlinked by the server and the old recovery key stops working. The caller gates this
    /// behind the device owner's authentication.
    ///
    /// `twoFactorCode` is what the person typed when the account has two-factor on. Returns the new
    /// emergency kit secrets on success, to be shown once; nil on failure (see `error`).
    public func changePassphrase(
        _ choice: VaultNewPassphrase, twoFactorCode raw: String? = nil
    ) async -> VaultPassphraseReset? {
        var result: VaultPassphraseReset?
        await withSession { session, server in
            var twoFactor: VaultTwoFactorCode?
            if let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty {
                guard let parsed = VaultTwoFactorCode(raw) else { throw VaultAccountError.invalidTwoFactor }
                twoFactor = parsed
            }
            let passphrase: String
            switch choice {
            case .generated:
                passphrase = VaultPassphraseSuggestion.make()
            case .own(let typed, let confirmation):
                // The same rules as at registration.
                guard isAcceptableVaultPassphrase(typed) else { throw VaultAccountError.passphraseTooShort }
                guard typed == confirmation else { throw VaultAccountError.passphraseMismatch }
                passphrase = typed
            }

            // One retry on a keyring conflict: another device wrote the keyring between read and write.
            var attempt = 0
            while true {
                attempt += 1
                let keyring = try await server.keyring(apiKey: session.apiKey)
                guard let blob = keyring.blob.flatMap(VaultKeyringBlob.decode) else {
                    throw VaultAccountError.keyringUnreadable
                }
                // The inbox in the server's keyring must be this phone's: a swapped keyring would make
                // the reset wrap keys nobody else holds.
                guard Data(base64Encoded: blob.inboxPublicKey) == session.inboxPublicKey else {
                    throw VaultAccountError.keyringUnreadable
                }
                let crypto = self.crypto
                let userKey = session.userKey
                let reset = try await offMain {
                    try crypto.resetKeyring(keyring: blob, userKey: userKey, newPassphrase: passphrase)
                }
                do {
                    let reply = try await server.resetPassphrase(
                        apiKey: session.apiKey,
                        VaultPassphraseResetRequest(
                            newAuthHash: reset.authHash, kdf: reset.kdf, keyring: reset.keyringBlob,
                            baseVersion: keyring.version, twoFactor: twoFactor))
                    do {
                        try sessions.save(session.withKdf(reset.kdf))
                    } catch {
                        // The server already holds the new keyring: the kit must still be shown, or the new
                        // passphrase would be lost too. This phone keeps syncing with its device key.
                        self.error = .keychain
                    }
                    revokedByPassphraseChange = reply.revokedDevices
                    devices.removeAll { $0.id != session.keyId }
                    result = VaultPassphraseReset(
                        username: session.username, serverURL: session.serverURL, passphrase: passphrase,
                        isGenerated: choice == .generated, recoveryKey: reset.recoveryKey,
                        revokedDevices: reply.revokedDevices)
                    return
                } catch VaultError.outcome(.keyringConflict) where attempt < 2 {
                    continue
                }
            }
        }
        return result
    }

    // MARK: - Two-factor

    public func loadTwoFactor() async {
        await withSession { session, server in
            twoFactor = try await server.twoFactorStatus(apiKey: session.apiKey)
        }
    }

    public func startTwoFactorSetup(passphrase: String) async {
        await withSession { session, server in
            let authHash = try await authHash(passphrase, session: session)
            twoFactorStep = .confirming(try await server.setUpTwoFactor(apiKey: session.apiKey, authHash: authHash))
        }
    }

    public func confirmTwoFactor(code raw: String) async {
        await withSession { session, server in
            guard case .totp(let code) = VaultTwoFactorCode(raw) else { throw VaultAccountError.invalidTwoFactor }
            let codes = try await server.enableTwoFactor(apiKey: session.apiKey, code: code)
            twoFactorStep = .showingRecoveryCodes(codes.recoveryCodes)
            twoFactor = VaultTwoFactorStatus(enabled: true, recoveryCodesLeft: codes.recoveryCodes.count)
        }
    }

    /// `code` is a current authenticator code or an unused recovery code.
    public func disableTwoFactor(passphrase: String, code raw: String) async {
        await withSession { session, server in
            let code: String
            switch VaultTwoFactorCode(raw) {
            case .totp(let value), .recovery(let value): code = value
            case nil: throw VaultAccountError.invalidTwoFactor
            }
            let authHash = try await authHash(passphrase, session: session)
            try await server.disableTwoFactor(apiKey: session.apiKey, authHash: authHash, code: code)
            twoFactor = VaultTwoFactorStatus(enabled: false, recoveryCodesLeft: 0)
        }
    }

    /// Leaves the setup or the recovery codes; a secret never confirmed simply stays pending on the server.
    public func finishTwoFactorStep() { twoFactorStep = .idle }

    // MARK: - Plumbing

    private func authHash(_ passphrase: String, session: VaultStoredSession) async throws -> String {
        guard !passphrase.isEmpty else { throw VaultAccountError.invalidCredentials }
        let crypto = self.crypto
        let kdf = session.kdf
        return try await offMain { try crypto.credentials(passphrase: passphrase, kdf: kdf) }
            .authHash.base64EncodedString()
    }

    /// One operation at a time, against the session as the Keychain holds it now.
    private func withSession(
        _ body: (VaultStoredSession, any VaultSecurityServing) async throws -> Void
    ) async {
        guard !isWorking else { return }
        guard let session = sessions.load() else { return error = .deviceRevoked }
        error = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await body(session, makeServer(session.serverURL))
        } catch VaultError.outcome(.unauthorized) {
            error = .deviceRevoked
        } catch {
            self.error = mapVaultAccountError(error)
        }
    }
}

/// The new passphrase: generated by the app (recommended), or the person's own, typed twice.
public enum VaultNewPassphrase: Equatable, Sendable {
    case generated
    case own(String, confirmation: String)
}

/// What a passphrase change hands back to be shown once in the emergency kit. Never persisted or logged.
public struct VaultPassphraseReset: Equatable, Sendable {
    public let username: String
    public let serverURL: URL
    public let passphrase: String
    /// Generated passphrases go in the kit; a person's own is not repeated back to them.
    public let isGenerated: Bool
    public let recoveryKey: String
    /// Other devices the server unlinked.
    public let revokedDevices: Int
}

extension VaultStoredSession {
    /// The same session after a passphrase change: everything but the KDF stays.
    func withKdf(_ kdf: VaultKdf) -> VaultStoredSession {
        VaultStoredSession(
            serverURL: serverURL, username: username, accountId: accountId, apiKey: apiKey, keyId: keyId,
            kdf: kdf, userKey: userKey, inboxPublicKey: inboxPublicKey, inboxSecretKey: inboxSecretKey)
    }
}
