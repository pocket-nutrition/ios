// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

import PocketNutritionCore

private let day = 86_400.0
private let now = 10_000_000.0

private func ticket(
    _ id: String = "t1", status: RecognitionStatus = .queued, expiresAt: Double = now + 100,
    result: RecognitionResult? = nil, error: String? = nil
) -> RecognitionTicket {
    RecognitionTicket(
        id: id, status: status, createdAt: now, updatedAt: nil, expiresAt: expiresAt, result: result, error: error
    )
}

/// A fake audio folder: every name modified at `modified` (default: just now).
private func disk(_ names: [String], modified: Double = now) -> [String: Double] {
    Dictionary(uniqueKeysWithValues: names.map { ($0, modified) })
}

private let sampleResult = RecognitionResult(
    transcript: "deux oeufs", language: "fr",
    items: [RecognitionItem(rawText: "deux oeufs", quantity: 2, unit: "piece", cookingMethod: nil, candidates: [])]
)

private func entry(
    state: RecognitionEntryState = .pendingUpload, audio: String? = "a.m4a", createdAt: Double = now,
    ticketId: String? = nil, resultFetchedAt: Double? = nil
) -> RecognitionEntry {
    var e = RecognitionEntry(localId: "L", createdAt: createdAt, audioFile: audio)
    e.state = state
    e.ticketId = ticketId
    e.resultFetchedAt = resultFetchedAt
    return e
}

@Suite("recognition entry state machine")
struct RecognitionEntryTransitionTests {

    @Test("a new entry starts pendingUpload with its audio")
    func newEntry() {
        let e = RecognitionEntry(localId: "L", createdAt: now, audioFile: "a.m4a")
        #expect(e.state == .pendingUpload)
        #expect(e.audioFile == "a.m4a")
        #expect(e.ticketId == nil)
    }

    @Test("upload success stores the ticket and moves to processing")
    func uploadSuccess() {
        let e = entry().applying(.uploadSucceeded(ticket("t9", status: .queued, expiresAt: 777), now: now))
        #expect(e.state == .processing)
        #expect(e.ticketId == "t9")
        #expect(e.serverExpiresAt == 777)
        #expect(e.lastStatus == .queued)
        #expect(e.audioFile == "a.m4a", "audio stays until the result is received")
        #expect(e.lastUploadFailure == nil)
    }

    @Test("offline or transient upload failure stays pendingUpload and keeps the audio")
    func uploadTransient() {
        for failure in [UploadFailure.offline, .transient] {
            let e = entry().applying(.uploadFailed(failure, message: nil))
            #expect(e.state == .pendingUpload)
            #expect(e.audioFile == "a.m4a")
            #expect(e.lastUploadFailure == failure)
        }
    }

    @Test("401 stays pendingUpload and is remembered, not retried in a loop")
    func uploadUnauthorized() {
        let e = entry().applying(.uploadFailed(.unauthorized, message: nil))
        #expect(e.state == .pendingUpload)
        #expect(e.lastUploadFailure == .unauthorized)
        #expect(!e.isEligibleForUpload(trigger: .backoff))
        #expect(e.isEligibleForUpload(trigger: .manual))
        #expect(e.isEligibleForUpload(trigger: .screenOpen))
    }

    @Test("413 and 415 make the entry unrecoverable with the server message")
    func uploadRejected() {
        for failure in [UploadFailure.tooLarge, .unsupportedMedia] {
            let e = entry().applying(.uploadFailed(failure, message: "clip too big"))
            #expect(e.state == .unrecoverable)
            #expect(e.error == "clip too big")
        }
    }

    @Test("polling a non-terminal ticket updates the status and stays processing")
    func pollingProgress() {
        let e = entry(state: .processing, ticketId: "t1")
            .applying(.polled(ticket(status: .transcribing, expiresAt: 5), now: now))
        #expect(e.state == .processing)
        #expect(e.lastStatus == .transcribing)
        #expect(e.serverExpiresAt == 5)
    }

    @Test("an unknown status keeps processing")
    func pollingUnknown() {
        let e = entry(state: .processing, ticketId: "t1")
            .applying(.polled(ticket(status: .unknown("zz")), now: now))
        #expect(e.state == .processing)
    }

    @Test("done copies the result, stamps the time and releases the audio")
    func polledDone() {
        let e = entry(state: .processing, ticketId: "t1")
            .applying(.polled(ticket(status: .done, result: sampleResult), now: now + 5))
        #expect(e.state == .ready)
        #expect(e.result == sampleResult)
        #expect(e.resultFetchedAt == now + 5)
        #expect(e.audioFile == nil)
    }

