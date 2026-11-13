// SPDX-License-Identifier: MPL-2.0

import Foundation

// Account-security wire types and rules: linked devices, changing the passphrase, two-factor login, the
// fingerprint phrase and the session timeout. No cryptography here (see `PocketNutritionVault`).

// MARK: - Devices

/// One device key of the account, as `GET /v1/keys` lists it. Revoked keys are listed too.
public struct VaultDevice: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let role: String
    public let label: String
    /// ISO 8601, as the server wrote it.
    public let createdAt: String
    public let revokedAt: String?

    public init(id: String, role: String = "owner", label: String, createdAt: String, revokedAt: String? = nil) {
        self.id = id
        self.role = role
        self.label = label
        self.createdAt = createdAt
        self.revokedAt = revokedAt
    }

    public var isActive: Bool { revokedAt == nil }

    /// The server writes microseconds and either `Z` or `+00:00`; nil when it is neither.
    public var createdDate: Date? { parseVaultTimestamp(createdAt) }

    private enum CodingKeys: String, CodingKey {
        case id, role, label
        case createdAt = "created_at"
        case revokedAt = "revoked_at"
    }
}

/// ISO 8601 with or without fractional seconds. Python writes six fractional digits, which the
/// fractional-seconds formatter accepts.
public func parseVaultTimestamp(_ raw: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: raw) { return date }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    if let date = plain.date(from: raw) { return date }
    // No offset at all (a naive datetime): the server stores UTC.
    return plain.date(from: raw + "Z") ?? fractional.date(from: raw + "Z")
}

// MARK: - Changing the passphrase (always through the reset endpoint)

/// `POST /v1/account/passphrase/reset`: a forgotten passphrase replaced from a device that is still
/// linked. No proof of the old passphrase (nobody knows it any more); the device key and, when two-factor is
/// on, a code are the proof. The keyring wraps the same user key under a new passphrase AND a new recovery key.
public struct VaultPassphraseResetRequest: Codable, Equatable, Sendable {
    public let newAuthHash: String
    public let kdf: VaultKdf
    public let keyring: String
    public let baseVersion: Int
    /// Only for an account with two-factor on; omitted from the JSON when nil.
    public let totpCode: String?
    public let recoveryCode: String?

    public init(
        newAuthHash: String, kdf: VaultKdf, keyring: String, baseVersion: Int, twoFactor: VaultTwoFactorCode? = nil
    ) {
        self.newAuthHash = newAuthHash
        self.kdf = kdf
        self.keyring = keyring
        self.baseVersion = baseVersion
        switch twoFactor {
        case .totp(let code): totpCode = code; recoveryCode = nil
        case .recovery(let code): totpCode = nil; recoveryCode = code
        case nil: totpCode = nil; recoveryCode = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kdf, keyring
        case newAuthHash = "new_auth_hash"
        case baseVersion = "base_version"
        case totpCode = "totp_code"
        case recoveryCode = "recovery_code"
    }
}

public struct VaultPassphraseChanged: Codable, Equatable, Sendable {
    public let version: Int
    /// Other devices the server unlinked: they hold the old KDF and must log in again.
    public let revokedDevices: Int

    private enum CodingKeys: String, CodingKey {
        case version
        case revokedDevices = "revoked_devices"
    }
}

// MARK: - Two-factor

public struct VaultTwoFactorStatus: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let recoveryCodesLeft: Int

    public init(enabled: Bool, recoveryCodesLeft: Int) {
        self.enabled = enabled
        self.recoveryCodesLeft = recoveryCodesLeft
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case recoveryCodesLeft = "recovery_codes_left"
    }
}

/// A TOTP secret waiting for its first code. The secret is shown so it can be typed into an
/// authenticator by hand; the URI opens one directly.
public struct VaultTwoFactorSetup: Codable, Equatable, Sendable {
    public let secret: String
    public let otpauthURI: String

    public init(secret: String, otpauthURI: String) {
        self.secret = secret
        self.otpauthURI = otpauthURI
    }

    /// The secret in groups of four, easier to copy by eye.
    public var groupedSecret: String {
        let characters = Array(secret)
        return stride(from: 0, to: characters.count, by: 4)
            .map { String(characters[$0..<min($0 + 4, characters.count)]) }
            .joined(separator: " ")
    }

