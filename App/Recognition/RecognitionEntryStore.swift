// SPDX-License-Identifier: MPL-2.0

import Foundation
import Observation
import PocketNutritionCore

/// The voice-capture entries and their audio files, persisted locally.
///
/// The entries are a versioned JSON file in Application Support (the `JournalStore` pattern) and the
/// audio lives in a private folder beside it. BOTH are excluded from backup and written with
/// `.completeUnlessOpen` data protection: encrypted at rest whenever the device is locked, yet a
/// recording already open keeps writing if the screen locks mid-clip, and a result that lands in the
/// brief background time after locking can still be saved. (`.complete` would fail exactly those.)
///
/// The retention rules are the pure `StoredEntries.purged` in Core; this class applies them to disk.
/// Ordering rule throughout: PERSIST FIRST, delete files and server tickets AFTER, and never delete
/// anything if the persist failed.
@MainActor
@Observable
final class RecognitionEntryStore {

    struct PersistError: Error {}

    private(set) var entries: [RecognitionEntry] = []

    private let fileURL: URL
    private let audioDirectory: URL
    private let now: @Sendable () -> Date
    /// True while the entries are NOT known to have been loaded: the file exists but could not be read
    /// (or the audio folder could not be listed). While true nothing is written and NOTHING is deleted —
    /// no purge, no orphan sweep — because an empty in-memory list would make every recording look
    /// abandoned. `recover()` retries the load and clears it.
    private(set) var isBlocked = false
    /// The last write failed. Uploading is paused meanwhile: a ticket that cannot be recorded locally
    /// would be created and thrown away again on every retry.
    private var lastWriteFailed = false
    /// Audio named by entries that could not be decoded, or every file when the entries file had to be
    /// set aside: never swept as orphans this session.
    private var protectedAudio: Set<String> = []

    /// Whether a state change can currently be saved. The coordinator does not upload otherwise.
    var canPersist: Bool { !isBlocked && !lastWriteFailed }

    init(directory: URL? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let audioDirectory = base.appendingPathComponent("RecognitionAudio", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: audioDirectory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
        )
        fileURL = base.appendingPathComponent("recognition-entries.json")
        self.audioDirectory = audioDirectory
        self.now = now
        Self.excludeFromBackup(audioDirectory)
        load()
    }

    var entriesNewestFirst: [RecognitionEntry] { entries.sorted { $0.createdAt > $1.createdAt } }

    /// From local state only — safe to read in any `body`.
    var badge: RecognitionBadge { recognitionBadge(entries) }

    func entry(_ localId: String) -> RecognitionEntry? { entries.first { $0.localId == localId } }

    func audioURL(of entry: RecognitionEntry) -> URL? {
        entry.audioFile.map { audioDirectory.appendingPathComponent($0) }
    }

    /// A fresh path inside the private audio folder. The recorder writes straight here, so a clip is
    /// never in a less protected place (and a crash mid-recording leaves an orphan, swept on launch).
    func newRecordingURL() -> URL {
        audioDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
    }

    /// Saves an encoded meal photo in the same private folder as the clips (same protection, same
    /// retention) and returns its path, ready for `createEntry(adopting:)`. Its `.jpg` extension is what
    /// makes it upload as a photo.
    func savePhoto(_ jpeg: Data) throws -> URL {
        let url = audioDirectory.appendingPathComponent("\(UUID().uuidString).\(recognitionPhotoExtension)")
        try jpeg.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        return url
    }

    /// Clips that exist on disk but could not be given an entry (storage blocked or failing). Kept in
    /// the private audio folder and offered again by `retryUnsavedClips()` instead of waiting for the
    /// 7-day sweep. In memory only: after a relaunch such a clip is an orphan like any other.
    private(set) var unsavedClips: [URL] = []

    /// Persists a finished recording as `pendingUpload` — BEFORE any network call. A blocked store is
    /// recovered first; if persisting still fails this throws, the audio file is left where it is, and
    /// the clip is remembered in `unsavedClips`.
    func createEntry(adopting recordingURL: URL) throws -> RecognitionEntry {
        if isBlocked { recover() }
        do {
            let entry = try makeEntry(adopting: recordingURL)
            unsavedClips.removeAll { $0 == recordingURL }
            return entry
        } catch {
            if FileManager.default.fileExists(atPath: recordingURL.path), !unsavedClips.contains(recordingURL) {
                unsavedClips = unsavedClips + [recordingURL]
            }
            throw error
        }
    }

    /// Tries again to give every unsaved clip an entry. Returns the entries that were created.
    func retryUnsavedClips() -> [RecognitionEntry] {
        recover()
        return unsavedClips.compactMap { try? createEntry(adopting: $0) }
    }