    @Test("failed with audio present needs a retry, with the server error")
    func polledFailedWithAudio() {
        let e = entry(state: .processing, ticketId: "t1")
            .applying(.polled(ticket(status: .failed, error: "bad audio"), now: now))
        #expect(e.state == .needsRetry)
        #expect(e.error == "bad audio")
        #expect(e.endReason == .failed)
    }

    @Test("404 and 410 with audio present need a retry, distinguished by reason")
    func goneAndExpired() {
        let gone = entry(state: .processing, ticketId: "t1").applying(.ticketGone)
        let expired = entry(state: .processing, ticketId: "t1").applying(.ticketExpired)
        #expect(gone.state == .needsRetry && gone.endReason == .gone)
        #expect(expired.state == .needsRetry && expired.endReason == .expired)
    }

    @Test("the same endings without audio are unrecoverable")
    func withoutAudio() {
        let base = entry(state: .processing, audio: nil, ticketId: "t1")
        #expect(base.applying(.ticketGone).state == .unrecoverable)
        #expect(base.applying(.ticketExpired).state == .unrecoverable)
        #expect(base.applying(.polled(ticket(status: .failed), now: now)).state == .unrecoverable)
    }

    @Test("retry sends the same audio as a NEW ticket on the same entry")
    func retryCreatesNewTicket() {
        let expired = entry(state: .processing, ticketId: "old").applying(.ticketExpired)
        #expect(expired.isEligibleForUpload(trigger: .manual))
        #expect(!expired.isEligibleForUpload(trigger: .backoff))
        #expect(!expired.isEligibleForUpload(trigger: .screenOpen))
        let retried = expired.applying(.uploadSucceeded(ticket("new"), now: now))
        #expect(retried.state == .processing)
        #expect(retried.ticketId == "new")
        #expect(retried.localId == expired.localId)
        #expect(retried.error == nil)
        #expect(retried.endReason == nil)
    }

    @Test("a failed retry upload stays needsRetry")
    func retryUploadFails() {
        let e = entry(state: .needsRetry, ticketId: "old").applying(.uploadFailed(.offline, message: nil))
        #expect(e.state == .needsRetry)
    }

    @Test("losing the audio turns pendingUpload and needsRetry into unrecoverable")
    func audioLost() {
        for state in [RecognitionEntryState.pendingUpload, .needsRetry] {
            let e = entry(state: state).applying(.audioLost)
            #expect(e.state == .unrecoverable)
            #expect(e.audioFile == nil)
        }
        let processing = entry(state: .processing, ticketId: "t").applying(.audioLost)
        #expect(processing.state == .processing)
        #expect(processing.audioFile == nil)
    }

    @Test("ready and unrecoverable ignore every event")
    func terminalStatesAreInert() {
        var ready = entry(state: .ready, audio: nil, ticketId: "t", resultFetchedAt: now)
        ready.result = sampleResult
        var dead = entry(state: .unrecoverable, audio: nil)
        dead.error = "x"
        let events: [RecognitionEntryEvent] = [
            .uploadSucceeded(ticket(), now: now), .uploadFailed(.offline, message: nil),
            .polled(ticket(status: .failed), now: now), .ticketGone, .ticketExpired, .audioLost,
        ]
        for event in events {
            #expect(ready.applying(event) == ready)
            #expect(dead.applying(event) == dead)
        }
    }

    @Test("a ready entry is fully readable with no network: it carries the result itself")
    func readyIsSelfContained() throws {
        let ready = entry(state: .processing, ticketId: "t")
            .applying(.polled(ticket(status: .done, result: sampleResult), now: now))
        let data = try StoredEntries.encode([ready])
        let back = try #require(try StoredEntries.decode(data).first)
        #expect(back.result?.transcript == "deux oeufs")
        #expect(back.result?.items.count == 1)
    }

    @Test("upload eligibility by state and trigger")
    func eligibility() {
        #expect(entry(state: .pendingUpload).isEligibleForUpload(trigger: .backoff))
        #expect(!entry(state: .processing, ticketId: "t").isEligibleForUpload(trigger: .manual))
        #expect(!entry(state: .ready, audio: nil).isEligibleForUpload(trigger: .manual))
        #expect(!entry(state: .unrecoverable, audio: nil).isEligibleForUpload(trigger: .manual))
        #expect(!entry(state: .pendingUpload, audio: nil).isEligibleForUpload(trigger: .manual))
    }

