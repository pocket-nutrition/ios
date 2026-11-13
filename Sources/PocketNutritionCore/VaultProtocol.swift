// SPDX-License-Identifier: MPL-2.0

import Foundation

// The vault protocol, as far as it can be expressed without cryptography. The rules here mirror
// `pocket-nutrition-vault/docs/PROTOCOL.md`; the cipher work itself lives in `PocketNutritionVault`,
// because it needs libsodium and this target is Foundation-only so it can be tested on Linux.

public enum VaultProtocol {
    /// First field of every record's authenticated data. Bumped if the AAD layout ever changes.
    public static let aadVersion = "pnv1"
    /// `key_id` of records encrypted under the user key.
    public static let userKeyId = "user"
    /// `key_id` of records sealed to the phone's inbox public key by a drop.
    public static let inboxKeyId = "inbox"
    /// Record types the app writes.
    public static let captureRecordType = "capture"

    // The server refuses anything below these, and so does the client: a hostile or hacked server
    // must not be able to talk the phone into deriving its keys with a trivially weak KDF. The floor IS
    // the app's own default, so "the server asked for the minimum" gives an attacker nothing to exploit.
    public static let minKdfOpsLimit = 3
    public static let maxKdfOpsLimit = 10
    public static let minKdfMemLimit = 64 * 1024 * 1024
    public static let maxKdfMemLimit = 1024 * 1024 * 1024
    public static let kdfSaltBytes = 16
    /// What the app asks for on a new account.
    public static let defaultKdfOpsLimit = 3
    public static let defaultKdfMemLimit = 64 * 1024 * 1024

    /// The server never sees the passphrase, so it cannot enforce a length: the app does. Bitwarden's floor.
    public static let minPassphraseLength = 12

    public static let authHashBytes = 32
    public static let keyBytes = 32
}

// MARK: - Authenticated data

/// The bytes bound to a record's ciphertext as AAD, so the server cannot swap a record's contents
/// for another's, replay an old revision, or relabel which key it was written under:
///
///     pnv1|<account_id>|<record_id>|<type>|<scope_id or "">|<revision>|<key_id>
public func vaultRecordAAD(
    accountId: String, recordId: String, type: String, scopeId: String?, revision: Int, keyId: String
) -> Data {
    let fields = [
        VaultProtocol.aadVersion, accountId, recordId, type, scopeId ?? "", String(revision), keyId,
    ]
    return Data(fields.joined(separator: "|").utf8)
}

/// What a keyring entry is wrapped for. It is part of the AAD, so a wrapped key cannot be passed off as
/// a different one (the passphrase copy of the user key can never be opened as the recovery copy).
public enum VaultKeyringPurpose: String, Sendable {
    case passphrase
    case recovery
    case inbox
}

/// `pnv1|keyring|<purpose>`
public func vaultKeyringAAD(_ purpose: VaultKeyringPurpose) -> Data {
    Data("\(VaultProtocol.aadVersion)|keyring|\(purpose.rawValue)".utf8)
}

// MARK: - Input rules

/// The username as the server will see it: trimmed and lowercased, 3 to 64 characters of
/// `a-z 0-9 _ . -`, starting with a letter or digit. Nil when it cannot be a valid username.
public func normalizedVaultUsername(_ raw: String) -> String? {
    let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard (3...64).contains(name.utf8.count) else { return nil }
    let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_.-")
    guard name.allSatisfy({ allowed.contains($0) }), let first = name.first, first.isLetter || first.isNumber
    else { return nil }
    return name
}

/// Whether a new passphrase is long enough. Counted in characters as typed (an accented letter is one),
/// after the same normalisation the KDF applies, so the rule cannot disagree with what is derived.
public func isAcceptableVaultPassphrase(_ raw: String) -> Bool {
    raw.precomposedStringWithCompatibilityMapping.count >= VaultProtocol.minPassphraseLength
}

/// `https` only, with a host and no embedded credentials. The passphrase-derived login hash and every
/// record travel to this address, so plain `http` is refused and no ATS exception is needed.
public func validatedVaultServerURL(_ raw: String) -> URL? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let components = URLComponents(string: trimmed),
          components.scheme?.lowercased() == "https",
          let host = components.host, !host.isEmpty,
          components.user == nil, components.password == nil,
          components.query == nil, components.fragment == nil,
          let url = components.url
    else { return nil }
    return url
}

