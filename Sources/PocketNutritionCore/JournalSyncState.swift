// SPDX-License-Identifier: MPL-2.0

import Foundation

/// What the phone remembers about its journal's sync with one vault account.
///
/// Bound to the account: a different account starts from nothing, so signing in to another vault uploads
/// the whole local journal to it. A meal that has no known server revision has never been uploaded, and
/// that alone makes it go up, which is how a first sync transfers everything with no special mode.
public struct JournalSyncState: Codable, Equatable, Sendable {

    public var accountId: String
    /// `GET /v1/sync` position: everything up to here has been looked at.
    public var cursor: Int
    /// Meal id to the last revision the server is known to hold, tombstones included.
    public var revisions: [String: Int]
    /// Meals changed here since they were last uploaded.
    public var dirty: Set<String>
    /// Meals deleted here whose deletion the server has not heard yet.
    public var deleted: Set<String>

    public init(
        accountId: String, cursor: Int = 0, revisions: [String: Int] = [:], dirty: Set<String> = [],
        deleted: Set<String> = []
    ) {
        self.accountId = accountId
        self.cursor = cursor
        self.revisions = revisions
        self.dirty = dirty
        self.deleted = deleted
    }

    public mutating func markChanged(_ id: String) {
        deleted.remove(id)
        dirty.insert(id)
    }

    /// A meal that never reached the server needs no deletion there.
    public mutating func markDeleted(_ id: String) {
        dirty.remove(id)
        if revisions[id] != nil { deleted.insert(id) }
    }

    /// Whether there is anything to send, given the meals that exist locally.
    public func hasWork(localIds: Set<String>) -> Bool {
        !dirty.isEmpty || !deleted.isEmpty || localIds.contains { revisions[$0] == nil }
    }
}
