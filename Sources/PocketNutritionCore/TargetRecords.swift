// SPDX-License-Identifier: MPL-2.0

import Foundation

// The daily-targets data as vault records: the plaintext of `profile`, `targets` and `weight` records, before
// encryption (spec 05 §3). Like `MealRecordPayload`, these are their own types rather than the app's models,
// so the wire format cannot change by accident when the UI does, and Android and the `me` viewer can
// implement exactly this. JSON is snake_case, `updated_at` is seconds since 1970, readers ignore unknown
// fields, and a record whose `version` is newer than this client reads is refused, never overwritten.

/// The record id of the one `profile` record of an account.
public let profileRecordId = "profile"
/// The record id of the one `targets` record of an account.
public let targetsRecordId = "targets"

/// `weight-YYYY-MM-DD`: one record per day.
public func weightRecordId(date: String) -> String { "weight-\(date)" }

/// The day of a weight record id, or nil when the id is not one.
public func weightRecordDate(recordId: String) -> String? {
    guard recordId.hasPrefix("weight-") else { return nil }
    let date = String(recordId.dropFirst("weight-".count))
    return isCalendarDay(date) ? date : nil
}

/// "YYYY-MM-DD", digits only.
public func isCalendarDay(_ value: String) -> Bool {
    let parts = value.split(separator: "-", omittingEmptySubsequences: false)
    return parts.count == 3 && parts.map(\.count) == [4, 2, 2] && parts.allSatisfy { $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }
}

/// Vault record ids match `^[A-Za-z0-9_-]{1,64}$`.
public func isValidVaultRecordId(_ id: String) -> Bool {
    guard (1...64).contains(id.count) else { return false }
    return id.unicodeScalars.allSatisfy { s in
        (s >= "A" && s <= "Z") || (s >= "a" && s <= "z") || (s >= "0" && s <= "9") || s == "_" || s == "-"
    }
}

// MARK: - profile

public struct ProfileRecordPayload: Codable, Equatable, Sendable {

    public static let version = 1
    public static let readableVersions: ClosedRange<Int> = 1...1

    public struct Version: Codable, Equatable, Sendable {
        public var effectiveFrom: String
        public var birthYear: Int
        public var basis: CalculationBasis
        public var situation: TargetSituation
        public var trimester: Int?
        public var lactation: LactationPeriod?
        public var postmenopausal: Bool?
        public var pal: Double
        public var weightKg: Double
        public var phytateMgPerDay: Double?
        /// Not in spec 05's example: the questionnaire's height, kept for later. Readers ignore it.
        public var heightCm: Double?

        public init(_ v: ProfileVersion) {
            effectiveFrom = v.effectiveFrom
            birthYear = v.birthYear
            basis = v.basis
            situation = v.situation
            trimester = v.trimester
            lactation = v.lactation
            postmenopausal = v.postmenopausal
            pal = v.pal
            weightKg = v.weightKg
            phytateMgPerDay = v.phytateMgPerDay
            heightCm = v.heightCm
        }

        public var profileVersion: ProfileVersion {
            ProfileVersion(
                effectiveFrom: effectiveFrom, birthYear: birthYear, basis: basis, situation: situation,
                trimester: trimester, lactation: lactation, postmenopausal: postmenopausal, pal: pal,
                weightKg: weightKg, phytateMgPerDay: phytateMgPerDay, heightCm: heightCm)
        }

        private enum CodingKeys: String, CodingKey {
            case basis, situation, trimester, lactation, postmenopausal, pal
            case effectiveFrom = "effective_from"
            case birthYear = "birth_year"
            case weightKg = "weight_kg"
            case phytateMgPerDay = "phytate_mg_per_day"
            case heightCm = "height_cm"
        }

        // Every optional is written as null rather than left out, as spec 05 shows the record.
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(effectiveFrom, forKey: .effectiveFrom)
            try c.encode(birthYear, forKey: .birthYear)
            try c.encode(basis, forKey: .basis)
            try c.encode(situation, forKey: .situation)
            try c.encode(trimester, forKey: .trimester)
            try c.encode(lactation, forKey: .lactation)
            try c.encode(postmenopausal, forKey: .postmenopausal)
            try c.encode(pal, forKey: .pal)
            try c.encode(weightKg, forKey: .weightKg)
            try c.encode(phytateMgPerDay, forKey: .phytateMgPerDay)
            try c.encodeIfPresent(heightCm, forKey: .heightCm)
        }
    }

    public var version: Int
    public var updatedAt: Double
    public var versions: [Version]

    public init(updatedAt: Double, versions: [ProfileVersion]) {
        version = Self.version
        self.updatedAt = updatedAt
        self.versions = versions.map(Version.init)
    }

    public var profileVersions: [ProfileVersion] { versions.map(\.profileVersion) }

    private enum CodingKeys: String, CodingKey {
        case version, versions
        case updatedAt = "updated_at"
    }
}

// MARK: - targets

/// Which nutrients the rings show, in display order. Not versioned.
public struct WatchList: Codable, Equatable, Sendable {
    /// A preset name, or `custom` once the keys were edited by hand.
    public var preset: String
    public var keys: [String]