    private enum CodingKeys: String, CodingKey {
        case secret
        case otpauthURI = "otpauth_uri"
    }
}

public struct VaultRecoveryCodes: Codable, Equatable, Sendable {
    public let recoveryCodes: [String]

    private enum CodingKeys: String, CodingKey {
        case recoveryCodes = "recovery_codes"
    }
}

/// What a person typed in the two-factor field: six digits from the authenticator, or one of the
/// printed recovery codes (`xxxx-xxxx-xxxx`). Nil when it can be neither.
public enum VaultTwoFactorCode: Equatable, Sendable {
    case totp(String)
    case recovery(String)

    public init?(_ raw: String) {
        let compact = raw.filter { !$0.isWhitespace }
        if compact.count == 6, compact.allSatisfy({ $0.isASCII && $0.isNumber }) {
            self = .totp(compact)
            return
        }
        let letters = compact.lowercased().filter { $0 != "-" }
        let alphabet = Set("abcdefghijklmnopqrstuvwxyz234567")
        guard letters.count == 12, letters.allSatisfy({ alphabet.contains($0) }) else { return nil }
        self = .recovery(letters)
    }
}

// MARK: - Fingerprint phrase

/// Five words naming the account's keys, the same on every device that opened them. Two devices
/// (or the web viewer) showing different words means one of them was handed other keys.
///
/// `digest` is BLAKE2b-256 of `vaultFingerprintInput`. Each word is one big-endian 32-bit chunk modulo
/// the 7776-word EFF list; the bias (under 2e-6 per word) is irrelevant for a comparison phrase.
public func vaultFingerprintWords(digest: Data) -> [String]? {
    let bytes = [UInt8](digest)
    let wordCount = 5
    guard bytes.count >= wordCount * 4 else { return nil }
    let words = EffLongWordlist.words
    return (0..<wordCount).map { index in
        let chunk = bytes[(index * 4)..<(index * 4 + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return words[Int(chunk % UInt32(words.count))]
    }
}

/// `pnv1|fingerprint|<account_id>|` followed by the raw 32-byte inbox public key.
public func vaultFingerprintInput(accountId: String, inboxPublicKey: Data) -> Data {
    Data("\(VaultProtocol.aadVersion)|fingerprint|\(accountId)|".utf8) + inboxPublicKey
}

// MARK: - Session timeout

/// How long the app may stay in the background before the vault session expires.
public enum VaultSessionTimeout: String, CaseIterable, Sendable {
    case immediately
    case oneMinute
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case fourHours
    case onRestart
    case never

    var seconds: TimeInterval? {
        switch self {
        case .immediately: 0
        case .oneMinute: 60
        case .fiveMinutes: 5 * 60
        case .fifteenMinutes: 15 * 60
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        case .fourHours: 4 * 60 * 60
        case .onRestart, .never: nil
        }
    }
}

/// What happens when the session expires. `lock` only exists with Face ID turned on: without it there
/// is nothing to unlock with but the passphrase, and logging in again is exactly that.
public enum VaultTimeoutAction: String, CaseIterable, Sendable {
    case lock
    case logOut
}

/// Whether the session expired while the app was away.
///
/// - `backgroundedAt`: when the app last left the foreground, nil if never recorded.
/// - `isColdLaunch`: the process was started (not just brought back). A restart always expires an
///   `onRestart` session; for timed ones, a launch with no recorded time expires too, since nothing says
///   how long the app was gone.
public func isVaultSessionExpired(
    timeout: VaultSessionTimeout, backgroundedAt: Date?, now: Date, isColdLaunch: Bool
) -> Bool {
    switch timeout {
    case .never: return false
    case .onRestart: return isColdLaunch
    default:
        guard let backgroundedAt else { return isColdLaunch }
        return now.timeIntervalSince(backgroundedAt) >= (timeout.seconds ?? 0)
    }
}

/// The action that actually applies: a lock without Face ID does nothing (the UI never offers it, but
/// a setting saved before Face ID was turned off must not turn into a surprise logout).
public func effectiveVaultTimeoutAction(
    timeout: VaultSessionTimeout, action: VaultTimeoutAction, isBiometricLockEnabled: Bool
) -> VaultTimeoutAction? {
    guard timeout != .never else { return nil }
    if action == .lock && !isBiometricLockEnabled { return nil }
    return action
}
