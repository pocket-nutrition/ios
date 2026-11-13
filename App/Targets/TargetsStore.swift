// SPDX-License-Identifier: MPL-2.0

import Foundation
import Observation
import PocketNutritionCore

/// What changed in the targets data because of the person, by vault record id.
enum TargetsChange {
    case saved(String)
    case deleted(String)
}

/// The person's daily-targets data on this phone (spec 05 §2): profile history, override history, watch list
/// and weight log. Health data: it stays in this file and, with a vault account, in the encrypted vault. It is
/// never sent to the API.
///
/// Versioned histories, so a past day keeps the targets it had: saving the questionnaire appends a version
/// dated today (replacing today's), any override change appends a complete snapshot dated today (replacing
/// today's). Older versions are never edited.
@MainActor
@Observable
final class TargetsStore {

    struct StoredWeight: Codable, Hashable {
        var date: String
        var kg: Double
        var updatedAt: Double
    }

    private struct File: Codable {
        var version: Int
        var profiles: [ProfileVersion]
        var profileUpdatedAt: Double?
        var overrides: [OverrideVersion]
        var watchList: WatchList
        var targetsUpdatedAt: Double?
        var weights: [StoredWeight]
    }

    private(set) var profiles: [ProfileVersion] = []
    private(set) var profileUpdatedAt: Double?
    private(set) var overrides: [OverrideVersion] = []
    private(set) var watchList: WatchList = WatchListPreset.standard.watchList
    private(set) var targetsUpdatedAt: Double?
    private(set) var weights: [StoredWeight] = []

    /// Told about every change the person makes, never about what `apply` writes from the vault.
    @ObservationIgnored var onChange: ((TargetsChange) -> Void)?

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let now: () -> Date

    init(fileURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("targets.json")
        }
        self.now = now
        load()
    }

    // MARK: - Reading

    var weightEntries: [WeightEntry] {
        weights.map { WeightEntry(date: $0.date, kg: $0.kg) }.sorted { $0.date < $1.date }
    }

    var latestProfile: ProfileVersion? { profiles.last }

    /// Whether the person has set anything up: a profile, or overrides alone after "Skip".
    var isConfigured: Bool { !profiles.isEmpty || !overrides.isEmpty }

    var today: String { localDay(now()) }

    /// The overrides in force today.
    var currentOverrides: [String: TargetOverride] { overridesForDay(overrides, day: today) }

    // MARK: - Changes

    func saveProfile(_ version: ProfileVersion) {
        var dated = version
        dated.effectiveFrom = today
        if profiles.last?.effectiveFrom == dated.effectiveFrom {
            profiles[profiles.count - 1] = dated
        } else {
            profiles.append(dated)
        }
        profileUpdatedAt = stamp()
        persist()
        onChange?(.saved(profileRecordId))
    }

    /// Sets (or with nil, resets to EFSA) one nutrient's override, as a new complete snapshot dated today.
    func setOverride(_ key: String, _ value: TargetOverride?) {
        var values = currentOverrides
        values[key] = value
        appendOverrides(values)
    }

    func resetAllOverrides() { appendOverrides([:]) }

    func choosePreset(_ preset: WatchListPreset) {
        watchList = preset.watchList
        touchTargets()
    }

    /// Editing the keys by hand makes the list custom.
    func setWatchKeys(_ keys: [String]) {
        watchList = WatchList(preset: WatchListPreset.custom, keys: keys)
        touchTargets()
    }

    /// One entry per date: a new entry for the same date replaces it.
    func logWeight(date: String, kg: Double) {
        weights.removeAll { $0.date == date }
        weights.append(StoredWeight(date: date, kg: kg, updatedAt: stamp()))
        persist()
        onChange?(.saved(weightRecordId(date: date)))
    }

    func deleteWeight(date: String) {
        weights.removeAll { $0.date == date }
        persist()
        onChange?(.deleted(weightRecordId(date: date)))
    }

    private func appendOverrides(_ values: [String: TargetOverride]) {
        let version = OverrideVersion(effectiveFrom: today, values: values)
        if overrides.last?.effectiveFrom == version.effectiveFrom {
            overrides[overrides.count - 1] = version
        } else {
            overrides.append(version)
        }
        touchTargets()
    }

    private func touchTargets() {
        targetsUpdatedAt = stamp()
        persist()
        onChange?(.saved(targetsRecordId))
    }

    /// Strictly increasing, so two quick edits never tie on `updated_at`.
    private func stamp() -> Double {
        let latest = ([profileUpdatedAt, targetsUpdatedAt] + weights.map(\.updatedAt)).compactMap { $0 }.max() ?? 0
        return max(now().timeIntervalSince1970.rounded(.down), latest + 1)
    }

    // MARK: - Vault records

    var records: [TargetsVaultRecord] {
        var out: [TargetsVaultRecord] = []
        if let profileUpdatedAt, !profiles.isEmpty {
            out.append(.profile(ProfileRecordPayload(updatedAt: profileUpdatedAt, versions: profiles)))
        }
        if let targetsUpdatedAt {
            out.append(.targets(TargetsRecordPayload(updatedAt: targetsUpdatedAt, overrides: overrides, watchList: watchList)))
        }
        out += weights.map { .weight(WeightRecordPayload(updatedAt: $0.updatedAt, date: $0.date, kg: $0.kg)) }
        return out
    }

    /// Record id to last local edit, for settling a sync against edits made while it ran.
    var localUpdatedAt: [String: Double] {
        Dictionary(records.map { ($0.recordId, $0.updatedAt) }, uniquingKeysWith: { _, last in last })
    }

    /// Writes what the vault sync brought in. One write, and no `onChange`.
    func apply(upserts: [TargetsVaultRecord], deletes: Set<String>) {
        guard !upserts.isEmpty || !deletes.isEmpty else { return }
        let deletedDates = Set(deletes.compactMap { weightRecordDate(recordId: $0) })
        weights.removeAll { deletedDates.contains($0.date) }
        for record in upserts {
            switch record {
            case .profile(let p):
                profiles = p.profileVersions
                profileUpdatedAt = p.updatedAt
            case .targets(let t):
                overrides = t.overrideVersions
                watchList = t.watchList
                targetsUpdatedAt = t.updatedAt
            case .weight(let w):
                weights.removeAll { $0.date == w.date }
                weights.append(StoredWeight(date: w.date, kg: w.kg, updatedAt: w.updatedAt))
            }
        }
        persist()
    }

    // MARK: - File

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else {
            // Set aside rather than overwritten: it may be a newer format, and it is the person's data.
            let salvage = fileURL.deletingLastPathComponent().appendingPathComponent("targets.unreadable.json")
            try? FileManager.default.removeItem(at: salvage)
            try? FileManager.default.moveItem(at: fileURL, to: salvage)
            return
        }
        profiles = file.profiles
        profileUpdatedAt = file.profileUpdatedAt
        overrides = file.overrides
        watchList = file.watchList
        targetsUpdatedAt = file.targetsUpdatedAt
        weights = file.weights
    }

    private func persist() {
        let file = File(
            version: 1, profiles: profiles, profileUpdatedAt: profileUpdatedAt, overrides: overrides,
            watchList: watchList, targetsUpdatedAt: targetsUpdatedAt, weights: weights)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
