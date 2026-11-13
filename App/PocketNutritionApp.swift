// SPDX-License-Identifier: MPL-2.0

import PocketNutritionVault
import SwiftUI

@main
struct PocketNutritionApp: App {

    /// Created once for the process lifetime and handed to the view tree. The store reads its file in
    /// `init`, so making it a `@State` here rather than constructing it per-view keeps that to a
    /// single read at launch.
    @State private var journal: JournalStore
    @State private var shortcuts = MealShortcutsStore()
    @State private var journalSync: JournalSyncCoordinator
    @State private var sessionGuard: VaultSessionGuard
    @Environment(\.scenePhase) private var scenePhase
    @State private var recognitionStore: RecognitionEntryStore
    @State private var recognition: RecognitionCoordinator
    @State private var targets: TargetsStore
    @State private var reference = ReferenceIntakesStore()
    @State private var targetsSync: TargetsSyncCoordinator
    @AppStorage(TargetsFeature.defaultsKey) private var isTargetsEnabled = TargetsFeature.defaultEnabled

    init() {
        let journal = JournalStore()
        _journal = State(initialValue: journal)
        let journalSync = JournalSyncCoordinator(journal: journal)
        _journalSync = State(initialValue: journalSync)
        _sessionGuard = State(initialValue: VaultSessionGuard(journalSync: journalSync))
        let targets = TargetsStore()
        _targets = State(initialValue: targets)
        _targetsSync = State(initialValue: TargetsSyncCoordinator(store: targets))
        let store = RecognitionEntryStore()
        _recognitionStore = State(initialValue: store)
        _recognition = State(
            initialValue: RecognitionCoordinator(
                store: store,
                // No vault account, no client: nothing is sent, and recordings wait on the phone.
                makeClient: {
                    guard VaultInbox.live() != nil else { return nil }
                    return RecognitionClient(configuration: RecognitionSettings.configuration())
                },
                makeVault: { VaultInbox.live() },
                requiresVault: true
            ))
    }

    var body: some Scene {
        WindowGroup {
            JournalView()
                .environment(journal)
                .environment(shortcuts)
                .environment(recognitionStore)
                .environment(recognition)
                .environment(journalSync)
                .environment(sessionGuard)
                .environment(targets)
                .environment(reference)
                .task { await journalSync.syncNow() }
                .task(id: isTargetsEnabled) {
                    // Nothing of the feature is fetched or synced while its preview switch is off.
                    guard isTargetsEnabled else { return }
                    await reference.refreshIfStale()
                    await targetsSync.syncNow()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        // Expire the vault session first, so a timeout logout never races a sync.
                        Task {
                            await sessionGuard.appDidBecomeActive()
                            journalSync.syncSoon(after: .zero)
                            if isTargetsEnabled {
                                targetsSync.syncSoon(after: .zero)
                                await reference.refreshIfStale()
                            }
                        }
                        // Dictations are followed for as long as the app is in front, not only while a
                        // screen about them is open: a result can arrive while the person is elsewhere.
                        recognition.start()
                    case .background:
                        recognition.stop()
                        sessionGuard.appDidEnterBackground()
                    default:
                        break
                    }
                }
                // PnColor is a fixed light palette with no dark variants (matches Android's
                // light-only theme). Without pinning this, system Dark Mode flips automatic
                // colors (nav title, text field text, status bar) to white while our custom
                // backgrounds stay light, making titles unreadable.
                .preferredColorScheme(.light)
        }
    }
}
