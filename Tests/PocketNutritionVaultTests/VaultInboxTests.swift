// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

import PocketNutritionCore
@testable import PocketNutritionVault

/// An in-memory vault with just the records API, paged like the real one.
private final class RecordsVault: VaultServing, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var records: [VaultRecord] = []
    private(set) var drops: [VaultDropRequest] = []
    private(set) var puts: [(id: String, write: VaultRecordWrite)] = []
    var pageSize = 100
    var failSync = false
    var failPut = false
    private var seq = 0

    /// Plays the worker: a record written by a drop, sealed to `publicKey`.
    func deposit(id: String, plaintext: Data, to publicKey: Data, crypto: VaultCrypto = VaultCrypto()) throws {
        try store(id: id, revision: 1, keyId: "inbox", ciphertext: crypto.seal(plaintext, to: publicKey))
    }

    func store(id: String, revision: Int, keyId: String, ciphertext: String, deleted: Bool = false) throws {
        lock.withLock {
            seq += 1
            records.removeAll { $0.id == id }
            records.append(Self.record(id: id, revision: revision, keyId: keyId, ciphertext: ciphertext, seq: seq, deleted: deleted))
        }
    }

    private static func record(id: String, revision: Int, keyId: String, ciphertext: String, seq: Int, deleted: Bool) -> VaultRecord {
        let json: [String: Any] = [
            "id": id, "type": "capture", "scope_id": NSNull(), "revision": revision, "key_id": keyId,
            "ciphertext": ciphertext, "deleted": deleted, "seq": seq,
        ]
        return try! JSONDecoder().decode(VaultRecord.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func createDrop(apiKey: String, _ request: VaultDropRequest) async throws -> VaultDropToken {
        lock.withLock { drops.append(request) }
        let json = #"{"drop_id":"d1","token":"pnv_drop","expires_at":"2030-01-01T00:00:00Z"}"#
        return try JSONDecoder().decode(VaultDropToken.self, from: Data(json.utf8))
    }

    func sync(apiKey: String, since: Int) async throws -> VaultSyncPage {
        if failSync { throw VaultError.offline }
        let newer = lock.withLock { records.filter { $0.seq > since }.sorted { $0.seq < $1.seq } }
        let page = Array(newer.prefix(pageSize))
        let body: [String: Any] = [
            "records": page.map { r in
                [
                    "id": r.id, "type": r.type, "scope_id": NSNull(), "revision": r.revision, "key_id": r.keyId,
                    "ciphertext": r.ciphertext, "deleted": r.deleted, "seq": r.seq,
                ] as [String: Any]
            },
            "cursor": page.last?.seq ?? since, "has_more": newer.count > page.count,
        ]
        return try JSONDecoder().decode(VaultSyncPage.self, from: JSONSerialization.data(withJSONObject: body))
    }

    func putRecord(apiKey: String, id: String, _ write: VaultRecordWrite) async throws {
        if failPut { throw VaultError.offline }
        lock.withLock { puts.append((id, write)) }
        try store(id: id, revision: write.revision, keyId: write.keyId, ciphertext: write.ciphertext)
    }

    // Not used here.
    func serverInfo() async throws -> VaultServerInfo { throw VaultError.offline }
    func prelogin(username: String) async throws -> VaultKdf { throw VaultError.offline }
    func register(_ request: VaultRegisterRequest) async throws -> VaultSession { throw VaultError.offline }
    func login(_ request: VaultLoginRequest) async throws -> VaultSession { throw VaultError.offline }
    func logout(apiKey: String) async throws {}
    func deleteAccount(apiKey: String, authHash: String) async throws {}
    func deleteRecord(apiKey: String, id: String, revision: Int) async throws {}
}

private func payload(recordId: String, status: String = "done", withResult: Bool = true) -> Data {
    let result = #"{"transcript":"une pomme","language":"fr","items":[{"raw_text":"une pomme","quantity":1,"unit":"piece","cooking_method":null,"candidates":[{"ingredient_id":"pomme_crue","name":"Apple, raw","score":0.9}]}]}"#
    return Data(
        #"{"v":1,"record_id":"\#(recordId)","ticket_id":"t1","status":"\#(status)","result":\#(withResult ? result : "null"),"error":null,"completed_at":1.0}"#
            .utf8)
}

@Suite("vault inbox")
struct VaultInboxTests {

    private let crypto = VaultCrypto()
    private let session: VaultStoredSession
    private let vault = RecordsVault()

    init() throws {
        let userKey = try crypto.newKey()
        let inbox = try crypto.newInboxKeyPair()
        session = VaultStoredSession(
            serverURL: URL(string: "https://vault.example")!, username: "alice", accountId: "acc-1",
            apiKey: "device-key", keyId: "kid", kdf: try crypto.newKdf(), userKey: userKey,
            inboxPublicKey: inbox.publicKey, inboxSecretKey: inbox.secretKey)
    }

    private var inbox: VaultInbox { VaultInbox(session: session, server: vault) }

    // MARK: Drop

    @Test("a drop is minted for a new record, sealed to the inbox, and handed over with the vault address")
    func prepareDrop() async throws {
        let grant = try await inbox.prepareDrop()

        let request = try #require(vault.drops.first)
        #expect(request.recordId == grant.recordId)
        #expect(request.type == "capture" && request.keyId == "inbox")
        #expect(request.ttlSeconds == VaultInbox.dropTTLSeconds && request.maxWrites == VaultInbox.dropMaxWrites)
        #expect(grant.token == "pnv_drop")
        #expect(grant.vaultURL == "https://vault.example")
        #expect(grant.inboxPublicKey == session.inboxPublicKey.base64EncodedString())
        // The server only accepts ids of this shape, and the recognition service checks the same rule.
        #expect(isValidTicketId(grant.recordId))
    }

    @Test("every drop gets its own record id")
    func recordIdsDiffer() async throws {
        let first = try await inbox.prepareDrop()
        let second = try await inbox.prepareDrop()
        #expect(first.recordId != second.recordId)
    }

    // MARK: Collect

    @Test("the worker's sealed result is opened and re-saved under the user key")
    func collectsAndResaves() async throws {
        try vault.deposit(id: "rec-1", plaintext: payload(recordId: "rec-1"), to: session.inboxPublicKey)

        guard case .result(let result) = try await inbox.collect(recordId: "rec-1") else {
            Issue.record("expected a result")
            return
        }
        #expect(result.transcript == "une pomme")
        #expect(result.items.first?.candidates.first?.ingredientId == "pomme_crue")

        // The drop wrote revision 1; the re-save is revision 2 under the user key, bound to its metadata.
        let put = try #require(vault.puts.first)
        #expect(put.id == "rec-1" && put.write.revision == 2 && put.write.keyId == "user")
        let aad = vaultRecordAAD(
            accountId: "acc-1", recordId: "rec-1", type: "capture", scopeId: nil, revision: 2, keyId: "user")
        let plaintext = try crypto.decrypt(put.write.ciphertext, key: session.userKey, aad: aad)
        #expect(plaintext == payload(recordId: "rec-1"))
    }

    @Test("a record already re-saved is read with the user key and not written again")
    func collectsAResavedRecord() async throws {
        try vault.deposit(id: "rec-1", plaintext: payload(recordId: "rec-1"), to: session.inboxPublicKey)
        _ = try await inbox.collect(recordId: "rec-1")
        let putsAfterFirst = vault.puts.count

        guard case .result = try await inbox.collect(recordId: "rec-1") else {
            Issue.record("expected a result")
            return
        }
        #expect(vault.puts.count == putsAfterFirst)
    }

    @Test("a failed re-save does not lose the result, and the next collect finds the record still sealed")
    func resaveFailureKeepsTheResult() async throws {
        try vault.deposit(id: "rec-1", plaintext: payload(recordId: "rec-1"), to: session.inboxPublicKey)
        vault.failPut = true
        guard case .result = try await inbox.collect(recordId: "rec-1") else {
            Issue.record("expected a result")
            return
        }
        #expect(vault.records.first?.keyId == "inbox")
        vault.failPut = false
        _ = try await inbox.collect(recordId: "rec-1")
        #expect(vault.records.first?.keyId == "user")
    }

    @Test("no record yet, or a deleted one, is 'not there'")
    func notThere() async throws {
        #expect(try await inbox.collect(recordId: "rec-1") == .notThere)
        try vault.store(id: "rec-1", revision: 2, keyId: "user", ciphertext: "", deleted: true)
        #expect(try await inbox.collect(recordId: "rec-1") == .notThere)
    }

    @Test("a record is found on a later page")
    func paging() async throws {
        vault.pageSize = 2
        for index in 0..<5 {
            try vault.deposit(id: "other-\(index)", plaintext: payload(recordId: "other-\(index)"), to: session.inboxPublicKey)
        }
        try vault.deposit(id: "rec-1", plaintext: payload(recordId: "rec-1"), to: session.inboxPublicKey)
        guard case .result = try await inbox.collect(recordId: "rec-1") else {
            Issue.record("expected a result")
            return
        }
    }

    @Test("a payload meant for another record is refused: a swapped or replayed drop")
    func wrongRecordId() async throws {
        try vault.deposit(id: "rec-1", plaintext: payload(recordId: "someone-else"), to: session.inboxPublicKey)
        #expect(try await inbox.collect(recordId: "rec-1") == .unreadable)
        #expect(vault.puts.isEmpty)
    }

    @Test("a failed or non-final delivery, or one without a result, is unreadable")
    func notADelivery() async throws {
        for (index, plaintext) in [
            payload(recordId: "r0", status: "failed"),
            payload(recordId: "r1", status: "extracting"),
            payload(recordId: "r2", withResult: false),
            Data("not json".utf8),
        ].enumerated() {
            try vault.deposit(id: "r\(index)", plaintext: plaintext, to: session.inboxPublicKey)
            #expect(try await inbox.collect(recordId: "r\(index)") == .unreadable, "case \(index)")
        }
    }

    @Test("something sealed to another key does not open")
    func sealedToAnotherKey() async throws {
        let stranger = try crypto.newInboxKeyPair()
        try vault.deposit(id: "rec-1", plaintext: payload(recordId: "rec-1"), to: stranger.publicKey)
        #expect(try await inbox.collect(recordId: "rec-1") == .unreadable)
    }

    @Test("a user-key record whose metadata was changed does not open")
    func tamperedMetadata() async throws {
        // Encrypted for revision 2, but stored as revision 3: the AAD no longer matches.
        let aad = vaultRecordAAD(
            accountId: "acc-1", recordId: "rec-1", type: "capture", scopeId: nil, revision: 2, keyId: "user")
        let sealed = try crypto.encrypt(payload(recordId: "rec-1"), key: session.userKey, aad: aad)
        try vault.store(id: "rec-1", revision: 3, keyId: "user", ciphertext: sealed)
        #expect(try await inbox.collect(recordId: "rec-1") == .unreadable)
    }

    @Test("an unknown key id is unreadable")
    func unknownKeyId() async throws {
        try vault.store(id: "rec-1", revision: 1, keyId: "scope:x:1", ciphertext: "AAAA")
        #expect(try await inbox.collect(recordId: "rec-1") == .unreadable)
    }

    @Test("a network failure is thrown, not mistaken for 'not there'")
    func offline() async {
        vault.failSync = true
        await #expect(throws: VaultError.offline) { try await inbox.collect(recordId: "rec-1") }
    }
}
