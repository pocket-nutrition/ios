// SPDX-License-Identifier: MPL-2.0

import Foundation
import Observation
import PocketNutritionCore
import PocketNutritionVault

/// Keeps the profile, targets and weight records in step with the linked vault account, like
/// `JournalSyncCoordinator` does for meals, with its own bookkeeping file and cursor. Without a linked
/// account it does nothing and the data stays on the phone.
@MainActor
final class TargetsSyncCoordinator {

    private let store: TargetsStore
    private let stateStore: JournalSyncStateStore
    private let loadSession: () -> VaultStoredSession?
    private let makeServer: @Sendable (URL) -> any VaultServing

    private var state: JournalSyncState?
    private var isRunning = false
    private var runAgain = false
    private var pending: Task<Void, Never>?

    init(
        store: TargetsStore,
        stateStore: JournalSyncStateStore = TargetsSyncCoordinator.defaultStateStore,
        loadSession: @escaping () -> VaultStoredSession? = {
            VaultSessionStore(secrets: KeychainSecretStore.vaultSession).load()
        },
        makeServer: @escaping @Sendable (URL) -> any VaultServing = { VaultClient(baseURL: $0) }
    ) {
        self.store = store
        self.stateStore = stateStore
        self.loadSession = loadSession
        self.makeServer = makeServer
        state = stateStore.load()
        store.onChange = { [weak self] change in self?.noteChange(change) }
    }

    static var defaultStateStore: JournalSyncStateStore {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return JournalSyncStateStore(fileURL: directory.appendingPathComponent("targets.sync.json"))
    }

    func syncSoon(after delay: Duration = .seconds(2)) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    func syncNow() async {
        guard !isRunning else {
            runAgain = true
            return
        }
        guard let session = loadSession() else {
            if state != nil {
                state = nil
                stateStore.clear()
            }
            return
        }
        isRunning = true
        defer { isRunning = false }
        repeat {
            runAgain = false
            await runOnce(session)
        } while runAgain
    }

    private func noteChange(_ change: TargetsChange) {
        guard let session = loadSession() else { return }
        var current = boundState(to: session)
        switch change {
        case .saved(let id): current.markChanged(id)
        case .deleted(let id): current.markDeleted(id)
        }
        saveState(current)
        syncSoon()
    }

    private func runOnce(_ session: VaultStoredSession) async {
        let snapshot = boundState(to: session)
        if state != snapshot { saveState(snapshot) }
        let result = await TargetsSync(session: session, server: makeServer(session.serverURL))
            .run(local: store.records, state: snapshot)
        guard let current = state else { return }
        let edited = store.localUpdatedAt
        let applicable = result.applicableUpserts(localUpdatedAt: edited)
        store.apply(upserts: applicable, deletes: result.deletes)
        saveState(current.merging(result, applied: applicable, localUpdatedAt: edited))
    }

    private func boundState(to session: VaultStoredSession) -> JournalSyncState {
        if let state, state.accountId == session.accountId { return state }
        return JournalSyncState(accountId: session.accountId)
    }

    private func saveState(_ new: JournalSyncState) {
        state = new
        stateStore.save(new)
    }
}
