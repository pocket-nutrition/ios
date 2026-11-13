// SPDX-License-Identifier: MPL-2.0

import Foundation
import PocketNutritionCore

/// What the recognition service needs to deposit one result in the vault: where, with which write-only
/// token, under which record, and the public key to seal it to.
public struct VaultDropGrant: Sendable, Equatable {
    public let vaultURL: String
    public let token: String
    public let recordId: String
    /// Base64 X25519 public key.
    public let inboxPublicKey: String
}

/// What `collect` found for a record.
public enum VaultCollected: Sendable, Equatable {
    case result(RecognitionResult)
    /// Nothing under that id yet (or it was deleted): ask again later.
    case notThere
    /// A record is there but is not a usable delivery of this capture: wrong id, not final, undecodable,
    /// or it does not open with this phone's keys. Asking again will not change that.
    case unreadable
}

/// The phone's side of a capture delivered through the vault: mint the write-only drop that goes to the
/// recognition service, then collect what the worker sealed into it.
///
/// Holds the unlocked keys of one linked session, so build it from `VaultStoredSession` and drop it when
/// the work is done.
public struct VaultInbox: Sendable {

    /// The drop token outlives the 48 h ticket, so a late worker can still deposit.
    public static let dropTTLSeconds = 3 * 24 * 3600
    /// One retry if the first deposit's answer was lost; the token can do nothing else.
    public static let dropMaxWrites = 2

    private let session: VaultStoredSession
    private let server: any VaultServing
    private let crypto: VaultCrypto

    public init(session: VaultStoredSession, server: any VaultServing, crypto: VaultCrypto = VaultCrypto()) {
        self.session = session
        self.server = server
        self.crypto = crypto
    }

    /// A fresh record id and a drop token for it. Nothing is written yet.
    public func prepareDrop() async throws -> VaultDropGrant {
        let recordId = UUID().uuidString.lowercased()
        let token = try await server.createDrop(
            apiKey: session.apiKey,
            VaultDropRequest(
                recordId: recordId, type: VaultProtocol.captureRecordType, keyId: VaultProtocol.inboxKeyId,
                ttlSeconds: Self.dropTTLSeconds, maxWrites: Self.dropMaxWrites))
        return VaultDropGrant(
            vaultURL: session.serverURL.absoluteString, token: token.token, recordId: recordId,
            inboxPublicKey: session.inboxPublicKey.base64EncodedString())
    }

    /// Finds the record, opens it, and re-saves it under the user key so it becomes an ordinary record of
    /// the account (and the drop's hold on it ends). The re-save is best effort: the result is returned
    /// even if it fails, and a later `collect` finds the record still sealed and tries again.
    public func collect(recordId: String) async throws -> VaultCollected {
        guard let record = try await find(recordId), !record.deleted else { return .notThere }
        guard let plaintext = open(record) else { return .unreadable }
        guard let payload = try? decodeVaultDropPayload(plaintext, expectedRecordId: recordId),
              payload.status == .done, let result = payload.result
        else { return .unreadable }
        if record.isInboxDrop { await resave(record, plaintext: plaintext) }
        return .result(result)
    }

    // MARK: - Plumbing

    private func find(_ recordId: String) async throws -> VaultRecord? {
        var cursor = 0
        while true {
            let page = try await server.sync(apiKey: session.apiKey, since: cursor)
            if let match = page.records.first(where: { $0.id == recordId }) { return match }
            guard page.hasMore, page.cursor > cursor else { return nil }
            cursor = page.cursor
        }
    }

    /// The plaintext of a delivered record, or nil if it does not open. A drop is sealed to the inbox key;
    /// a record already re-saved is under the user key and bound to its own metadata.
    private func open(_ record: VaultRecord) -> Data? {
        switch record.keyId {
        case VaultProtocol.inboxKeyId:
            return try? crypto.openSealed(record.ciphertext, inbox: session.keys.inbox)
        case VaultProtocol.userKeyId:
            let bound = aad(for: record, revision: record.revision, keyId: record.keyId)
            return try? crypto.decrypt(record.ciphertext, key: session.userKey, aad: bound)
        default:
            return nil
        }
    }

    private func resave(_ record: VaultRecord, plaintext: Data) async {
        let revision = record.revision + 1
        let bound = aad(for: record, revision: revision, keyId: VaultProtocol.userKeyId)
        guard let sealed = try? crypto.encrypt(plaintext, key: session.userKey, aad: bound) else { return }
        try? await server.putRecord(
            apiKey: session.apiKey, id: record.id,
            VaultRecordWrite(
                type: record.type, scopeId: record.scopeId, revision: revision,
                keyId: VaultProtocol.userKeyId, ciphertext: sealed))
    }

    private func aad(for record: VaultRecord, revision: Int, keyId: String) -> Data {
        vaultRecordAAD(
            accountId: session.accountId, recordId: record.id, type: record.type, scopeId: record.scopeId,
            revision: revision, keyId: keyId)
    }
}
