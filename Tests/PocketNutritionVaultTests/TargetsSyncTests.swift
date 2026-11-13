// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

import PocketNutritionCore
@testable import PocketNutritionVault

private func weight(_ date: String, _ kg: Double, at updated: Double = 100) -> TargetsVaultRecord {
    .weight(WeightRecordPayload(updatedAt: updated, date: date, kg: kg))
}

private func profile(pal: Double, at updated: Double = 100) -> TargetsVaultRecord {
    .profile(ProfileRecordPayload(
        updatedAt: updated,
        versions: [
            ProfileVersion(
                effectiveFrom: "2026-11-01", birthYear: 1996, basis: .male, situation: .none, pal: pal, weightKg: 75)
        ]))
}

private let targets = TargetsVaultRecord.targets(TargetsRecordPayload(
    updatedAt: 100,
    overrides: [OverrideVersion(effectiveFrom: "2026-11-01", values: ["energyKcal": TargetOverride(min: 2200, max: 2200)])],
    watchList: WatchList(preset: "standard", keys: ["energyKcal"])))

/// The profile, targets and weight records sync through the same rules as meals, in their own pass.
@Suite("targets sync")
struct TargetsSyncTests {

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

    private var sync: TargetsSync { TargetsSync(session: session, server: vault) }
    private func fresh() -> JournalSyncState { JournalSyncState(accountId: "acc-1") }

    private func stored(_ id: String) throws -> TargetsVaultRecord {
        let record = try #require(vault.records[id])
        let aad = vaultRecordAAD(
            accountId: "acc-1", recordId: id, type: record.type, scopeId: nil, revision: record.revision,
            keyId: record.keyId)
        let plaintext = try crypto.decrypt(record.ciphertext, key: session.userKey, aad: aad)
        return try decodeTargetsRecord(plaintext, type: record.type, expectedId: id)
    }

    private func seal(_ id: String, type: String, plaintext: Data, revision: Int) throws -> String {
        let aad = vaultRecordAAD(
            accountId: "acc-1", recordId: id, type: type, scopeId: nil, revision: revision, keyId: "user")
        return try crypto.encrypt(plaintext, key: session.userKey, aad: aad)
    }

    private func put(_ record: TargetsVaultRecord, revision: Int) throws {
        vault.store(
            id: record.recordId, type: record.recordType, revision: revision,
            ciphertext: try seal(record.recordId, type: record.recordType, plaintext: try encodeTargetsRecord(record), revision: revision))
    }

    @Test("the three record types go up, each under its own type, and round-trip")
    func uploadsAndRoundTrips() async throws {
        let local = [profile(pal: 1.6), targets, weight("2026-11-06", 70.5)]
        let result = await sync.run(local: local, state: fresh())

        #expect(result.failure == nil)
        #expect(Set(vault.puts) == ["profile", "targets", "weight-2026-11-06"])
        #expect(vault.records["profile"]?.type == "profile")
        #expect(vault.records["targets"]?.type == "targets")
        #expect(vault.records["weight-2026-11-06"]?.type == "weight")
        for record in local { #expect(try stored(record.recordId) == record) }
    }

    @Test("records from another device come down, the newer edit wins")
    func downloadsAndNewerWins() async throws {
        try put(profile(pal: 1.8, at: 300), revision: 1)
        try put(weight("2026-11-05", 71), revision: 1)
        var state = fresh()
        state.revisions["profile"] = 1
        state.markChanged("profile")

        let result = await sync.run(local: [profile(pal: 1.4, at: 200)], state: state)
        #expect(Set(result.upserts.map(\.recordId)) == ["profile", "weight-2026-11-05"])
        #expect(result.upserts.contains(profile(pal: 1.8, at: 300)))
        #expect(vault.puts.isEmpty)
    }

    @Test("a record from a newer version is reported, never overwritten")
    func newerVersionNeverOverwritten() async throws {
        let newer = Data(#"{ "version": 9, "updated_at": 1, "versions": [] }"#.utf8)
        vault.store(id: "profile", type: "profile", revision: 1, ciphertext: try seal("profile", type: "profile", plaintext: newer, revision: 1))
        var state = fresh()
        state.markChanged("profile")

        let result = await sync.run(local: [profile(pal: 1.6, at: 500)], state: state)
        #expect(result.upserts.isEmpty)
        #expect(vault.puts.isEmpty)
        #expect(vault.records["profile"]?.revision == 1)
    }

    @Test("deleting a weight entry deletes its record, and the deletion reaches other devices")
    func deletionTravels() async throws {
        let first = await sync.run(local: [weight("2026-11-06", 70)], state: fresh())
        var state = fresh().merging(first, applied: [], localUpdatedAt: ["weight-2026-11-06": 100])
        state.markDeleted("weight-2026-11-06")

        let result = await sync.run(local: [], state: state)
        #expect(vault.deletes == ["weight-2026-11-06"])
        #expect(result.deletionsDelivered == ["weight-2026-11-06"])

        let otherDevice = await sync.run(local: [weight("2026-11-06", 70)], state: first.revisions.reduce(into: fresh()) { $0.revisions[$1.key] = $1.value })
        #expect(otherDevice.deletes == ["weight-2026-11-06"])
    }

    @Test("meal and targets syncs ignore each other's records")
    func separatePasses() async throws {
        try put(weight("2026-11-06", 70), revision: 1)
        let meals = await JournalSync(session: session, server: vault).run(local: [], state: fresh())
        #expect(meals.upserts.isEmpty && meals.deletes.isEmpty)

        let mealPayload = MealRecordPayload(
            id: "m1", savedAt: 1, updatedAt: 1, items: [], totals: .init(energyKcal: 0, proteinG: 0, carbohydratesG: 0, fatG: 0))
        vault.store(
            id: "m1", type: "meal", revision: 1,
            ciphertext: try seal("m1", type: "meal", plaintext: try encodeMealRecord(mealPayload), revision: 1))
        let health = await sync.run(local: [], state: fresh())
        #expect(health.upserts.map(\.recordId) == ["weight-2026-11-06"])
    }
}