    @Test("upload failure classification: 401 vs offline vs 413 vs 415 vs 5xx")
    func classification() {
        #expect(classifyUploadFailure(.unauthorized) == .unauthorized)
        #expect(classifyUploadFailure(.tooLarge) == .tooLarge)
        #expect(classifyUploadFailure(.unsupportedMedia) == .unsupportedMedia)
        #expect(classifyUploadFailure(.other(503)) == .transient)
        #expect(classifyUploadFailure(.other(500)) == .transient)
        #expect(classifyUploadFailure(.notFound) == .transient)
        #expect(classifyUploadFailure(nil) == .offline)
    }
}

@Suite("recognition review hardening")
struct RecognitionHardeningTests {

    @Test("done without a result keeps the audio and needs a retry — nothing is released")
    func doneWithoutResult() {
        let e = entry(state: .processing, ticketId: "t1").applying(.polled(ticket(status: .done, result: nil), now: now))
        #expect(e.state == .needsRetry)
        #expect(e.audioFile == "a.m4a")
        #expect(e.result == nil)
        #expect(e.endReason == .failed)
        let noAudio = entry(state: .processing, audio: nil, ticketId: "t1")
            .applying(.polled(ticket(status: .done, result: nil), now: now))
        #expect(noAudio.state == .unrecoverable)
    }

    @Test("a 2xx upload with an unreadable body is counted and, after 3, left to the user")
    func malformedUploadCap() {
        var e = entry()
        for attempt in 1...3 {
            e = e.applying(.uploadFailed(.malformedResponse, message: nil))
            #expect(e.state == .pendingUpload)
            #expect(e.malformedUploadCount == attempt)
        }
        #expect(!e.isEligibleForUpload(trigger: .backoff))
        #expect(!e.isEligibleForUpload(trigger: .screenOpen))
        #expect(e.isEligibleForUpload(trigger: .manual))
        let twice = entry().applying(.uploadFailed(.malformedResponse, message: nil))
            .applying(.uploadFailed(.malformedResponse, message: nil))
        #expect(twice.isEligibleForUpload(trigger: .backoff))
        #expect(classifyUploadFailure(.success) == .transient)
    }

    @Test("a successful upload resets the malformed counter")
    func malformedReset() {
        let e = entry().applying(.uploadFailed(.malformedResponse, message: nil))
            .applying(.uploadSucceeded(ticket(), now: now))
        #expect(e.malformedUploadCount == nil)
    }

    @Test("a late second upload cannot replace an existing ticket")
    func noSecondTicket() {
        let processing = entry().applying(.uploadSucceeded(ticket("first"), now: now))
        let again = processing.applying(.uploadSucceeded(ticket("second"), now: now))
        #expect(again.ticketId == "first")
    }

    @Test("poll pacing: at least 2 s between polls that returned early without a change")
    func pollPacing() {
        #expect(recognitionPollDelaySeconds(elapsed: 0.1, wait: 20, statusChanged: false) == 1.9)
        #expect(recognitionPollDelaySeconds(elapsed: 5, wait: 20, statusChanged: false) == 0)
        #expect(recognitionPollDelaySeconds(elapsed: 0.1, wait: 20, statusChanged: true) == 0)
        #expect(recognitionPollDelaySeconds(elapsed: 20, wait: 20, statusChanged: false) == 0)
        #expect(recognitionPollDelaySeconds(elapsed: 0, wait: 0, statusChanged: false) == 0, "a plain read is not a long poll")
    }

    @Test("an entry is discarded after import only when every skip is definitive")
    func discardRule() {
        #expect(canDiscardAfterImport(skips: []))
        #expect(canDiscardAfterImport(skips: [.noCandidate, .unknownIngredient, .notBuildable]))
        #expect(!canDiscardAfterImport(skips: [.unknownIngredient, .lookupFailed]))
        #expect(!canDiscardAfterImport(skips: [.lookupFailed]))
    }

    @Test("changing the server host requires a new key; same host does not")
    func hostChange() {
        #expect(recognitionHostChanged(from: "https://a.example.org/x", to: "https://b.example.org"))
        #expect(!recognitionHostChanged(from: "https://A.example.org", to: "https://a.example.org:8443/y"))
        #expect(!recognitionHostChanged(from: nil, to: "https://a.example.org", hasStoredKey: false))
        #expect(recognitionHostChanged(from: "garbage", to: "https://a.example.org"))
    }

    @Test("ingredient ids used as path segments are validated")
    func safeIds() {
        #expect(isValidIngredientId("oeuf_poule_entier_cuit"))
        #expect(isValidIngredientId("a.b-c_1"))
        #expect(!isValidIngredientId(""))
        #expect(!isValidIngredientId("."))
        #expect(!isValidIngredientId(".."))
        #expect(!isValidIngredientId("a/b"))
        #expect(!isValidIngredientId("a b"))
        #expect(!isValidIngredientId(String(repeating: "a", count: 129)))
        #expect(isValidIngredientId(String(repeating: "a", count: 128)))
    }