/// `{base}/v1/<segments…>`, appended to whatever path the server URL already has (a self-hosted vault
/// may live under a prefix such as `https://example.org/vault`).
public func vaultURL(base: URL, segments: [String], query: [URLQueryItem] = []) -> URL? {
    guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
    let prefix = components.path.split(separator: "/").map(String.init)
    components.path = "/" + (prefix + ["v1"] + segments).joined(separator: "/")
    components.queryItems = query.isEmpty ? nil : query
    return components.url
}

/// Whether the key derivation settings a server returned are safe to derive keys with.
public func isAcceptableVaultKdf(_ kdf: VaultKdf) -> Bool {
    guard kdf.alg == "argon2id",
          (VaultProtocol.minKdfOpsLimit...VaultProtocol.maxKdfOpsLimit).contains(kdf.opslimit),
          (VaultProtocol.minKdfMemLimit...VaultProtocol.maxKdfMemLimit).contains(kdf.memlimit),
          let salt = Data(base64Encoded: kdf.salt), salt.count == VaultProtocol.kdfSaltBytes
    else { return false }
    return true
}

// MARK: - HTTP outcomes

/// What a vault response means to the app, so screens branch on a meaning and not on a status code.
public enum VaultHTTPOutcome: Equatable, Sendable {
    case success
    /// 401 on a session call: the device key was revoked or the account erased. Sign out.
    case unauthorized
    /// 401 on login: wrong username or passphrase.
    case invalidCredentials
    /// 409 `username_taken`.
    case usernameTaken
    /// 403 `registration_closed`.
    case registrationClosed
    /// 429: too many attempts, or the account is locked. Seconds to wait, when the server said.
    case tooManyAttempts(retryAfter: Int?)
    /// 413 `quota_exceeded`: the account is full.
    case quotaExceeded
    /// 409 `revision_conflict`: someone else wrote first; pull and merge.
    case revisionConflict
    /// 401 `two_factor_required` on login: the passphrase was right, now a code is needed.
    case twoFactorRequired
    /// 401 `invalid_two_factor` on login: a wrong or already-used code.
    case invalidTwoFactor
    /// 400 `invalid_code`: a wrong code while setting up or turning off two-factor.
    case invalidCode
    /// 409 `keyring_conflict`: another device changed the keyring first.
    case keyringConflict
    /// 409 `no_passphrase`: an account made with an API key only has no passphrase to change.
    case noPassphrase
    /// 409 `two_factor_enabled`, `two_factor_disabled` or `no_pending_setup`: two-factor changed elsewhere.
    case twoFactorStateChanged
    /// 5xx: try again later.
    case serverError
    case other(Int)
}

/// Classifies a vault answer. `errorCode` is the `detail.error` string, when the body carried one.
public func classifyVaultHTTP(
    status: Int, errorCode: String? = nil, retryAfter: String? = nil, isLogin: Bool = false
) -> VaultHTTPOutcome {
    switch status {
    case 200...299: return .success
    case 401 where errorCode == "two_factor_required": return .twoFactorRequired
    case 401 where errorCode == "invalid_two_factor": return .invalidTwoFactor
    // A wrong passphrase on a call made with a valid device key: not a revoked device.
    case 401 where errorCode == "invalid_credentials": return .invalidCredentials
    case 401: return isLogin ? .invalidCredentials : .unauthorized
    case 400 where errorCode == "invalid_code": return .invalidCode
    case 409 where errorCode == "keyring_conflict": return .keyringConflict
    case 409 where errorCode == "no_passphrase": return .noPassphrase
    case 409 where ["two_factor_enabled", "two_factor_disabled", "no_pending_setup"].contains(errorCode ?? ""):
        return .twoFactorStateChanged
    case 403 where errorCode == "registration_closed": return .registrationClosed
    case 409 where errorCode == "username_taken": return .usernameTaken
    case 409 where errorCode == "revision_conflict": return .revisionConflict
    case 413 where errorCode == "quota_exceeded": return .quotaExceeded
    case 429: return .tooManyAttempts(retryAfter: retryAfter.flatMap { Int($0) })
    case 500...599: return .serverError
    default: return .other(status)
    }
}