    public init(preset: String, keys: [String]) {
        self.preset = preset
        self.keys = keys
    }
}

public struct TargetsRecordPayload: Codable, Equatable, Sendable {

    public static let version = 1
    public static let readableVersions: ClosedRange<Int> = 1...1

    public struct Override: Codable, Equatable, Sendable {
        public var effectiveFrom: String
        public var values: [String: TargetOverride]

        public init(_ v: OverrideVersion) {
            effectiveFrom = v.effectiveFrom
            values = v.values
        }

        public var overrideVersion: OverrideVersion {
            OverrideVersion(effectiveFrom: effectiveFrom, values: values)
        }

        private enum CodingKeys: String, CodingKey {
            case values
            case effectiveFrom = "effective_from"
        }
    }

    public var version: Int
    public var updatedAt: Double
    public var overrides: [Override]
    public var watchList: WatchList

    public init(updatedAt: Double, overrides: [OverrideVersion], watchList: WatchList) {
        version = Self.version
        self.updatedAt = updatedAt
        self.overrides = overrides.map(Override.init)
        self.watchList = watchList
    }

    public var overrideVersions: [OverrideVersion] { overrides.map(\.overrideVersion) }

    private enum CodingKeys: String, CodingKey {
        case version, overrides
        case updatedAt = "updated_at"
        case watchList = "watch_list"
    }
}

// MARK: - weight

public struct WeightRecordPayload: Codable, Equatable, Sendable {

    public static let version = 1
    public static let readableVersions: ClosedRange<Int> = 1...1

    public var version: Int
    public var updatedAt: Double
    public var date: String
    public var kg: Double

    public init(updatedAt: Double, date: String, kg: Double) {
        version = Self.version
        self.updatedAt = updatedAt
        self.date = date
        self.kg = kg
    }

    public var entry: WeightEntry { WeightEntry(date: date, kg: kg) }

    private enum CodingKeys: String, CodingKey {
        case version, date, kg
        case updatedAt = "updated_at"
    }
}

// MARK: - One type for the three

/// A `profile`, `targets` or `weight` record, so the three sync together in one pass.
public enum TargetsVaultRecord: Equatable, Sendable {
    case profile(ProfileRecordPayload)
    case targets(TargetsRecordPayload)
    case weight(WeightRecordPayload)

    public static let profileType = "profile"
    public static let targetsType = "targets"
    public static let weightType = "weight"
    public static let types: Set<String> = [profileType, targetsType, weightType]

    public var recordId: String {
        switch self {
        case .profile: profileRecordId
        case .targets: targetsRecordId
        case .weight(let w): weightRecordId(date: w.date)
        }
    }

    public var recordType: String {
        switch self {
        case .profile: Self.profileType
        case .targets: Self.targetsType
        case .weight: Self.weightType
        }
    }

    public var updatedAt: Double {
        switch self {
        case .profile(let p): p.updatedAt
        case .targets(let t): t.updatedAt
        case .weight(let w): w.updatedAt
        }
    }
}

public enum TargetsRecordError: Error, Equatable, Sendable {
    case malformed
    /// Written by a newer version of the app: leave it alone rather than overwrite what cannot be read.
    case unsupportedVersion(Int)
    /// The payload does not belong to the record it arrived in (a swapped record or a wrong type).
    case idMismatch
}

public func encodeTargetsRecord(_ record: TargetsVaultRecord) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    switch record {
    case .profile(let p): return try encoder.encode(p)
    case .targets(let t): return try encoder.encode(t)
    case .weight(let w): return try encoder.encode(w)
    }
}

/// Only the version, read first so a newer format is reported as such rather than as malformed.
private struct VersionProbe: Decodable { var version: Int }

public func decodeTargetsRecord(
    _ plaintext: Data, type: String, expectedId: String
) throws(TargetsRecordError) -> TargetsVaultRecord {
    let decoder = JSONDecoder()
    guard let probe = try? decoder.decode(VersionProbe.self, from: plaintext) else { throw .malformed }
    let record: TargetsVaultRecord
    switch type {
    case TargetsVaultRecord.profileType:
        guard ProfileRecordPayload.readableVersions.contains(probe.version) else { throw .unsupportedVersion(probe.version) }
        guard let p = try? decoder.decode(ProfileRecordPayload.self, from: plaintext) else { throw .malformed }
        record = .profile(p)
    case TargetsVaultRecord.targetsType:
        guard TargetsRecordPayload.readableVersions.contains(probe.version) else { throw .unsupportedVersion(probe.version) }
        guard let t = try? decoder.decode(TargetsRecordPayload.self, from: plaintext) else { throw .malformed }
        record = .targets(t)
    case TargetsVaultRecord.weightType:
        guard WeightRecordPayload.readableVersions.contains(probe.version) else { throw .unsupportedVersion(probe.version) }
        guard let w = try? decoder.decode(WeightRecordPayload.self, from: plaintext), isCalendarDay(w.date) else { throw .malformed }
        record = .weight(w)
    default:
        throw .malformed
    }
    guard record.recordId == expectedId else { throw .idMismatch }
    return record
}