    private func makeEntry(adopting recordingURL: URL) throws -> RecognitionEntry {
        let name = recordingURL.lastPathComponent
        guard recordingURL.deletingLastPathComponent().standardizedFileURL == audioDirectory.standardizedFileURL,
              FileManager.default.fileExists(atPath: recordingURL.path)
        else { throw PersistError() }
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: recordingURL.path
        )
        Self.excludeFromBackup(recordingURL)
        let entry = RecognitionEntry(
            localId: UUID().uuidString, createdAt: now().timeIntervalSince1970, audioFile: name
        )
        let updated = entries + [entry]
        // One retry: a transient write failure should not cost the user a recording.
        guard persist(updated) || persist(updated) else { throw PersistError() }
        entries = updated
        return entry
    }

    /// Applies a transition. Returns true only if the new state reached disk; in that case a released
    /// audio file is deleted afterwards. On false nothing changed and nothing was deleted, so callers
    /// must not delete a server ticket either.
    @discardableResult
    func apply(_ event: RecognitionEntryEvent, to localId: String) -> Bool {
        guard let index = entries.firstIndex(where: { $0.localId == localId }) else { return false }
        let before = entries[index]
        let after = before.applying(event)
        guard after != before else { return true }
        let updated = entries.enumerated().map { $0.offset == index ? after : $0.element }
        guard persist(updated) else { return false }
        entries = updated
        if let released = before.audioFile, after.audioFile == nil { deleteAudio(released) }
        return true
    }

    /// Removes the entry and its audio. The audio stays if the removal could not be persisted.
    @discardableResult
    func remove(_ localId: String) -> Bool {
        guard let entry = entry(localId) else { return true }
        let updated = entries.filter { $0.localId != localId }
        guard persist(updated) else { return false }
        entries = updated
        if let file = entry.audioFile { deleteAudio(file) }
        return true
    }

    /// Re-applies the 7-day retention rules (also on return to the foreground, not only at launch).
    /// Does nothing unless the entries were loaded successfully.
    func purgeNow() {
        guard !isBlocked, let onDisk = listAudio() else { return }
        applyPurge(to: entries, onDisk: onDisk)
    }

    /// Retries whatever is stuck: a blocked load is attempted again; a failed write is retried.
    func recover() {
        if isBlocked {
            load()
        } else if lastWriteFailed {
            _ = persist(entries)
        }
    }

    // MARK: - Disk

    private func load() {
        isBlocked = true   // until proven otherwise
        var loaded: [RecognitionEntry] = []
        var dropped: Set<String> = []
        var setAside = false
        if FileManager.default.fileExists(atPath: fileURL.path) {
            guard let data = readWithRetry(fileURL) else {
                // A read ERROR is not an empty file. Touch nothing.
                return
            }
            if let report = try? StoredEntries.decodeReport(data) {
                // The first write would rewrite the file without the entries we could not read: keep a
                // copy first, and stay blocked if that cannot be done.
                if report.droppedCount > 0, !salvageEntriesFile(move: false) { return }
                loaded = report.entries
                dropped = report.droppedAudioFiles
                // Entries we could not decode may still own audio we cannot name: protect all of it.
                setAside = report.droppedCount > report.droppedAudioFiles.count
            } else {
                // Set aside rather than overwritten, as `JournalStore` does. Its entries are unknown, so
                // none of the audio may be swept this session. If it cannot be moved away we stay
                // blocked: the next write would otherwise replace the only copy.
                guard salvageEntriesFile(move: true) else { return }
                setAside = true
            }
        }
        guard let onDisk = listAudio() else { return }
        protectedAudio = setAside ? Set(onDisk.keys) : dropped
        entries = loaded
        isBlocked = false
        lastWriteFailed = false
        applyPurge(to: loaded, onDisk: onDisk)
    }

    /// Keeps the entries file under a unique name — never by deleting an earlier salvage first — and
    /// retains the three most recent. Returns false if it could not be done.
    private func salvageEntriesFile(move: Bool) -> Bool {
        let directory = fileURL.deletingLastPathComponent()
        let prefix = "recognition-entries.unreadable-"
        let stamp = Int(now().timeIntervalSince1970)
        let destination = directory.appendingPathComponent("\(prefix)\(stamp)-\(UUID().uuidString.prefix(6)).json")
        do {
            if move {
                try FileManager.default.moveItem(at: fileURL, to: destination)
            } else {
                try FileManager.default.copyItem(at: fileURL, to: destination)
            }
        } catch {
            return false
        }
        Self.excludeFromBackup(destination)
        let kept = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasPrefix(prefix) }
            .sorted()
        // Names start with the timestamp, so lexical order is age order.
        for name in kept.dropLast(3) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        return true
    }

    private func applyPurge(to current: [RecognitionEntry], onDisk: [String: Double]) {
        guard !isBlocked else { return }
        let purge = StoredEntries.purged(
            current, now: now().timeIntervalSince1970, audioFilesOnDisk: onDisk, protectedAudio: protectedAudio
        )
        // Persist the new state first; only then remove files.
        if purge.entries != current {
            guard persist(purge.entries) else { return }
            entries = purge.entries
        }
        purge.audioToDelete.forEach(deleteAudio)
    }

    /// Audio folder contents with modification times (Unix seconds); nil if it cannot be listed.
    private func listAudio() -> [String: Double]? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: audioDirectory.path) else {
            return nil
        }
        let fallback = now().timeIntervalSince1970
        return Dictionary(uniqueKeysWithValues: names.map { name in
            let url = audioDirectory.appendingPathComponent(name)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            // An unreadable date counts as "now": unknown age is never a reason to delete.
            return (name, modified?.timeIntervalSince1970 ?? fallback)
        })
    }

    private func readWithRetry(_ url: URL) -> Data? {
        for _ in 0..<2 {
            if let data = try? Data(contentsOf: url) { return data }
        }
        return nil
    }

    private func deleteAudio(_ file: String) {
        try? FileManager.default.removeItem(at: audioDirectory.appendingPathComponent(file))
    }

    private func persist(_ list: [RecognitionEntry]) -> Bool {
        guard !isBlocked, let data = try? StoredEntries.encode(list) else { return false }
        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch {
            lastWriteFailed = true
            return false
        }
        lastWriteFailed = false
        Self.excludeFromBackup(fileURL)
        return true
    }

    private static func excludeFromBackup(_ url: URL) {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }
}
