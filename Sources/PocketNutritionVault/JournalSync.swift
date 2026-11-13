// SPDX-License-Identifier: MPL-2.0

import Foundation
import PocketNutritionCore

/// Why a sync stopped before it finished. What was done up to that point is still returned.
public enum JournalSyncFailure: Error, Equatable, Sendable {
    /// No connection: try again later, nothing is lost.
    case offline
    /// The account is full. Retrying will not help until something is freed.
    case quotaExceeded
    /// The device key was revoked or the account erased: this phone is no longer linked.
    case unauthorized
    case server
}

/// A payload that syncs as vault records: one record per value, sealed under the user key.
///
/// Meals (`meal`) and the daily-targets data (`profile`, `targets`, `weight`) share the same sync rules:
/// last writer wins on `updatedAt`, a deletion wins over an untouched copy but not over a local edit, and a
/// record this version cannot read is never overwritten.
public protocol VaultSyncPayload: Equatable, Sendable {
    /// The record types this payload is read from; other records in the feed are skipped.
    static var recordTypes: Set<String> { get }
    var recordId: String { get }
    var recordType: String { get }
    var updatedAt: Double { get }
    func encodedRecord() throws -> Data
    /// Nil when the plaintext cannot be trusted: malformed, from a newer format, or naming another record.
    static func decodeRecord(_ plaintext: Data, type: String, expectedId: String) -> Self?
}

extension MealRecordPayload: VaultSyncPayload {
    public static var recordTypes: Set<String> { ["meal"] }
    public var recordId: String { id }
    public var recordType: String { "meal" }
    public func encodedRecord() throws -> Data { try encodeMealRecord(self) }
    public static func decodeRecord(_ plaintext: Data, type: String, expectedId: String) -> MealRecordPayload? {
        try? decodeMealRecord(plaintext, expectedId: expectedId)
    }
}

extension TargetsVaultRecord: VaultSyncPayload {
    public static var recordTypes: Set<String> { types }
    public func encodedRecord() throws -> Data { try encodeTargetsRecord(self) }
    public static func decodeRecord(_ plaintext: Data, type: String, expectedId: String) -> TargetsVaultRecord? {
        try? decodeTargetsRecord(plaintext, type: type, expectedId: expectedId)
    }
}

/// The meal journal's sync.
public typealias JournalSync = VaultRecordSync<MealRecordPayload>
public typealias JournalSyncResult = VaultRecordSyncResult<MealRecordPayload>
/// The profile, targets and weight records' sync, with its own cursor and state.
public typealias TargetsSync = VaultRecordSync<TargetsVaultRecord>
public typealias TargetsSyncResult = VaultRecordSyncResult<TargetsVaultRecord>

/// What one sync pass changed, as a delta the caller applies to its own, possibly newer, state.
///
/// A delta rather than a new state because the person keeps using the app while the network calls run: a
/// meal edited meanwhile must stay marked as changed, not be cleared by a sync that uploaded its old version.
public struct VaultRecordSyncResult<Payload: VaultSyncPayload>: Equatable, Sendable {
    public var cursor: Int
    /// Revisions the server now holds, to merge into the state.
    public var revisions: [String: Int] = [:]
    /// Meal id to the `updatedAt` that was uploaded. Clear its dirty flag only if the meal is unchanged since.
    public var pushed: [String: Double] = [:]
    /// Deleted here and now deleted on the server too.
    public var deletionsDelivered: Set<String> = []
    /// Values to write locally: new from another device, or a newer version than the local one.
    public var upserts: [Payload] = []
    /// Meals deleted from another device, to remove locally.
    public var deletes: Set<String> = []
    public var failure: JournalSyncFailure?
}

