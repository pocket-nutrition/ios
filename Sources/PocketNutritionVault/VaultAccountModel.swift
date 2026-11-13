// SPDX-License-Identifier: MPL-2.0

import Foundation
import Observation
import PocketNutritionCore

/// What the person sees about the account this phone is linked to. Never contains a key.
public struct VaultAccountSummary: Equatable, Sendable {
    public let username: String
    public let serverURL: URL

    public init(username: String, serverURL: URL) {
        self.username = username
        self.serverURL = serverURL
    }
}

/// Every way an onboarding step can fail, as a meaning the screen can word, never a status code.
public enum VaultAccountError: Error, Equatable, Sendable {
    case invalidServerURL
    /// The address answers, but not like a Pocket Nutrition vault.
    case notAVault
    case offline
    case invalidUsername
    case passphraseTooShort
    case passphraseMismatch
    case usernameTaken
    case registrationClosed
    /// Wrong username or passphrase (the server does not say which).
    case invalidCredentials
    /// Seconds to wait, when the server said.
    case tooManyAttempts(Int?)
    /// The server asked for key-derivation settings below the floor, or ones that contradict its keyring.
    case unsafeKdf
    case keyringUnreadable
    /// A wrong or already-used two-factor code, or text that is not a code at all.
    case invalidTwoFactor
    /// The account has two-factor on and no code was given: ask for one and try again.
    case twoFactorRequired
    /// Another device changed the account's keys meanwhile: reopen the screen and try again.
    case keyringConflict
    /// The account was made with an API key only, so there is no passphrase to change.
    case noPassphrase
    /// Two-factor was turned on or off from another device meanwhile.
    case twoFactorStateChanged
    /// This device was unlinked from elsewhere (revoked, or the account erased).
    case deviceRevoked
    case serverError
    case keychain
    case crypto
}

/// Drives the vault onboarding screen: pick a server, create an account or log in (which links this
/// phone), unlink, erase.
///
/// What it never does: send the passphrase anywhere (only the login hash derived from it leaves the
/// phone), keep a key outside the Keychain item `VaultSessionStore` writes, or trust the server's word on
/// key-derivation settings (`isAcceptableVaultKdf`). The slow Argon2id work runs off the main actor.
@MainActor
@Observable
public final class VaultAccountModel {

    public enum Phase: Equatable, Sendable {
        case signedOut
        case signedIn(VaultAccountSummary)
    }

    public private(set) var phase: Phase = .signedOut
    /// What the checked server said about itself; nil until `checkServer` succeeds.
    public private(set) var serverInfo: VaultServerInfo?
    /// The recovery key of an account that is prepared but not yet registered. The screen shows it once and
    /// registration waits for the person to confirm they saved it.
    public private(set) var pendingRecoveryKey: String?
    public private(set) var isWorking = false
    public private(set) var error: VaultAccountError?
    /// The passphrase was right and the account has two-factor on: the screen asks for a code and calls
    /// `login` again with it.
    public private(set) var needsTwoFactor = false

    private struct PendingAccount {
        let username: String
        let account: VaultNewAccount
        let serverURL: URL
    }

    @ObservationIgnored private let deviceLabel: String
    @ObservationIgnored private let makeServer: @Sendable (URL) -> any VaultServing
    @ObservationIgnored private let crypto: VaultCrypto
    @ObservationIgnored private let sessions: VaultSessionStore
    @ObservationIgnored private let rememberServerURL: (String) -> Void

    @ObservationIgnored private var checkedServer: URL?
    @ObservationIgnored private var session: VaultStoredSession?
    @ObservationIgnored private var pending: PendingAccount?

    public init(
        deviceLabel: String,
        makeServer: @escaping @Sendable (URL) -> any VaultServing,
        crypto: VaultCrypto = VaultCrypto(),
        sessions: VaultSessionStore,
        install: any VaultInstallMarking,
        rememberServerURL: @escaping (String) -> Void
    ) {
        self.deviceLabel = deviceLabel
        self.makeServer = makeServer
        self.crypto = crypto
        self.sessions = sessions
        self.rememberServerURL = rememberServerURL

        // The Keychain outlives the app: on a fresh install, whatever it still holds was not linked by
        // this installation and must not come back as a signed-in session.
        if !install.hasLaunchedBefore {
            try? sessions.clear()
            install.markLaunched()
        }
        if let stored = sessions.load() {
            session = stored
            phase = .signedIn(VaultAccountSummary(username: stored.username, serverURL: stored.serverURL))
        }
    }

    public func clearError() { error = nil }

