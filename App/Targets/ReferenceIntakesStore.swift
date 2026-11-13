// SPDX-License-Identifier: MPL-2.0

import Foundation
import Observation
import PocketNutritionCore

/// Daily targets behind a preview switch (spec 05 §7): on in debug builds, off in release builds. When it is
/// off nothing of the feature is shown and nothing is fetched.
enum TargetsFeature {
    static let defaultsKey = "dailyTargetsPreview"

    #if DEBUG
    static let defaultEnabled = true
    #else
    static let defaultEnabled = false
    #endif

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? defaultEnabled
    }
}

/// The EFSA reference table from `GET /reference-intakes`, cached on disk with its fetch time.
///
/// Never bundled: the app embeds no reference value. Refetched when older than 24 hours; a failed fetch
/// keeps the cache. With no cache at all (first launch offline) there is no table, and the targets UI says
/// it needs a connection while the journal works as before.
@MainActor
@Observable
final class ReferenceIntakesStore {

    struct Cache: Codable {
        var fetchedAt: Date
        var response: ReferenceIntakesResponse
    }

    static let maxAge: TimeInterval = 24 * 60 * 60

    private(set) var cache: Cache?
    private(set) var isFetching = false

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let fetch: @Sendable () async throws -> ReferenceIntakesResponse

    init(
        fileURL: URL? = nil,
        fetch: @escaping @Sendable () async throws -> ReferenceIntakesResponse = {
            try await PocketNutritionApi.shared.referenceIntakes()
        }
    ) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("reference-intakes.json")
        }
        self.fetch = fetch
        if let data = try? Data(contentsOf: self.fileURL) {
            cache = try? JSONDecoder().decode(Cache.self, from: data)
        }
    }

    /// The rows, or nil when the table has never been fetched.
    var rows: [ReferenceRow]? { cache?.response.values }

    /// Fetches the table when there is none or it is older than a day. Silent on failure: the cache stays.
    func refreshIfStale(now: Date = Date()) async {
        guard TargetsFeature.isEnabled, !isFetching else { return }
        if let cache, now.timeIntervalSince(cache.fetchedAt) < Self.maxAge { return }
        isFetching = true
        defer { isFetching = false }
        guard let response = try? await fetch(), !response.values.isEmpty else { return }
        let fresh = Cache(fetchedAt: now, response: response)
        cache = fresh
        if let data = try? JSONEncoder().encode(fresh) { try? data.write(to: fileURL, options: .atomic) }
    }
}
