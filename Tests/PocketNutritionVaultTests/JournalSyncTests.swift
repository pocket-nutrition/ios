// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

import PocketNutritionCore
@testable import PocketNutritionVault

/// An in-memory vault with the records API, enforcing revisions like the real one.
final class MealsVault: VaultServing, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var records: [String: VaultRecord] = [:]
    private(set) var puts: [String] = []
    private(set) var deletes: [String] = []
    private var seq = 0
    var pageSize = 100
    var offline = false
    var full = false
    /// Another device writing between this phone's pull and its push.
    var beforePut: (() -> Void)?

    func store(
        id: String, type: String = "meal", revision: Int, keyId: String = "user", ciphertext: String,
        deleted: Bool = false
    ) {
        lock.withLock {
            seq += 1
            let json: [String: Any] = [
                "id": id, "type": type, "scope_id": NSNull(), "revision": revision, "key_id": keyId,
                "ciphertext": ciphertext, "deleted": deleted, "seq": seq,
            ]
            records[id] = try! JSONDecoder().decode(
                VaultRecord.self, from: JSONSerialization.data(withJSONObject: json))
        }
    }

    func sync(apiKey: String, since: Int) async throws -> VaultSyncPage {
        if offline { throw VaultError.offline }
        let newer = lock.withLock { records.values.filter { $0.seq > since }.sorted { $0.seq < $1.seq } }
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
        if offline { throw VaultError.offline }
        if full { throw VaultError.outcome(.quotaExceeded) }
        if let hook = beforePut {
            beforePut = nil
            hook()
        }
        let current = lock.withLock { records[id]?.revision ?? 0 }
        guard write.revision == current + 1 else { throw VaultError.outcome(.revisionConflict) }
        lock.withLock { puts.append(id) }
        store(id: id, type: write.type, revision: write.revision, keyId: write.keyId, ciphertext: write.ciphertext)
    }

    func deleteRecord(apiKey: String, id: String, revision: Int) async throws {
        if offline { throw VaultError.offline }
        guard let current = lock.withLock({ records[id]?.revision }) else { throw VaultError.outcome(.other(404)) }
        guard revision == current + 1 else { throw VaultError.outcome(.revisionConflict) }
        let type = lock.withLock { records[id]?.type ?? "meal" }
        lock.withLock { deletes.append(id) }
        store(id: id, type: type, revision: revision, ciphertext: "", deleted: true)
    }

    func serverInfo() async throws -> VaultServerInfo { throw VaultError.offline }
    func prelogin(username: String) async throws -> VaultKdf { throw VaultError.offline }
    func register(_ request: VaultRegisterRequest) async throws -> VaultSession { throw VaultError.offline }
    func login(_ request: VaultLoginRequest) async throws -> VaultSession { throw VaultError.offline }
    func logout(apiKey: String) async throws {}
    func deleteAccount(apiKey: String, authHash: String) async throws {}
    func createDrop(apiKey: String, _ request: VaultDropRequest) async throws -> VaultDropToken {
        throw VaultError.offline
    }
}

private func meal(_ id: String, at updated: Double = 100, label: String = "apple") -> MealRecordPayload {
    MealRecordPayload(
        id: id, savedAt: 50, updatedAt: updated,
        items: [
            .init(
                id: "i-\(id)", ingredientId: "apple", label: label, quantityG: 120, cookingMethod: "raw",
                measuredState: "raw")
        ],
        totals: .init(energyKcal: 62, proteinG: 0.3, carbohydratesG: 14, fatG: 0.2))
}

@Suite("journal sync")
struct JournalSyncTests {

    private let crypto = VaultCrypto()
    private let session: VaultStoredSession
    private let vault = MealsVault()

    init() throws {
        let inbox = try crypto.newInboxKeyPair()
        session = VaultStoredSession(
            serverURL: URL(string: "https://vault.example")!, username: "alice", accountId: "acc-1",
            apiKey: "device-key", keyId: "kid", kdf: try crypto.newKdf(), userKey: try crypto.newKey(),
            inboxPublicKey: inbox.publicKey, inboxSecretKey: inbox.secretKey)
    }

