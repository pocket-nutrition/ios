// SPDX-License-Identifier: MPL-2.0

import Foundation
import Network
import Observation
import PocketNutritionCore
import PocketNutritionVault

/// Drives every entry towards a result: uploads what is waiting, then follows what is processing with
/// a plain GET followed by a long poll (`wait=20`, `known_status` = last status).
///
/// One loop per entry, cancelled by `stop()` — cancellation is not an error and changes no entry.
/// Failures keep the entry and back off (3 s, doubling, cap 30 s). A 401 is never retried in a loop.
/// `NWPathMonitor` (Network framework, no permission) triggers an immediate retry when the network
/// comes back.
///
/// TICKET HYGIENE: an entry never ends up with two server tickets. Only one upload per entry runs at a
/// time, and any ticket a finished upload produced that the entry did not adopt (it was deleted, or
/// another upload won) is deleted from the server, best effort.
@MainActor
@Observable
final class RecognitionCoordinator {

    /// The last network attempt failed for connectivity reasons.
    private(set) var isOffline = false
    /// The server rejected the API key (401) and the user has not yet tried again.
    private(set) var isUnauthorized = false

    private struct Loop {
        let token: UUID
        let task: Task<Void, Never>
    }

    private let store: RecognitionEntryStore
    private let makeClient: () -> RecognitionClient?
    /// The phone's vault access, when it is linked to one. Nil means results come back through the ticket.
    private let makeVault: () -> VaultInbox?
    /// When true a recording is never sent without a vault drop: the result would otherwise go through
    /// the recognition server in the clear. The upload waits instead, like any other not-yet-possible one.
    private let requiresVault: Bool
    /// A drop minted for an entry whose upload has not gone through yet, reused by the retries: minting a
    /// new one on every attempt would fill the vault's cap on pending drops while offline.
    private var drops: [String: VaultDropGrant] = [:]
    /// How many times the vault had no record for a delivered capture. Bounded, so a delivery that never
    /// shows up ends as a failure the user can retry instead of waiting forever.
    private var missingInVault: [String: Int] = [:]
    private var loops: [String: Loop] = [:]
    private var uploadsInFlight: Set<String> = []
    /// Entries whose loop must end as soon as their in-flight upload finishes. An upload is never
    /// cancelled mid-flight: the ticket it creates would lose its id and the retry would duplicate it.
    private var stopWhenIdle: [String: UUID] = [:]
    private var monitor: NWPathMonitor?

    init(
        store: RecognitionEntryStore, makeClient: @escaping () -> RecognitionClient?,
        makeVault: @escaping () -> VaultInbox? = { nil }, requiresVault: Bool = false
    ) {
        self.requiresVault = requiresVault
        self.store = store
        self.makeClient = makeClient
        self.makeVault = makeVault
    }

    // MARK: - Lifecycle

    /// Screen opened or app foregrounded: restart everything, sending any waiting recording once even
    /// after a 401 (the user may have fixed the key), and re-reading every processing entry.
    func start() {
        stopLoops()
        isUnauthorized = false
        stopWhenIdle = [:]
        store.recover()
        store.purgeNow()
        startPathMonitor()
        for entry in store.entries { launch(entry.localId, firstTrigger: .screenOpen) }
    }

    func stop() {
        stopLoops()
        monitor?.cancel()
        monitor = nil
    }

    /// Cancels every loop except those in the middle of an upload, which finish that one request first.
    private func stopLoops() {
        for (localId, loop) in loops {
            if uploadsInFlight.contains(localId) {
                stopWhenIdle[localId] = loop.token
            } else {
                loop.task.cancel()
                loops[localId] = nil
            }
        }
    }

    /// One plain GET per processing entry, no loops — for the Journal screen, which only needs the
    /// badge to be current. Waiting uploads are left to the capture screen.
    func refreshProcessingOnce() {
        guard let client = makeClient() else { return }
        for entry in store.entries where entry.state == .processing {
            let localId = entry.localId
            Task { [weak self] in await self?.pollOnce(localId, client: client, wait: nil) }
        }
    }