/// Two-way sync of local values with the vault: one record per value, sealed under the user key. Used for the
/// meal journal (`JournalSync`) and for the daily-targets records (`TargetsSync`).
///
/// Conflicts are settled here, on the phone, because the server cannot read the records: the version
/// with the later `updatedAt` wins, and a deletion wins over an untouched copy but not over a local edit.
/// A record this version cannot read (written by a newer app) is left exactly as it is.
public struct VaultRecordSync<Payload: VaultSyncPayload>: Sendable {

    /// Pull-push rounds per run: a lost write race is retried after pulling, but not forever.
    static var maxRounds: Int { 3 }

    private let session: VaultStoredSession
    private let server: any VaultServing
    private let crypto: VaultCrypto

    public init(session: VaultStoredSession, server: any VaultServing, crypto: VaultCrypto = VaultCrypto()) {
        self.session = session
        self.server = server
        self.crypto = crypto
    }

    /// `local` is the journal as it is now. `state` must belong to this session's account.
    public func run(local: [Payload], state: JournalSyncState) async -> VaultRecordSyncResult<Payload> {
        var run = Run(local: Dictionary(local.map { ($0.recordId, $0) }, uniquingKeysWith: { _, last in last }), state: state)
        do {
            for _ in 0..<Self.maxRounds {
                try await pull(&run)
                if try await push(&run) { break }  // false means a write lost a race: pull again
            }
        } catch {
            run.result.failure = Self.classify(error)
        }
        return run.result
    }

    // MARK: - Pull

    /// Working copy of the world while a run goes: what is on the phone, and what the server is known to hold.
    private struct Run {
        var local: [String: Payload]
        var dirty: Set<String>
        var deleted: Set<String>
        var revisions: [String: Int]
        /// Records this version cannot read: never overwritten.
        var unreadable: Set<String> = []
        var cursor: Int
        var result: VaultRecordSyncResult<Payload>

        init(local: [String: Payload], state: JournalSyncState) {
            self.local = local
            dirty = state.dirty
            deleted = state.deleted
            revisions = state.revisions
            cursor = state.cursor
            result = VaultRecordSyncResult(cursor: state.cursor)
        }
    }

    private func pull(_ run: inout Run) async throws {
        while true {
            let page = try await server.sync(apiKey: session.apiKey, since: run.cursor)
            for record in page.records where Payload.recordTypes.contains(record.type) { absorb(record, into: &run) }
            let before = run.cursor
            run.cursor = max(run.cursor, page.cursor)
            run.result.cursor = run.cursor
            guard page.hasMore, run.cursor > before else { return }
        }
    }

    private func absorb(_ record: VaultRecord, into run: inout Run) {
        run.revisions[record.id] = record.revision
        run.result.revisions[record.id] = record.revision
        let id = record.id

        if record.deleted {
            // A deletion elsewhere removes an untouched copy; a copy edited here since is kept and goes back up.
            if run.dirty.contains(id), run.local[id] != nil { return }
            run.local[id] = nil
            if run.deleted.remove(id) != nil { run.result.deletionsDelivered.insert(id) }
            run.result.upserts.removeAll { $0.recordId == id }
            run.result.deletes.insert(id)
            return
        }

        guard let remote = open(record) else {
            run.unreadable.insert(id)
            return
        }
        // Deleted here, and the server has not heard yet: the deletion is about to be sent.
        if run.deleted.contains(id) { return }
        if let mine = run.local[id], mine.updatedAt >= remote.updatedAt { return }

        run.local[id] = remote
        run.dirty.remove(id)
        run.result.deletes.remove(id)
        run.result.upserts.removeAll { $0.recordId == id }
        run.result.upserts.append(remote)
    }

    /// The value inside a record, or nil if it cannot be trusted: not under the user key, does not open with
    /// it for exactly these fields, from a newer format, or naming another record.
    private func open(_ record: VaultRecord) -> Payload? {
        guard record.keyId == VaultProtocol.userKeyId else { return nil }
        let aad = vaultRecordAAD(
            accountId: session.accountId, recordId: record.id, type: record.type, scopeId: record.scopeId,
            revision: record.revision, keyId: record.keyId)
        guard let plaintext = try? crypto.decrypt(record.ciphertext, key: session.userKey, aad: aad) else { return nil }
        return Payload.decodeRecord(plaintext, type: record.type, expectedId: record.id)
    }

