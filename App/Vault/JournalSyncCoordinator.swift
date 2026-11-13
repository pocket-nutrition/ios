// SPDX-License-Identifier: MPL-2.0

import Foundation
import Observation
import PocketNutritionCore
import PocketNutritionVault

/// Where the sync bookkeeping lives: one small file next to the journal. Not a secret (meal ids and
/// revision numbers), and not in `UserDefaults` because it grows with the journal.
struct JournalSyncStateStore: Sendable {

    let fileURL: URL

    static var standard: JournalSyncStateStore {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return JournalSyncStateStore(fileURL: directory.appendingPathComponent("journal.sync.json"))
    }

    func load() -> JournalSyncState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(JournalSyncState.self, from: data)
    }

    func save(_ state: JournalSyncState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() { try? FileManager.default.removeItem(at: fileURL) }
}

/// Keeps the journal and the linked vault account in step: uploads what is new or edited here, brings
/// down what changed elsewhere, and settles conflicts (see `JournalSync`).
///
/// Nothing here needs the person to act. With a linked account the whole journal goes up the first time,
/// whatever was on the phone before the account existed; without one the coordinator does nothing and the
/// journal stays local. A failed sync is simply tried again at the next change or the next time the app
/// comes to the front.
@MainActor
@Observable
final class JournalSyncCoordinator {

    enum Status: Equatable {
        /// No linked account: the journal is only on this phone.
        case off
        case idle
        case syncing
        case offline
        case full
        case failed
    }

    private(set) var status: Status = .off
    private(set) var lastSyncedAt: Date?

    @ObservationIgnored private let journal: JournalStore
    @ObservationIgnored private let stateStore: JournalSyncStateStore
    @ObservationIgnored private let loadSession: () -> VaultStoredSession?
    @ObservationIgnored private let makeServer: @Sendable (URL) -> any VaultServing

    @ObservationIgnored private var state: JournalSyncState?
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var runAgain = false
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(
        journal: JournalStore,
        stateStore: JournalSyncStateStore = .standard,
        loadSession: @escaping () -> VaultStoredSession? = {
            VaultSessionStore(secrets: KeychainSecretStore.vaultSession).load()
        },
        makeServer: @escaping @Sendable (URL) -> any VaultServing = { VaultClient(baseURL: $0) }
    ) {
        self.journal = journal
        self.stateStore = stateStore
        self.loadSession = loadSession
        self.makeServer = makeServer
        state = stateStore.load()
        journal.onChange = { [weak self] change in self?.noteChange(change) }
    }

    // MARK: - Triggers

    /// After a change, a short pause first: editing a meal triggers several saves in a row.
    func syncSoon(after delay: Duration = .seconds(2)) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// This phone is no longer linked (logged out, or the account was erased): forget the bookkeeping, keep
    /// every meal. A later account, or the same one again, starts from a full upload.
    func unlinked() {
        pending?.cancel()
        state = nil
        stateStore.clear()
        status = .off
    }

    func syncNow() async {
        guard !isRunning else {
            runAgain = true
            return
        }
        guard let session = loadSession() else {
            if state != nil { unlinked() }
            status = .off
            return
        }
        isRunning = true
        status = .syncing
        defer { isRunning = false }
        repeat {
            runAgain = false
            await runOnce(session)
        } while runAgain
    }

    // MARK: - One pass

    private func noteChange(_ change: JournalChange) {
        guard let session = loadSession() else { return }
        var current = boundState(to: session)
        switch change {
        case .saved(let id): current.markChanged(id.uuidString.lowercased())
        case .deleted(let id): current.markDeleted(id.uuidString.lowercased())
        }
        store(current)
        syncSoon()
    }

    private func runOnce(_ session: VaultStoredSession) async {
        let snapshot = boundState(to: session)
        if state != snapshot { store(snapshot) }
        let local = journal.meals.map(\.record)
        let result = await JournalSync(session: session, server: makeServer(session.serverURL))
            .run(local: local, state: snapshot)
        merge(result)
        switch result.failure {
        case nil:
            status = .idle
            lastSyncedAt = Date()
        case .offline: status = .offline
        case .quotaExceeded: status = .full
        case .unauthorized, .server: status = .failed
        }
    }

    /// Applies a result to the journal and to the *current* state, which may have moved on while the network
    /// calls ran: a meal edited meanwhile stays marked as changed, and is not overwritten by an older copy.
    private func merge(_ result: JournalSyncResult) {
        guard let current = state else { return }

        let edited = Dictionary(uniqueKeysWithValues: journal.meals.map { ($0.recordId, $0.modifiedAt.timeIntervalSince1970) })
        let applicable = result.applicableUpserts(localUpdatedAt: edited)
        journal.apply(
            upserts: applicable.compactMap { SavedMeal(record: $0) },
            deletes: Set(result.deletes.compactMap { UUID(uuidString: $0) }))
        store(current.merging(result, applied: applicable, localUpdatedAt: edited))
    }

    /// The state for this account: the saved one, or an empty one when none exists or it belongs to
    /// another account (which then gets the whole journal).
    private func boundState(to session: VaultStoredSession) -> JournalSyncState {
        if let state, state.accountId == session.accountId { return state }
        return JournalSyncState(accountId: session.accountId)
    }

    private func store(_ new: JournalSyncState) {
        state = new
        stateStore.save(new)
    }
}
