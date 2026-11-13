// SPDX-License-Identifier: MPL-2.0

import Foundation
import PocketNutritionCore

public enum VaultError: Error, Sendable, Equatable {
    /// No connectivity, a timeout, or any transport failure: safe to retry.
    case offline
    /// The server answered something that is not a vault answer.
    case malformedResponse
    /// A meaningful non-success answer. See `VaultHTTPOutcome`.
    case outcome(VaultHTTPOutcome)
}

/// The calls onboarding needs. A protocol so the account model can be tested against a fake server.
public protocol VaultServing: Sendable {
    func serverInfo() async throws -> VaultServerInfo
    /// The account's KDF settings. Unknown usernames get stable fake ones, so this never fails for them.
    func prelogin(username: String) async throws -> VaultKdf
    func register(_ request: VaultRegisterRequest) async throws -> VaultSession
    func login(_ request: VaultLoginRequest) async throws -> VaultSession
    /// Unlinks this device: the server revokes the key used for the call.
    func logout(apiKey: String) async throws
    /// Erases the account and everything stored for it. Needs the login hash as proof of the passphrase.
    func deleteAccount(apiKey: String, authHash: String) async throws
    /// Mints a short-lived, write-only token for one record (see "Drops" in the protocol).
    func createDrop(apiKey: String, _ request: VaultDropRequest) async throws -> VaultDropToken
    /// Records changed after `since`, in order. A page may be partial: see `hasMore`.
    func sync(apiKey: String, since: Int) async throws -> VaultSyncPage
    /// Writes one record the owner encrypted. `revision` is the current revision + 1.
    func putRecord(apiKey: String, id: String, _ write: VaultRecordWrite) async throws
    /// Deletes one record (a tombstone). `revision` is the current revision + 1.
    func deleteRecord(apiKey: String, id: String, revision: Int) async throws
}

/// The account-security calls: devices, keyring, passphrase change and two-factor. Separate from
/// `VaultServing` so the onboarding and sync fakes do not have to grow with them.
public protocol VaultSecurityServing: Sendable {
    func listDevices(apiKey: String) async throws -> [VaultDevice]
    func revokeDevice(apiKey: String, id: String) async throws
    func keyring(apiKey: String) async throws -> VaultKeyring
    /// Replaces the passphrase from this linked device, without the old one (`POST /v1/account/passphrase/reset`).
    func resetPassphrase(apiKey: String, _ request: VaultPassphraseResetRequest) async throws -> VaultPassphraseChanged
    func twoFactorStatus(apiKey: String) async throws -> VaultTwoFactorStatus
    /// Needs the login hash: a stolen unlocked phone must not be enough to swap the second factor.
    func setUpTwoFactor(apiKey: String, authHash: String) async throws -> VaultTwoFactorSetup
    func enableTwoFactor(apiKey: String, code: String) async throws -> VaultRecoveryCodes
    func disableTwoFactor(apiKey: String, authHash: String, code: String) async throws
}
