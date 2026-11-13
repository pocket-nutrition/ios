// SPDX-License-Identifier: MPL-2.0

import Foundation

// The local model behind voice capture. One entry per recording, created BEFORE any network call: the
// phone keeps the recording and the result, and the server is only a relay. Not part of contracts 2.0.0.

public enum RecognitionEntryState: String, Equatable, Sendable, Codable {
    /// Audio saved locally, no ticket yet (offline, upload failed, or the app died mid-upload).
    case pendingUpload
    /// A ticket exists and the server status is non-terminal.
    case processing
    /// The server said done and the result is copied into the entry. Never touches the network again.
    case ready
    /// 410, 404 or failed — and the audio is still on the phone, so it can be sent again.
    case needsRetry
    /// Same endings with no audio left (or a rejected upload). Only deletion is offered.
    case unrecoverable
}

/// Why an entry ended without a result.
public enum RecognitionEndReason: String, Equatable, Sendable, Codable {
    case expired, gone, failed, rejected, audioLost
}

/// How an upload attempt failed, as far as the client's reaction is concerned.
public enum UploadFailure: String, Equatable, Sendable, Codable {
    /// No connectivity or timeout: keep waiting.
    case offline
    /// The server answered with an error that may pass (5xx and the like): keep waiting.
    case transient
    /// 401: do not retry in a loop.
    case unauthorized
    /// 413: retrying cannot help.
    case tooLarge
    /// 415: retrying cannot help.
    case unsupportedMedia
    /// A 2xx whose body carried no usable ticket id. Each retry may create another server ticket, so
    /// the automatic loop gives up after `malformedUploadLimit` of these.
    case malformedResponse
}

/// Automatic upload attempts allowed after unreadable-but-2xx answers.
public let malformedUploadLimit = 3

/// Classifies an upload's HTTP outcome; `nil` means no response at all (offline / timeout).
public func classifyUploadFailure(_ outcome: RecognitionHTTPOutcome?) -> UploadFailure {
    guard let outcome else { return .offline }
    switch outcome {
    case .unauthorized: return .unauthorized
    case .tooLarge: return .tooLarge
    case .unsupportedMedia: return .unsupportedMedia
    case .success, .notFound, .expired, .conflict, .other: return .transient
    }
}

public enum RecognitionEntryEvent: Equatable, Sendable {
    /// `vaultRecordId` is the vault record the worker will deposit the result in, when a drop was minted.
    case uploadSucceeded(RecognitionTicket, now: Double, vaultRecordId: String? = nil)
    case uploadFailed(UploadFailure, message: String?)
    case polled(RecognitionTicket, now: Double)
    case ticketGone
    case ticketExpired
    case audioLost
}

/// What triggered an upload attempt; decides whether this entry may be sent.
public enum UploadTrigger: Equatable, Sendable {
    /// The tracker's automatic back-off loop.
    case backoff
    /// Opening the capture screen or returning to the foreground.
    case screenOpen
    /// The user pressed "send now" / "retry".
    case manual
}

public struct RecognitionEntry: Equatable, Sendable, Codable, Identifiable {
    public var localId: String
    public var createdAt: Double
    /// File name inside the app's private audio folder.
    public var audioFile: String?
    public var ticketId: String?
    public var serverExpiresAt: Double?
    public var state: RecognitionEntryState
    public var lastStatus: RecognitionStatus?
    public var error: String?
    public var endReason: RecognitionEndReason?
    public var lastUploadFailure: UploadFailure?
    public var result: RecognitionResult?
    public var resultFetchedAt: Double?
    public var malformedUploadCount: Int?
    /// The vault record this capture's result is deposited in, when the upload carried a vault drop.
    public var vaultRecordId: String?
    /// Authenticates reads and deletes of this entry's ticket, so no shared key is needed. Nil for tickets made
    /// with the shared key (older entries, self-hosted servers).
    public var ticketSecret: String?
    /// A meal photo rather than a voice clip. Kept on the entry because the file (whose extension says
    /// it) is released once uploaded. Nil in entries written before photos existed: those are voice.
    public var isPhoto: Bool?

    public var id: String { localId }

    public init(localId: String, createdAt: Double, audioFile: String?) {
        self.localId = localId
        self.createdAt = createdAt
        self.audioFile = audioFile
        self.state = .pendingUpload
        if let audioFile, recognitionIsPhoto(fileName: audioFile) { isPhoto = true }
    }