    /// The user pressed "send now" / "send again".
    ///
    /// Idempotent: while that entry's upload is already in flight a second press does nothing, and it
    /// can never cancel an upload that is under way.
    func sendNow(_ localId: String) {
        guard !uploadsInFlight.contains(localId) else { return }
        // The tap must not be lost to a store that merely needs a nudge.
        store.recover()
        isUnauthorized = false
        loops[localId]?.task.cancel()
        loops[localId] = nil
        launch(localId, firstTrigger: .manual)
    }

    /// An entry just created by a recording: send straight away.
    func track(_ localId: String) {
        launch(localId, firstTrigger: .screenOpen)
    }

    /// Removes the entry and its audio, then asks the server to forget the ticket (best effort). The
    /// server is only asked once the removal is saved, so a failed removal never deletes a ticket whose
    /// entry is still on the phone. An upload still in flight cleans up after itself (see `upload`).
    func delete(_ localId: String) {
        drops[localId] = nil
        missingInVault[localId] = nil
        let removed = store.entry(localId)
        let ticketId = removed?.ticketId
        let ticketSecret = removed?.ticketSecret
        // An upload under way is left to finish: its answer carries the ticket id, which is what lets
        // it be deleted server-side. The loop then finds the entry gone and ends.
        if !uploadsInFlight.contains(localId) {
            loops[localId]?.task.cancel()
            loops[localId] = nil
        }
        guard store.remove(localId) else {
            // Not removed (could not be saved): the entry is still here, so keep it moving.
            launch(localId, firstTrigger: .screenOpen)
            return
        }
        if let ticketId, let client = makeClient() { discardTicket(ticketId, secret: ticketSecret, using: client) }
    }

    // MARK: - Loop