    /// Re-reads the Keychain item, for when another part of the app signed this phone out (a session
    /// timeout) or changed the session (a new passphrase) while this model was alive.
    public func reload() {
        session = sessions.load()
        if let session {
            phase = .signedIn(VaultAccountSummary(username: session.username, serverURL: session.serverURL))
        } else {
            phase = .signedOut
        }
    }

    /// Back to the plain login form, dropping a pending two-factor step.
    public func cancelTwoFactor() {
        needsTwoFactor = false
        error = nil
    }

    // MARK: - Server

    public func checkServer(_ rawURL: String) async {
        await run {
            guard let url = validatedVaultServerURL(rawURL) else { return fail(.invalidServerURL) }
            serverInfo = nil
            checkedServer = nil
            do {
                let info = try await makeServer(url).serverInfo()
                serverInfo = info
                checkedServer = url
                rememberServerURL(url.absoluteString)
            } catch {
                fail(map(error))
            }
        }
    }

    // MARK: - Log in

    /// `twoFactorCode` is what the person typed in the code field, once `needsTwoFactor` asked for it.
    public func login(username rawUsername: String, passphrase: String, twoFactorCode: String? = nil) async {
        await run {
            var twoFactor: VaultTwoFactorCode?
            if let twoFactorCode {
                guard let parsed = VaultTwoFactorCode(twoFactorCode) else { return fail(.invalidTwoFactor) }
                twoFactor = parsed
            }
            guard let username = normalizedVaultUsername(rawUsername) else { return fail(.invalidUsername) }
            guard !passphrase.isEmpty else { return fail(.invalidCredentials) }
            guard let url = checkedServer else { return fail(.invalidServerURL) }
            let server = makeServer(url)
            var issuedKey: String?
            do {
                let kdf = try await server.prelogin(username: username)
                guard isAcceptableVaultKdf(kdf) else { return fail(.unsafeKdf) }
                let crypto = self.crypto
                let credentials = try await offMain { try crypto.credentials(passphrase: passphrase, kdf: kdf) }

                let reply = try await server.login(
                    VaultLoginRequest(
                        username: username, authHash: credentials.authHash.base64EncodedString(),
                        deviceLabel: deviceLabel, twoFactor: twoFactor))
                issuedKey = reply.apiKey
                needsTwoFactor = false

                guard let blob = reply.keyring.blob.flatMap(VaultKeyringBlob.decode) else {
                    throw VaultAccountError.keyringUnreadable
                }
                // The wrap key came from the KDF the server announced at prelogin. A keyring that
                // claims another one is the server contradicting itself.
                guard blob.kdf == kdf else { throw VaultAccountError.unsafeKdf }
                let keys = try await offMain { try crypto.unlock(keyring: blob, credentials: credentials) }
                try link(
                    VaultStoredSession(
                        serverURL: url, username: username, accountId: reply.accountId, apiKey: reply.apiKey,
                        keyId: reply.keyId, kdf: kdf, userKey: keys.userKey,
                        inboxPublicKey: keys.inbox.publicKey, inboxSecretKey: keys.inbox.secretKey))
            } catch VaultError.outcome(.twoFactorRequired) {
                needsTwoFactor = true  // no key was issued: nothing to revoke
            } catch {
                // The server already issued this device a key: do not leave it active on a failed link.
                if let issuedKey { try? await server.logout(apiKey: issuedKey) }
                fail(map(error))
            }
        }
    }

    // MARK: - Create an account (two steps: keys first, registration after the recovery key is saved)

    /// Validates the form and builds the account's keys locally. Nothing is sent: the recovery key is shown
    /// first, because the server can never give it back.
    public func prepareAccount(username rawUsername: String, passphrase: String, confirmation: String) async {
        await run {
            guard let info = serverInfo, let url = checkedServer else { return fail(.invalidServerURL) }
            guard info.isRegistrationOpen else { return fail(.registrationClosed) }
            guard let username = normalizedVaultUsername(rawUsername) else { return fail(.invalidUsername) }
            guard isAcceptableVaultPassphrase(passphrase) else { return fail(.passphraseTooShort) }
            guard passphrase == confirmation else { return fail(.passphraseMismatch) }
            let crypto = self.crypto
            do {
                let account = try await offMain { try crypto.createAccount(passphrase: passphrase) }
                pending = PendingAccount(username: username, account: account, serverURL: url)
                pendingRecoveryKey = account.recoveryKey
            } catch {
                fail(map(error))
            }
        }
    }

