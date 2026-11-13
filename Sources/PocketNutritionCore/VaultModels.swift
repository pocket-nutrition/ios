// SPDX-License-Identifier: MPL-2.0

import Foundation

// Wire types for the vault API. Field names follow the server's snake_case JSON; decoding ignores
// keys it does not know, so a newer server never breaks an older app.

public struct VaultKdf: Codable, Equatable, Sendable {
    public let alg: String
    /// Base64, 16 bytes.
    public let salt: String
    public let opslimit: Int
    public let memlimit: Int

    public init(alg: String = "argon2id", salt: String, opslimit: Int, memlimit: Int) {
        self.alg = alg
        self.salt = salt
        self.opslimit = opslimit
        self.memlimit = memlimit
    }
}

public struct VaultServerInfo: Codable, Equatable, Sendable {
    public let name: String
    public let version: String
    /// `open` or `closed`.
    public let registration: String
    public let quotaBytes: Int

    public var isRegistrationOpen: Bool { registration == "open" }

    private enum CodingKeys: String, CodingKey {
        case name, version, registration
        case quotaBytes = "quota_bytes"
    }
}

public struct VaultKeyring: Codable, Equatable, Sendable {
    public let blob: String?
    public let version: Int

    public init(blob: String?, version: Int) {
        self.blob = blob
        self.version = version
    }
}

/// What register and login both return: this device's API key plus the account's wrapped keys.
public struct VaultSession: Codable, Equatable, Sendable {
    public let accountId: String
    public let apiKey: String
    public let keyId: String
    public let keyring: VaultKeyring

    private enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case apiKey = "api_key"
        case keyId = "key_id"
        case keyring
    }
}

public struct VaultRegisterRequest: Codable, Equatable, Sendable {
    public let username: String
    public let kdf: VaultKdf
    public let authHash: String
    public let keyring: String
    public let deviceLabel: String

    public init(username: String, kdf: VaultKdf, authHash: String, keyring: String, deviceLabel: String) {
        self.username = username
        self.kdf = kdf
        self.authHash = authHash
        self.keyring = keyring
        self.deviceLabel = deviceLabel
    }

    private enum CodingKeys: String, CodingKey {
        case username, kdf, keyring
        case authHash = "auth_hash"
        case deviceLabel = "device_label"
    }
}

public struct VaultLoginRequest: Codable, Equatable, Sendable {
    public let username: String
    public let authHash: String
    public let deviceLabel: String
    /// Only for an account with two-factor on; omitted from the JSON when nil.
    public let totpCode: String?
    public let recoveryCode: String?

    public init(
        username: String, authHash: String, deviceLabel: String, twoFactor: VaultTwoFactorCode? = nil
    ) {
        self.username = username
        self.authHash = authHash
        self.deviceLabel = deviceLabel
        switch twoFactor {
        case .totp(let code): totpCode = code; recoveryCode = nil
        case .recovery(let code): totpCode = nil; recoveryCode = code
        case nil: totpCode = nil; recoveryCode = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case username
        case authHash = "auth_hash"
        case deviceLabel = "device_label"
        case totpCode = "totp_code"
        case recoveryCode = "recovery_code"
    }
}

public struct VaultRecord: Codable, Equatable, Sendable {
    public let id: String
    public let type: String
    public let scopeId: String?
    public let revision: Int
    public let keyId: String
    /// Base64 `nonce || AEAD ciphertext` (user key) or a sealed box (inbox); empty for a tombstone.
    public let ciphertext: String
    public let deleted: Bool
    public let seq: Int

    public var isInboxDrop: Bool { keyId == VaultProtocol.inboxKeyId }

    private enum CodingKeys: String, CodingKey {
        case id, type, revision, ciphertext, deleted, seq
        case scopeId = "scope_id"
        case keyId = "key_id"
    }
}

public struct VaultSyncPage: Codable, Equatable, Sendable {
    public let records: [VaultRecord]
    public let cursor: Int
    public let hasMore: Bool

    private enum CodingKeys: String, CodingKey {
        case records, cursor
        case hasMore = "has_more"
    }
}

public struct VaultRecordWrite: Codable, Equatable, Sendable {
    public let type: String
    public let scopeId: String?
    /// The new revision: the current one + 1, or 1 for a new record.
    public let revision: Int
    public let keyId: String
    public let ciphertext: String

    public init(type: String, scopeId: String?, revision: Int, keyId: String, ciphertext: String) {
        self.type = type
        self.scopeId = scopeId
        self.revision = revision
        self.keyId = keyId
        self.ciphertext = ciphertext
    }

    private enum CodingKeys: String, CodingKey {
        case type, revision, ciphertext
        case scopeId = "scope_id"
        case keyId = "key_id"
    }
}

public struct VaultDropRequest: Codable, Equatable, Sendable {
    public let recordId: String
    public let type: String
    public let keyId: String
    public let ttlSeconds: Int
    public let maxWrites: Int

    public init(recordId: String, type: String, keyId: String, ttlSeconds: Int, maxWrites: Int) {
        self.recordId = recordId
        self.type = type
        self.keyId = keyId
        self.ttlSeconds = ttlSeconds
        self.maxWrites = maxWrites
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case recordId = "record_id"
        case keyId = "key_id"
        case ttlSeconds = "ttl_s"
        case maxWrites = "max_writes"
    }
}

public struct VaultDropToken: Codable, Equatable, Sendable {
    public let dropId: String
    public let token: String
    public let expiresAt: String

    private enum CodingKeys: String, CodingKey {
        case token
        case dropId = "drop_id"
        case expiresAt = "expires_at"
    }
}

// MARK: - Drop payloads

/// What the recognition service seals into the vault: a finished (or failed) capture.
public struct VaultDropPayload: Codable, Equatable, Sendable {
    public let version: Int
    public let recordId: String
    public let ticketId: String
    public let status: RecognitionStatus
    public let result: RecognitionResult?
    public let error: String?

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case recordId = "record_id"
        case ticketId = "ticket_id"
        case status, result, error
    }
}

public enum VaultDropPayloadError: Error, Equatable, Sendable {
    case malformed
    case unsupportedVersion(Int)
    /// The payload names another record than the one it arrived in: a swapped or replayed drop.
    /// Sealed boxes carry no AAD, so this embedded id is the only binding there is.
    case recordMismatch
    /// A status that is not final cannot be a delivery.
    case notTerminal
}

/// Decodes a decrypted drop and refuses one that was not meant for `expectedRecordId`.
public func decodeVaultDropPayload(
    _ plaintext: Data, expectedRecordId: String
) throws(VaultDropPayloadError) -> VaultDropPayload {
    let payload: VaultDropPayload
    do { payload = try JSONDecoder().decode(VaultDropPayload.self, from: plaintext) } catch { throw .malformed }
    guard payload.version == 1 else { throw .unsupportedVersion(payload.version) }
    guard payload.recordId == expectedRecordId else { throw .recordMismatch }
    guard payload.status.isTerminal else { throw .notTerminal }
    return payload
}