    /// The next state of this entry. Pure; `ready` and `unrecoverable` ignore everything.
    public func applying(_ event: RecognitionEntryEvent) -> RecognitionEntry {
        var next = self
        switch (state, event) {
        case (.ready, _), (.unrecoverable, _):
            return self

        case (.pendingUpload, .uploadSucceeded(let ticket, _, let vaultRecordId)),
             (.needsRetry, .uploadSucceeded(let ticket, _, let vaultRecordId)):
            next.ticketId = ticket.id
            next.vaultRecordId = vaultRecordId
            next.ticketSecret = ticket.secret
            next.serverExpiresAt = ticket.expiresAt
            next.lastStatus = ticket.status
            next.state = .processing
            next.error = nil
            next.endReason = nil
            next.lastUploadFailure = nil
            next.malformedUploadCount = nil

        case (.pendingUpload, .uploadFailed(let failure, let message)),
             (.needsRetry, .uploadFailed(let failure, let message)):
            next.lastUploadFailure = failure
            if failure == .malformedResponse { next.malformedUploadCount = (malformedUploadCount ?? 0) + 1 }
            if failure == .tooLarge || failure == .unsupportedMedia {
                next.state = .unrecoverable
                next.endReason = .rejected
                next.error = message
            }

        case (.processing, .polled(let ticket, let now)):
            next.serverExpiresAt = ticket.expiresAt
            next.lastStatus = ticket.status
            switch ticket.status {
            case .done:
                // "Done" with no result is a server fault, not an empty meal: nothing is released.
                guard let result = ticket.result, result.isUsable else {
                    next = next.ended(.failed, message: nil)
                    break
                }
                next.state = .ready
                next.result = result
                next.resultFetchedAt = now
                // The audio has served its purpose; the caller deletes the file it no longer names.
                next.audioFile = nil
                next.error = nil
            case .failed:
                next = next.ended(.failed, message: ticket.error)
            default:
                break
            }

        case (.processing, .ticketGone): next = next.ended(.gone, message: nil)
        case (.processing, .ticketExpired): next = next.ended(.expired, message: nil)

        case (_, .audioLost):
            next.audioFile = nil
            if state == .pendingUpload || state == .needsRetry {
                next.state = .unrecoverable
                next.endReason = .audioLost
            }

        default:
            return self
        }
        return next
    }

    /// `needsRetry` if the audio is still here, `unrecoverable` if not.
    private func ended(_ reason: RecognitionEndReason, message: String?) -> RecognitionEntry {
        var copy = self
        copy.state = audioFile == nil ? .unrecoverable : .needsRetry
        copy.endReason = reason
        copy.error = message
        return copy
    }

    /// Whether this entry may be (re)sent right now.
    ///
    /// Only a recording with audio can be sent. A `pendingUpload` goes out on any trigger except that
    /// the automatic loop leaves a 401 alone; a `needsRetry` is sent only when the user asks.
    public func isEligibleForUpload(trigger: UploadTrigger) -> Bool {
        guard audioFile != nil else { return false }
        switch state {
        case .pendingUpload:
            if trigger == .backoff && lastUploadFailure == .unauthorized { return false }
            if trigger != .manual, lastUploadFailure == .malformedResponse,
               (malformedUploadCount ?? 0) >= malformedUploadLimit { return false }
            return true
        case .needsRetry:
            return trigger == .manual
        case .processing, .ready, .unrecoverable:
            return false
        }
    }
}

public struct RecognitionBadge: Equatable, Sendable {
    public let readyCount: Int
    public let needsAttention: Bool

    public init(readyCount: Int, needsAttention: Bool) {
        self.readyCount = readyCount
        self.needsAttention = needsAttention
    }
}

/// The Journal menu's badge, from local state only.
public func recognitionBadge(_ entries: [RecognitionEntry]) -> RecognitionBadge {
    RecognitionBadge(
        readyCount: entries.filter { $0.state == .ready }.count,
        needsAttention: entries.contains {
            $0.state == .needsRetry || ($0.state == .pendingUpload && $0.lastUploadFailure == .unauthorized)
        }
    )
}

private struct StoredEntriesFile: Codable {
    var version: Int
    var entries: [RecognitionEntry]
}

public enum StoredEntries {

    public static let currentVersion = 1