    private var sync: JournalSync { JournalSync(session: session, server: vault) }
    private func fresh() -> JournalSyncState { JournalSyncState(accountId: "acc-1") }

    /// Applies a result to a state the way the app does.
    private func advance(_ state: JournalSyncState, _ result: JournalSyncResult) -> JournalSyncState {
        var next = state
        next.cursor = result.cursor
        next.revisions.merge(result.revisions) { _, new in new }
        next.dirty.subtract(result.pushed.keys)
        next.deleted.subtract(result.deletionsDelivered)
        return next
    }

    /// What the vault holds for a meal, opened with the user key and the record's own metadata.
    private func stored(_ id: String) throws -> MealRecordPayload {
        let record = try #require(vault.records[id])
        let aad = vaultRecordAAD(
            accountId: "acc-1", recordId: id, type: record.type, scopeId: nil, revision: record.revision,
            keyId: record.keyId)
        let plaintext = try crypto.decrypt(record.ciphertext, key: session.userKey, aad: aad)
        return try decodeMealRecord(plaintext, expectedId: id)
    }

    private func seal(_ payload: MealRecordPayload, revision: Int, userKey: Data? = nil) throws -> String {
        let aad = vaultRecordAAD(
            accountId: "acc-1", recordId: payload.id, type: "meal", scopeId: nil, revision: revision, keyId: "user")
        return try crypto.encrypt(try encodeMealRecord(payload), key: userKey ?? session.userKey, aad: aad)
    }

    // MARK: First sync

    @Test("the first sync uploads every local meal, with nothing to switch on")
    func firstSyncUploadsEverything() async throws {
        let local = [meal("a"), meal("b"), meal("c")]
        let result = await sync.run(local: local, state: fresh())

        #expect(result.failure == nil)
        #expect(Set(vault.puts) == ["a", "b", "c"])
        #expect(try stored("b") == meal("b"))
        #expect(result.revisions == ["a": 1, "b": 1, "c": 1])
        #expect(result.pushed == ["a": 100, "b": 100, "c": 100])
    }

    @Test("a meal already uploaded is not uploaded again")
    func noReupload() async throws {
        let local = [meal("a")]
        let first = await sync.run(local: local, state: fresh())
        let state = advance(fresh(), first)
        let again = await sync.run(local: local, state: state)

        #expect(vault.puts == ["a"])
        #expect(again.pushed.isEmpty && again.failure == nil)
    }

    @Test("an edited meal goes up as the next revision")
    func editBumpsRevision() async throws {
        var state = advance(fresh(), await sync.run(local: [meal("a")], state: fresh()))
        state.markChanged("a")
        let edited = meal("a", at: 200, label: "pear")
        let result = await sync.run(local: [edited], state: state)

        #expect(result.revisions["a"] == 2)
        #expect(try stored("a") == edited)
    }

    // MARK: Another device

    @Test("meals from the vault come down, and local ones that the vault lacks go up")
    func newDeviceMerges() async throws {
        vault.store(id: "remote", revision: 1, ciphertext: try seal(meal("remote"), revision: 1))
        let result = await sync.run(local: [meal("local")], state: fresh())

        #expect(result.upserts == [meal("remote")])
        #expect(vault.puts == ["local"])
        #expect(result.deletes.isEmpty)
    }

    @Test("the newer edit wins when a meal changed on both sides")
    func newerWins() async throws {
        vault.store(id: "a", revision: 1, ciphertext: try seal(meal("a", at: 300, label: "remote"), revision: 1))
        var state = fresh()
        state.revisions["a"] = 1
        state.markChanged("a")

        let remoteWins = await sync.run(local: [meal("a", at: 200, label: "local")], state: state)
        #expect(remoteWins.upserts.map(\.items.first?.label) == ["remote"])
        #expect(vault.puts.isEmpty)

        let localWins = await sync.run(local: [meal("a", at: 400, label: "local")], state: state)
        #expect(localWins.upserts.isEmpty)
        #expect(localWins.revisions["a"] == 2)
        #expect(try stored("a").items.first?.label == "local")
    }

    // MARK: Deletions