    @Test("untrusted ticket data: bad id rejected, strings and lists capped")
    func untrustedTicket() throws {
        let bad = #"{"id":"../x","status":"queued","created_at":1,"expires_at":2}"#
        #expect(throws: (any Error).self) { try JSONDecoder().decode(RecognitionTicket.self, from: Data(bad.utf8)) }
        let tooLong = #"{"id":"\#(String(repeating: "a", count: 65))","status":"queued","created_at":1,"expires_at":2}"#
        #expect(throws: (any Error).self) { try JSONDecoder().decode(RecognitionTicket.self, from: Data(tooLong.utf8)) }

        let candidates = (0..<15).map { #"{"ingredient_id":"c\#($0)"}"# }.joined(separator: ",")
        let items = (0..<60).map { _ in #"{"raw_text":"x","candidates":[\#(candidates)]}"# }.joined(separator: ",")
        let long = String(repeating: "e", count: 500)
        let json = #"{"id":"ok-1","status":"failed","created_at":1,"expires_at":2,"error":"\#(long)","result":{"transcript":"t","items":[\#(items)]}}"#
        let ticket = try JSONDecoder().decode(RecognitionTicket.self, from: Data(json.utf8))
        #expect(ticket.error?.count == 200)
        #expect(ticket.result?.items.count == 50)
        #expect(ticket.result?.items.first?.candidates.count == 10)
    }

    @Test("done with an empty result object is not a result: audio kept, retry offered")
    func emptyResultIsNotReady() throws {
        let json = #"{"id":"t1","status":"done","created_at":1,"expires_at":2,"result":{}}"#
        let t = try JSONDecoder().decode(RecognitionTicket.self, from: Data(json.utf8))
        let e = entry(state: .processing, ticketId: "t1").applying(.polled(t, now: now))
        #expect(e.state == .needsRetry)
        #expect(e.audioFile == "a.m4a")
        #expect(!RecognitionResult(transcript: "", language: nil, items: []).isUsable)
        #expect(RecognitionResult(transcript: "riz", language: nil, items: []).isUsable)
        #expect(sampleResult.isUsable)
    }

    @Test("a missing host record with a key that survived a reinstall counts as a host change")
    func hostChangeAfterReinstall() {
        #expect(recognitionHostChanged(from: nil, to: "https://a.example.org", hasStoredKey: true))
        #expect(!recognitionHostChanged(from: nil, to: "https://a.example.org", hasStoredKey: false))
        #expect(!recognitionHostChanged(from: "https://a.example.org", to: "https://a.example.org/x", hasStoredKey: true))
    }

    @Test("decoding reports dropped entries and keeps their audio names")
    func decodeReport() throws {
        let good = try StoredEntries.encode([entry()])
        var object = try #require(try JSONSerialization.jsonObject(with: good) as? [String: Any])
        var list = try #require(object["entries"] as? [[String: Any]])
        list.append(["localId": 5, "audioFile": "bad.m4a"])
        list.append(["nonsense": true])
        object["entries"] = list
        let data = try JSONSerialization.data(withJSONObject: object)
        let report = try StoredEntries.decodeReport(data)
        #expect(report.entries.count == 1)
        #expect(report.droppedCount == 2)
        #expect(report.droppedAudioFiles == ["bad.m4a"])
        let clean = try StoredEntries.decodeReport(good)
        #expect(clean.droppedCount == 0)
    }

    @Test("one undecodable entry does not discard the others")
    func lenientDecode() throws {
        let good = try StoredEntries.encode([entry()])
        var object = try #require(try JSONSerialization.jsonObject(with: good) as? [String: Any])
        var list = try #require(object["entries"] as? [[String: Any]])
        list.append(["localId": 5])
        object["entries"] = list
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(try StoredEntries.decode(data).count == 1)
    }
}

@Suite("recognition entries persistence and retention")
struct RecognitionRetentionTests {

    @Test("encode then decode round-trips, versioned")
    func roundTrip() throws {
        var full = entry(state: .ready, audio: nil, ticketId: "t", resultFetchedAt: now)
        full.result = sampleResult
        full.lastStatus = .done
        full.lastUploadFailure = .unauthorized
        full.endReason = .gone
        full.error = "e"
        full.serverExpiresAt = 3
        let list = [entry(), full]
        let data = try StoredEntries.encode(list)
        #expect(try StoredEntries.decode(data) == list)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["version"] as? Int == 1)
    }

    @Test("a newer file version is refused, garbage is an error")
    func versions() {
        #expect(throws: StoredEntries.DecodeError.self) {
            try StoredEntries.decode(Data(#"{"version":99,"entries":[]}"#.utf8))
        }
        #expect(throws: (any Error).self) { try StoredEntries.decode(Data("nope".utf8)) }
    }

    @Test("audio older than 7 days is deleted; pending/needsRetry entries then become unrecoverable")
    func oldAudio() {
        let old = now - 7 * day - 1
        let a = entry(state: .pendingUpload, audio: "old.m4a", createdAt: old)
        let b = entry(state: .processing, audio: "p.m4a", createdAt: old, ticketId: "t")
        let c = entry(state: .pendingUpload, audio: "fresh.m4a", createdAt: now - 6 * day)
        let result = StoredEntries.purged(
            [a, b, c].enumerated().map { var e = $1; e.localId = "L\($0)"; return e },
            now: now, audioFilesOnDisk: disk(["old.m4a", "p.m4a", "fresh.m4a"])
        )
        #expect(result.entries.map(\.state) == [.unrecoverable, .processing, .pendingUpload])
        #expect(result.entries.map(\.audioFile) == [nil, nil, "fresh.m4a"])
        #expect(Set(result.audioToDelete) == ["old.m4a", "p.m4a"])
    }

    @Test("exactly 7 days old is kept")
    func boundary() {
        let result = StoredEntries.purged(
            [entry(audio: "a.m4a", createdAt: now - 7 * day)], now: now, audioFilesOnDisk: disk(["a.m4a"])
        )
        #expect(result.entries.first?.audioFile == "a.m4a")
    }

    @Test("ready entries are purged 7 days after resultFetchedAt, not before")
    func readyPurge() {
        var keep = entry(state: .ready, audio: nil, resultFetchedAt: now - 7 * day)
        keep.localId = "keep"
        var drop = entry(state: .ready, audio: nil, resultFetchedAt: now - 7 * day - 1)
        drop.localId = "drop"
        let result = StoredEntries.purged([keep, drop], now: now, audioFilesOnDisk: [:])
        #expect(result.entries.map(\.localId) == ["keep"])
    }

    @Test("orphan audio is deleted only once it is older than 7 days")
    func orphans() {
        var files = disk(["mine.m4a"])
        files["old-orphan.m4a"] = now - 7 * day - 1
        files["young-orphan.m4a"] = now - 6 * day
        files["edge-orphan.m4a"] = now - 7 * day
        let result = StoredEntries.purged([entry(audio: "mine.m4a")], now: now, audioFilesOnDisk: files)
        #expect(result.audioToDelete == ["old-orphan.m4a"])
        #expect(result.entries.count == 1)
    }

    @Test("audio of entries that could not be decoded is protected, never swept as an orphan")
    func protectedAudio() {
        var files = disk([])
        files["dropped.m4a"] = now - 30 * day
        files["real-orphan.m4a"] = now - 30 * day
        let result = StoredEntries.purged([], now: now, audioFilesOnDisk: files, protectedAudio: ["dropped.m4a"])
        #expect(result.audioToDelete == ["real-orphan.m4a"])
    }

    @Test("an entry whose audio file vanished loses it; pendingUpload becomes unrecoverable")
    func missingFile() {
        let result = StoredEntries.purged([entry(audio: "gone.m4a")], now: now, audioFilesOnDisk: [:])
        #expect(result.entries.first?.state == .unrecoverable)
        #expect(result.entries.first?.audioFile == nil)
    }

    @Test("badge counts ready entries and flags attention from local state only")
    func badge() {
        var ready = entry(state: .ready, audio: nil)
        ready.localId = "r1"
        var ready2 = ready
        ready2.localId = "r2"
        let processing = entry(state: .processing, ticketId: "t")
        let retry = entry(state: .needsRetry, ticketId: "t")
        let unauth = entry(state: .pendingUpload).applying(.uploadFailed(.unauthorized, message: nil))
        let offline = entry(state: .pendingUpload).applying(.uploadFailed(.offline, message: nil))

        #expect(recognitionBadge([]) == RecognitionBadge(readyCount: 0, needsAttention: false))
        #expect(recognitionBadge([ready, ready2, processing, offline])
            == RecognitionBadge(readyCount: 2, needsAttention: false))
        #expect(recognitionBadge([retry]).needsAttention)
        #expect(recognitionBadge([unauth]).needsAttention)
        #expect(recognitionBadge([ready, retry]) == RecognitionBadge(readyCount: 1, needsAttention: true))
    }
}