    /// Audio is kept at most this long, whatever state the entry is in.
    public static let audioRetentionSeconds: Double = 7 * 24 * 60 * 60
    /// A `ready` entry that was never imported is dropped this long after its result arrived.
    public static let readyRetentionSeconds: Double = 7 * 24 * 60 * 60

    public enum DecodeError: Error, Equatable, Sendable {
        case unsupportedVersion(Int)
    }

    public struct PurgeResult: Equatable, Sendable {
        public let entries: [RecognitionEntry]
        /// Audio file names the caller must delete.
        public let audioToDelete: [String]
    }

    public static func encode(_ entries: [RecognitionEntry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(StoredEntriesFile(version: currentVersion, entries: entries))
    }

    /// One undecodable entry is dropped; the rest are kept. A file that is not valid at all, or comes
    /// from a newer version, still throws so the caller can set it aside.
    public static func decode(_ data: Data) throws -> [RecognitionEntry] {
        try decodeReport(data).entries
    }

    public struct DecodeReport: Equatable, Sendable {
        public let entries: [RecognitionEntry]
        /// How many entries could not be decoded.
        public let droppedCount: Int
        /// Audio file names named by entries that could not be decoded. That audio is still somebody's
        /// recording and must never be swept as an orphan.
        public let droppedAudioFiles: Set<String>
    }

    public static func decodeReport(_ data: Data) throws -> DecodeReport {
        let file = try JSONDecoder().decode(LenientEntriesFile.self, from: data)
        guard file.version <= currentVersion else { throw DecodeError.unsupportedVersion(file.version) }
        return DecodeReport(
            entries: file.entries.compactMap(\.entry),
            droppedCount: file.entries.filter { $0.entry == nil }.count,
            droppedAudioFiles: Set(file.entries.filter { $0.entry == nil }.compactMap(\.audioFile))
        )
    }

    private struct LenientEntriesFile: Decodable {
        let version: Int
        let entries: [Lossy]
    }

    private struct Lossy: Decodable {
        let entry: RecognitionEntry?
        let audioFile: String?

        private enum Keys: String, CodingKey { case audioFile }

        init(from decoder: Decoder) throws {
            entry = try? RecognitionEntry(from: decoder)
            audioFile = (try? decoder.container(keyedBy: Keys.self))
                .flatMap { try? $0.decodeIfPresent(String.self, forKey: .audioFile) }
        }
    }

    /// The retention rules: audio past 7 days or missing from disk is released, stale `ready` entries
    /// are dropped, and audio files no entry names are deleted — but only once they are themselves older
    /// than the 7-day retention, so a clip whose entry failed to save stays recoverable.
    ///
    /// `audioFilesOnDisk` maps file name to modification time (Unix seconds). `protectedAudio` names
    /// files that must never be swept (audio of entries that could not be decoded).
    public static func purged(
        _ entries: [RecognitionEntry], now: Double, audioFilesOnDisk: [String: Double],
        protectedAudio: Set<String> = []
    ) -> PurgeResult {
        var toDelete = Set<String>()
        var kept: [RecognitionEntry] = []
        for original in entries {
            if original.state == .ready,
               let fetched = original.resultFetchedAt, now - fetched > readyRetentionSeconds {
                if let file = original.audioFile { toDelete.insert(file) }
                continue
            }
            var entry = original
            if let file = entry.audioFile {
                if now - entry.createdAt > audioRetentionSeconds {
                    toDelete.insert(file)
                    entry = entry.applying(.audioLost)
                } else if audioFilesOnDisk[file] == nil {
                    entry = entry.applying(.audioLost)
                }
            }
            kept.append(entry)
        }
        let referenced = Set(entries.compactMap(\.audioFile)).union(protectedAudio)
        let orphans = audioFilesOnDisk.filter { name, modified in
            !referenced.contains(name) && now - modified > audioRetentionSeconds
        }.keys
        return PurgeResult(entries: kept, audioToDelete: Array(toDelete.union(orphans)).sorted())
    }
}

/// Seconds to wait before the next long poll. A poll that returned early with no status change (a
/// server that ignores `wait`, say) must not turn into a tight loop: at least 2 s between such polls.
public func recognitionPollDelaySeconds(elapsed: Double, wait: Int, statusChanged: Bool) -> Double {
    let minimumInterval = 2.0
    if statusChanged || elapsed >= Double(wait) || elapsed >= minimumInterval { return 0 }
    return minimumInterval - max(elapsed, 0)
}