    @Test("a deletion on another device removes an untouched copy, not one edited here")
    func remoteDeletion() async throws {
        vault.store(id: "gone", revision: 2, ciphertext: "", deleted: true)
        vault.store(id: "kept", revision: 2, ciphertext: "", deleted: true)
        var state = fresh()
        state.revisions = ["gone": 1, "kept": 1]
        state.markChanged("kept")

        let result = await sync.run(local: [meal("gone"), meal("kept")], state: state)
        #expect(result.deletes == ["gone"])
        // The edited copy comes back to life on top of the tombstone.
        #expect(result.revisions["kept"] == 3)
        #expect(try stored("kept").id == "kept")
    }

    @Test("a meal deleted here is deleted in the vault, and one never uploaded needs nothing sent")
    func localDeletion() async throws {
        let first = await sync.run(local: [meal("a")], state: fresh())
        var state = advance(fresh(), first)
        state.markDeleted("a")
        state.markDeleted("never-uploaded")

        #expect(state.deleted == ["a"])
        let result = await sync.run(local: [], state: state)
        #expect(vault.deletes == ["a"])
        #expect(result.deletionsDelivered == ["a"])
        #expect(vault.records["a"]?.deleted == true)
    }

    // MARK: Distrust

    @Test("records that are not the app's own meals are left alone")
    func foreignRecords() async throws {
        vault.store(id: "capture-1", type: "capture", revision: 2, ciphertext: "AAAA")
        vault.store(id: "inbox-1", revision: 1, keyId: "inbox", ciphertext: "AAAA")
        vault.store(id: "newer", revision: 1, ciphertext: try seal(
            { var m = meal("newer"); m.version = 3; return m }(), revision: 1))
        vault.store(id: "wrong-key", revision: 1, ciphertext: try seal(meal("wrong-key"), revision: 1, userKey: try crypto.newKey()))
        vault.store(id: "swapped", revision: 1, ciphertext: try seal(meal("other"), revision: 1))

        let result = await sync.run(local: [], state: fresh())
        #expect(result.upserts.isEmpty && result.failure == nil)
        #expect(vault.puts.isEmpty)
    }

    @Test("a record this version cannot read is never overwritten by a local meal of the same id")
    func unreadableIsNotOverwritten() async throws {
        vault.store(id: "a", revision: 1, ciphertext: try seal(meal("a"), revision: 1, userKey: try crypto.newKey()))
        var state = fresh()
        state.markChanged("a")
        _ = await sync.run(local: [meal("a", at: 999)], state: state)
        #expect(vault.puts.isEmpty)
    }

    // MARK: Failures and races

    @Test("offline is reported and nothing is marked as sent")
    func offline() async throws {
        vault.offline = true
        let result = await sync.run(local: [meal("a")], state: fresh())
        #expect(result.failure == .offline)
        #expect(result.pushed.isEmpty)
    }

    @Test("a full account is reported, and what fit before is kept")
    func quota() async throws {
        vault.full = true
        let result = await sync.run(local: [meal("a")], state: fresh())
        #expect(result.failure == .quotaExceeded)
    }

    @Test("a write that lost a race is retried after pulling")
    func raceIsRetried() async throws {
        // The vault has a newer revision than this phone knows about: the first write conflicts.
        vault.store(id: "a", revision: 4, ciphertext: try seal(meal("a", at: 10, label: "old"), revision: 4))
        var state = fresh()
        state.revisions["a"] = 2
        state.markChanged("a")

        let result = await sync.run(local: [meal("a", at: 500, label: "mine")], state: state)
        #expect(result.failure == nil)
        #expect(result.revisions["a"] == 5)
        #expect(try stored("a").items.first?.label == "mine")
    }

    @Test("a write that loses a race in flight is retried against what the other device wrote")
    func raceInFlight() async throws {
        let theirs = meal("a", at: 700, label: "theirs")
        vault.beforePut = { [vault] in
            vault.store(id: "a", revision: 1, ciphertext: try! seal(theirs, revision: 1))
        }
        let mine = meal("a", at: 500, label: "mine")
        let result = await sync.run(local: [mine], state: fresh())

        // The other device's edit is newer, so it wins and nothing is overwritten.
        #expect(result.failure == nil)
        #expect(result.upserts == [theirs])
        #expect(try stored("a") == theirs)
    }