    // MARK: - Push

    /// Sends what is new here. Returns false when a write lost a race and the caller should pull and retry.
    private func push(_ run: inout Run) async throws -> Bool {
        var retry = false

        for id in run.local.keys.sorted() {
            guard let meal = run.local[id], !run.unreadable.contains(id) else { continue }
            guard run.dirty.contains(id) || run.revisions[id] == nil else { continue }
            let revision = (run.revisions[id] ?? 0) + 1
            do {
                try await server.putRecord(apiKey: session.apiKey, id: id, try write(meal, revision: revision))
                run.revisions[id] = revision
                run.result.revisions[id] = revision
                run.result.pushed[id] = meal.updatedAt
                run.dirty.remove(id)
            } catch VaultError.outcome(.revisionConflict) {
                retry = true
            }
        }

        for id in run.deleted.sorted() {
            guard let known = run.revisions[id] else {
                run.result.deletionsDelivered.insert(id)
                run.deleted.remove(id)
                continue
            }
            do {
                try await server.deleteRecord(apiKey: session.apiKey, id: id, revision: known + 1)
                run.revisions[id] = known + 1
                run.result.revisions[id] = known + 1
            } catch VaultError.outcome(.revisionConflict) {
                retry = true
                continue
            } catch VaultError.outcome(.other(404)) {
                // Already gone on the server.
            }
            run.result.deletionsDelivered.insert(id)
            run.deleted.remove(id)
        }
        return !retry
    }

    private func write(_ meal: Payload, revision: Int) throws -> VaultRecordWrite {
        let plaintext = try meal.encodedRecord()
        let aad = vaultRecordAAD(
            accountId: session.accountId, recordId: meal.recordId, type: meal.recordType, scopeId: nil,
            revision: revision, keyId: VaultProtocol.userKeyId)
        return VaultRecordWrite(
            type: meal.recordType, scopeId: nil, revision: revision, keyId: VaultProtocol.userKeyId,
            ciphertext: try crypto.encrypt(plaintext, key: session.userKey, aad: aad))
    }

    private static func classify(_ error: Error) -> JournalSyncFailure {
        switch error {
        case VaultError.offline: return .offline
        case VaultError.outcome(.unauthorized): return .unauthorized
        case VaultError.outcome(.quotaExceeded): return .quotaExceeded
        default: return .server
        }
    }
}

// MARK: - Applying a result

extension VaultRecordSyncResult {

    /// The downloaded values that may still be written: not those the person edited after the sync took
    /// its snapshot (`localUpdatedAt` is the local state as it is now, record id to last edit).
    public func applicableUpserts(localUpdatedAt: [String: Double]) -> [Payload] {
        upserts.filter { (localUpdatedAt[$0.recordId] ?? 0) <= $0.updatedAt }
    }
}

extension JournalSyncState {

    /// This state with a sync result folded in. `self` is the CURRENT state, which may have moved on while
    /// the network calls ran: a meal edited meanwhile (`localUpdatedAt` differs from what was uploaded) stays
    /// marked as changed, so the edit goes up on the next pass instead of being lost.
    public func merging<Payload>(
        _ result: VaultRecordSyncResult<Payload>, applied: [Payload], localUpdatedAt: [String: Double]
    ) -> JournalSyncState {
        var next = self
        next.cursor = max(cursor, result.cursor)
        next.revisions.merge(result.revisions) { _, new in new }
        for (id, uploadedAt) in result.pushed where localUpdatedAt[id] == uploadedAt { next.dirty.remove(id) }
        for meal in applied { next.dirty.remove(meal.recordId) }
        for id in result.deletes { next.dirty.remove(id) }
        next.deleted.subtract(result.deletionsDelivered)
        return next
    }
}