    private func launch(_ localId: String, firstTrigger: UploadTrigger) {
        guard loops[localId] == nil, let client = makeClient(),
              let entry = store.entry(localId),
              entry.state == .pendingUpload || entry.state == .processing || firstTrigger == .manual
        else { return }
        let token = UUID()
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.run(localId, client: client, firstTrigger: firstTrigger, token: token)
        }
        loops[localId] = Loop(token: token, task: task)
    }

    private func run(_ localId: String, client: RecognitionClient, firstTrigger: UploadTrigger, token: UUID) async {
        defer { finish(localId, token: token) }
        var trigger = firstTrigger
        var isFirstPoll = true
        var failures = 0
        while !Task.isCancelled {
            guard let entry = store.entry(localId) else { return }
            // Another request for this entry is still going: wait for it WITHOUT consuming the trigger.
            if uploadsInFlight.contains(localId) {
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            var succeeded: Bool
            if entry.isEligibleForUpload(trigger: trigger) {
                let outcome = await upload(entry, client: client)
                if stopWhenIdle[localId] == token { stopWhenIdle[localId] = nil; return }
                switch outcome {
                case .skipped:
                    // Nothing was sent, so the trigger is NOT consumed (a manual Retry stays manual).
                    store.recover()
                    failures += 1
                    try? await Task.sleep(for: .seconds(recognitionBackoffSeconds(consecutiveFailures: failures)))
                    continue
                case .succeeded: succeeded = true
                case .failed: succeeded = false
                }
                // A Retry the user asked for on an ended entry keeps being retried with back-off if it
                // fails for a passing reason (offline, 5xx), rather than ending the loop silently. A
                // rejection (401, 413/415) or a lost file still ends it, since retrying cannot help.
                trigger = store.entry(localId)?.state == .needsRetry ? .manual : .backoff
            } else if entry.state == .processing {
                let wait = isFirstPoll ? nil : recognitionLongPollSeconds
                let started = ContinuousClock.now
                succeeded = await pollOnce(localId, client: client, wait: wait)
                isFirstPoll = false
                if succeeded, !Task.isCancelled {
                    // A poll that came back early with nothing new must not become a tight loop.
                    let after = store.entry(localId)
                    let elapsed = (ContinuousClock.now - started) / .seconds(1)
                    let delay = recognitionPollDelaySeconds(
                        elapsed: elapsed, wait: wait ?? 0,
                        statusChanged: after?.lastStatus != entry.lastStatus || after?.state != entry.state
                    )
                    if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                }
            } else {
                return
            }
            if Task.isCancelled { return }
            if succeeded {
                failures = 0
            } else {
                // A 401 is never retried in a loop; and a rejected upload (413/415) leaves the entry in
                // a state the loop will not touch.
                if isUnauthorized { return }
                guard let current = store.entry(localId) else { return }
                let canContinue = current.state == .processing || current.isEligibleForUpload(trigger: trigger)
                guard canContinue else { return }
                failures += 1
                // Whatever is stuck (a failed write, a blocked load) is retried along with the network.
                store.recover()
                try? await Task.sleep(for: .seconds(recognitionBackoffSeconds(consecutiveFailures: failures)))
            }
        }
    }

    private enum UploadOutcome { case succeeded, failed, skipped }

    /// `.skipped` means nothing was attempted (entries cannot be saved right now): the caller keeps its
    /// trigger and waits, so a user's tap is never consumed by a non-attempt.
    private func upload(_ entry: RecognitionEntry, client: RecognitionClient) async -> UploadOutcome {
        let localId = entry.localId
        // Never a second ticket for an entry that has one (a retry from `needsRetry` is the exception:
        // it replaces an ended ticket, and the user asked for it).
        guard entry.state == .needsRetry || entry.ticketId == nil,
              !uploadsInFlight.contains(localId),
              let url = store.audioURL(of: entry) else { return .failed }
        // A ticket that could not be recorded locally would be created and discarded on every retry,
        // so nothing is sent while the entries cannot be saved.
        guard store.canPersist else { return .skipped }
        let replacedTicketId = entry.state == .needsRetry ? entry.ticketId : nil
        let replacedSecret = entry.state == .needsRetry ? entry.ticketSecret : nil
        uploadsInFlight.insert(localId)
        defer { uploadsInFlight.remove(localId) }
        do {
            // With a vault, the worker needs a write-only drop to put the sealed result in. If it cannot
            // be minted nothing is sent: sending anyway would hand the result to the recognition server.
            var grant = drops[localId]
            if grant == nil {
                if let inbox = makeVault() {
                    grant = try await inbox.prepareDrop()
                    drops[localId] = grant
                } else if requiresVault {
                    return .skipped
                }
            }
            let ticket = try await client.upload(audioFileURL: url, vault: grant)
            isOffline = false
            let adopted = store.apply(
                .uploadSucceeded(ticket, now: Date().timeIntervalSince1970, vaultRecordId: grant?.recordId),
                to: localId) && store.entry(localId)?.ticketId == ticket.id
            if adopted { drops[localId] = nil }
            // Not adopted — the entry was deleted meanwhile (even when this task was cancelled) or the
            // state could not be saved: the audio now sits on the server for nothing, so remove it.
            if store.entry(localId)?.ticketId != ticket.id {
                discardTicket(ticket.id, secret: ticket.secret, using: client)
            } else if let replacedTicketId {
                // The retry replaced an ended ticket: forget the old one on the server too.
                discardTicket(replacedTicketId, secret: replacedSecret, using: client)
            }
            return adopted ? .succeeded : .failed
        } catch is CancellationError {
            return .failed
        } catch RecognitionError.unreadableAudio {
            store.apply(.audioLost, to: localId)
            return .failed
        } catch RecognitionError.audioReadFailed {
            store.apply(.uploadFailed(.transient, message: nil), to: localId)
            return .failed
        } catch RecognitionError.malformedUpload {
            store.apply(.uploadFailed(.malformedResponse, message: nil), to: localId)
            return .failed
        } catch let error as RecognitionError {
            // A drop token the server refuses is not the person's mistake: the token was already used
            // (409) or no longer valid (401 on a server with no shared key). Mint a new one and try again.
            let dropRefused = error.outcome == .conflict || (error.outcome == .unauthorized && !client.usesSharedKey)
            if dropRefused { drops[localId] = nil }
            let failure = dropRefused ? UploadFailure.transient : classifyUploadFailure(error.outcome)
            isOffline = failure == .offline
            if failure == .unauthorized { isUnauthorized = true }
            var message: String?
            if case .http(_, let text) = error { message = text }
            store.apply(.uploadFailed(failure, message: message), to: localId)
            return .failed
        } catch {
            store.apply(.uploadFailed(.transient, message: nil), to: localId)
            return .failed
        }
    }

    @discardableResult
    private func pollOnce(_ localId: String, client: RecognitionClient, wait: Int?) async -> Bool {
        guard let entry = store.entry(localId), entry.state == .processing, let ticketId = entry.ticketId
        else { return false }
        do {
            let fetched = try await client.fetch(
                id: ticketId, secret: entry.ticketSecret, wait: wait,
                knownStatus: wait == nil ? nil : entry.lastStatus?.rawValue
            )
            isOffline = false
            switch fetched {
            case .ticket(var ticket):
                if isDeliveredToVault(ticket) {
                    switch await collectFromVault(entry) {
                    case .result(let result): ticket = ticket.withResult(result)
                    case .retryLater: return false
                    case .unreadable: break  // no result: the entry ends as a failure it can retry
                    }
                }
                let saved = store.apply(.polled(ticket, now: Date().timeIntervalSince1970), to: localId)
                // The server's copy goes only once the result is safely on disk.
                if saved, store.entry(localId)?.state == .ready {
                    discardTicket(ticketId, secret: entry.ticketSecret, using: client)
                }
                return saved
            case .gone: return store.apply(.ticketGone, to: localId)
            case .expired: return store.apply(.ticketExpired, to: localId)
            }
        } catch is CancellationError {
            return false
        } catch let error as RecognitionError {
            if error.outcome == .unauthorized { isUnauthorized = true } else { isOffline = error.outcome == nil }
            return false
        } catch {
            return false
        }
    }

    private enum VaultCollection { case result(RecognitionResult), retryLater, unreadable }

    /// Fetches a delivered capture's result from the vault. Anything that may pass (offline, a record that
    /// has not appeared yet) is `retryLater`, up to a bound; a record that cannot be used is `unreadable`.
    private func collectFromVault(_ entry: RecognitionEntry) async -> VaultCollection {
        guard let recordId = entry.vaultRecordId, let inbox = makeVault() else { return .unreadable }
        do {
            switch try await inbox.collect(recordId: recordId) {
            case .result(let result):
                missingInVault[entry.localId] = nil
                return .result(result)
            case .unreadable:
                return .unreadable
            case .notThere:
                let misses = (missingInVault[entry.localId] ?? 0) + 1
                missingInVault[entry.localId] = misses
                return misses >= 8 ? .unreadable : .retryLater
            }
        } catch {
            isOffline = (error as? VaultError) == .offline
            return .retryLater
        }
    }

    /// Best-effort `DELETE` that survives the cancellation of the task that asked for it.
    private func discardTicket(_ id: String, secret: String?, using client: RecognitionClient) {
        Task { try? await client.delete(id: id, secret: secret) }
    }

    private func finish(_ localId: String, token: UUID) {
        guard loops[localId]?.token == token else { return }
        loops[localId] = nil
    }

    // MARK: - Network path

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.networkBecameAvailable() }
        }
        monitor.start(queue: DispatchQueue(label: "org.pocketnutrition.recognition.path"))
        self.monitor = monitor
    }

    /// An immediate retry instead of waiting out the back-off: a loop that is asleep is restarted.
    private func networkBecameAvailable() {
        // `monitor` is nil after `stop()`: a path update already on its way must not restart anything.
        guard monitor != nil, isOffline else { return }
        for entry in store.entries where entry.state == .pendingUpload || entry.state == .processing {
            // Never interrupt an upload under way (its ticket would be duplicated).
            guard !uploadsInFlight.contains(entry.localId) else { continue }
            loops[entry.localId]?.task.cancel()
            loops[entry.localId] = nil
            launch(entry.localId, firstTrigger: .backoff)
        }
    }
}