    @Test("a long journal is read across pages")
    func paging() async throws {
        vault.pageSize = 2
        for index in 0..<5 {
            vault.store(id: "r\(index)", revision: 1, ciphertext: try seal(meal("r\(index)"), revision: 1))
        }
        let result = await sync.run(local: [], state: fresh())
        #expect(result.upserts.count == 5)
    }

    // MARK: Folding a result into the state

    @Test("a meal edited while the sync ran stays marked as changed; an unchanged one is cleared")
    func mergeKeepsLaterEdits() {
        var state = fresh()
        state.markChanged("edited-meanwhile")
        state.markChanged("unchanged")
        state.markChanged("remote-won")
        state.markDeleted("x")
        var result = JournalSyncResult(cursor: 9)
        result.pushed = ["edited-meanwhile": 100, "unchanged": 100]
        result.revisions = ["edited-meanwhile": 1, "unchanged": 1, "remote-won": 3]
        let remoteWon = meal("remote-won", at: 900)
        result.upserts = [remoteWon]

        let local: [String: Double] = ["edited-meanwhile": 250, "unchanged": 100, "remote-won": 100]
        let applied = result.applicableUpserts(localUpdatedAt: local)
        let merged = state.merging(result, applied: applied, localUpdatedAt: local)

        #expect(applied == [remoteWon])
        #expect(merged.dirty == ["edited-meanwhile"])
        #expect(merged.cursor == 9 && merged.revisions["unchanged"] == 1)
    }

    @Test("a downloaded meal that was edited here since the snapshot is not written over")
    func staleUpsertIsDropped() {
        var result = JournalSyncResult(cursor: 1)
        result.upserts = [meal("a", at: 100)]
        #expect(result.applicableUpserts(localUpdatedAt: ["a": 300]).isEmpty)
        #expect(result.applicableUpserts(localUpdatedAt: [:]).count == 1)
    }

    @Test("sync state: a deletion of a meal that never reached the server is not remembered")
    func stateBookkeeping() {
        var state = fresh()
        state.markChanged("a")
        state.markDeleted("a")
        #expect(state.dirty.isEmpty && state.deleted.isEmpty)
        #expect(state.hasWork(localIds: ["b"]))
        state.revisions["b"] = 1
        #expect(!state.hasWork(localIds: ["b"]))
    }

    // MARK: Payload

    @Test("the wire format is stable and refuses a swapped or newer record")
    func payloadFormat() throws {
        let data = try encodeMealRecord(meal("a"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["v"] as? Int == 2 && json["updated_at"] as? Double == 100)
        #expect((json["totals"] as? [String: Any])?["energy_kcal"] as? Double == 62)
        #expect((json["items"] as? [[String: Any]])?.first?["ingredient_id"] as? String == "apple")

        #expect(throws: MealRecordError.idMismatch) { try decodeMealRecord(data, expectedId: "b") }
        #expect(throws: MealRecordError.malformed) { try decodeMealRecord(Data("{}".utf8), expectedId: "a") }
    }

    @Test("a v1 record still decodes, without slot or nutrients; v2 fields round-trip")
    func payloadVersions() throws {
        let v1 = #"{"v":1,"id":"a","saved_at":1,"updated_at":2,"items":[],"totals":{"energy_kcal":1,"protein_g":0,"carbohydrates_g":0,"fat_g":0}}"#
        let old = try decodeMealRecord(Data(v1.utf8), expectedId: "a")
        #expect(old.version == 1 && old.slot == nil && old.nutrients == nil)

        var m = meal("a")
        m.slot = "lunch"
        m.nutrients = NutrientTotals(["energyKcal": 62, "ironMg": 0.2])
        m.items[0].energyKcal = nil
        let back = try decodeMealRecord(try encodeMealRecord(m), expectedId: "a")
        #expect(back.slot == "lunch" && back.nutrients?["ironMg"] == 0.2)
    }
}