    public func registerPreparedAccount() async {
        await run {
            guard let pending else { return }
            let server = makeServer(pending.serverURL)
            var issuedKey: String?
            do {
                let reply = try await server.register(
                    VaultRegisterRequest(
                        username: pending.username, kdf: pending.account.kdf, authHash: pending.account.authHash,
                        keyring: pending.account.keyringBlob, deviceLabel: deviceLabel))
                issuedKey = reply.apiKey
                let keys = pending.account.keys
                try link(
                    VaultStoredSession(
                        serverURL: pending.serverURL, username: pending.username, accountId: reply.accountId,
                        apiKey: reply.apiKey, keyId: reply.keyId, kdf: pending.account.kdf, userKey: keys.userKey,
                        inboxPublicKey: keys.inbox.publicKey, inboxSecretKey: keys.inbox.secretKey))
                discardPendingAccount()
            } catch {
                if let issuedKey { try? await server.logout(apiKey: issuedKey) }
                let failure = map(error)
                // Taken or closed: the form must change, so go back to it. A network failure keeps the
                // prepared account, so "continue" can simply be tried again.
                if failure == .usernameTaken || failure == .registrationClosed { discardPendingAccount() }
                fail(failure)
            }
        }
    }

    public func discardPendingAccount() {
        pending = nil
        pendingRecoveryKey = nil
    }

    // MARK: - Unlink and erase

    /// Signs this phone out. Returns false when the server could not be told, in which case this device's key
    /// stays valid there until it is revoked from another device; the phone is signed out either way.
    @discardableResult
    public func logout() async -> Bool {
        var reached = false
        await run {
            guard let session else { return }
            do {
                try await makeServer(session.serverURL).logout(apiKey: session.apiKey)
                reached = true
            } catch VaultError.outcome(.unauthorized) {
                reached = true  // the key was already revoked
            } catch {
                reached = false
            }
            signOutLocally()
        }
        return reached
    }

    /// Erases the account on the server. The passphrase is re-derived with the KDF this phone was linked
    /// with, never with whatever the server says now.
    public func deleteAccount(passphrase: String) async {
        await run {
            guard let session else { return }
            guard !passphrase.isEmpty else { return fail(.invalidCredentials) }
            let crypto = self.crypto
            do {
                let credentials = try await offMain { try crypto.credentials(passphrase: passphrase, kdf: session.kdf) }
                try await makeServer(session.serverURL).deleteAccount(
                    apiKey: session.apiKey, authHash: credentials.authHash.base64EncodedString())
                signOutLocally()
            } catch {
                fail(map(error))
            }
        }
    }

    // MARK: - Plumbing

    /// One operation at a time; `isWorking` covers the screen while it runs.
    private func run(_ body: () async -> Void) async {
        guard !isWorking else { return }
        error = nil
        isWorking = true
        defer { isWorking = false }
        await body()
    }

    private func fail(_ failure: VaultAccountError) { error = failure }

    /// Saves the linked session and flips to signed in. Throws `.keychain` if it could not be stored.
    private func link(_ stored: VaultStoredSession) throws {
        do { try sessions.save(stored) } catch { throw VaultAccountError.keychain }
        session = stored
        phase = .signedIn(VaultAccountSummary(username: stored.username, serverURL: stored.serverURL))
    }

    private func signOutLocally() {
        do {
            try sessions.clear()
        } catch {
            // Keys still on the phone: stay signed in rather than pretend they are gone.
            fail(.keychain)
            return
        }
        session = nil
        phase = .signedOut
    }

    private func map(_ error: Error) -> VaultAccountError { mapVaultAccountError(error) }
}

/// One mapping for every vault account screen, so a failure reads the same wherever it happens.
func mapVaultAccountError(_ error: Error) -> VaultAccountError {
    switch error {
    case let failure as VaultAccountError: return failure
    case VaultError.offline: return .offline
    case VaultError.malformedResponse: return .notAVault
    case VaultError.outcome(let outcome):
        switch outcome {
        case .invalidCredentials, .unauthorized: return .invalidCredentials
        case .usernameTaken: return .usernameTaken
        case .registrationClosed: return .registrationClosed
        case .tooManyAttempts(let seconds): return .tooManyAttempts(seconds)
        case .twoFactorRequired: return .twoFactorRequired
        case .invalidTwoFactor, .invalidCode: return .invalidTwoFactor
        case .keyringConflict: return .keyringConflict
        case .noPassphrase: return .noPassphrase
        case .twoFactorStateChanged: return .twoFactorStateChanged
        case .success, .quotaExceeded, .revisionConflict, .serverError, .other: return .serverError
        }
    case VaultCryptoError.unacceptableKdf: return .unsafeKdf
    case VaultCryptoError.decryptionFailed, VaultCryptoError.inboxKeyMismatch, VaultCryptoError.malformedInput:
        return .keyringUnreadable
    case is VaultCryptoError: return .crypto
    default: return .serverError
    }
}

/// Runs slow, memory-hungry key derivation away from the main actor.
func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    let result = await Task.detached(priority: .userInitiated) { Result { try work() } }.value
    return try result.get()
}
