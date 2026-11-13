// SPDX-License-Identifier: MPL-2.0

import Foundation

// Which profile, weight and target overrides apply on a given day, so that editing the profile or logging a
// weight changes today's targets without rewriting the past. Port of the sandbox's `targetHistory.ts`, held
// to the `weight-for-day`, `profile-for-day` and `apply-target-overrides` suites. All dates are local
// calendar days written "YYYY-MM-DD"; they compare as strings.

/// One saved state of the questionnaire, in force from `effectiveFrom` until the next version.
public struct ProfileVersion: Codable, Equatable, Sendable {
    public var effectiveFrom: String
    public var birthYear: Int
    public var basis: CalculationBasis
    public var situation: TargetSituation
    public var trimester: Int?
    public var lactation: LactationPeriod?
    public var postmenopausal: Bool?
    public var pal: Double
    /// The weight typed in the questionnaire; the weight log takes over when it has entries.
    public var weightKg: Double
    public var phytateMgPerDay: Double?
    /// Stored for later; EFSA's table does not use it. Not part of the contract's calculation.
    public var heightCm: Double?

    public init(
        effectiveFrom: String, birthYear: Int, basis: CalculationBasis, situation: TargetSituation,
        trimester: Int? = nil, lactation: LactationPeriod? = nil, postmenopausal: Bool? = nil, pal: Double,
        weightKg: Double, phytateMgPerDay: Double? = nil, heightCm: Double? = nil
    ) {
        self.effectiveFrom = effectiveFrom
        self.birthYear = birthYear
        self.basis = basis
        self.situation = situation
        self.trimester = trimester
        self.lactation = lactation
        self.postmenopausal = postmenopausal
        self.pal = pal
        self.weightKg = weightKg
        self.phytateMgPerDay = phytateMgPerDay
        self.heightCm = heightCm
    }
}

public struct WeightEntry: Codable, Equatable, Hashable, Sendable {
    public var date: String
    public var kg: Double

    public init(date: String, kg: Double) {
        self.date = date
        self.kg = kg
    }
}

/// A user-set daily target for one nutrient: replaces the computed min/max, never the safety upper limit.
public struct TargetOverride: Codable, Equatable, Hashable, Sendable {
    public var min: Double?
    public var max: Double?

    public init(min: Double?, max: Double?) {
        self.min = min
        self.max = max
    }

    // Both keys are always written, null included, as the vault record shows them.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(min, forKey: .min)
        try c.encode(max, forKey: .max)
    }

    private enum CodingKeys: String, CodingKey { case min, max }
}

/// The complete set of overrides in force from `effectiveFrom` (a snapshot, not a diff).
public struct OverrideVersion: Codable, Equatable, Sendable {
    public var effectiveFrom: String
    public var values: [String: TargetOverride]

    public init(effectiveFrom: String, values: [String: TargetOverride]) {
        self.effectiveFrom = effectiveFrom
        self.values = values
    }
}

/// A target as it applies on one day, after the overrides.
public struct DayTarget: Codable, Equatable, Sendable {
    public var nutrientKey: String
    public var unit: TargetUnit
    public var min: Double?
    public var max: Double?
    public var upperLimit: Double?
    public var sources: [String]
    public var overridden: Bool

    public init(_ target: NutrientTarget, overridden: Bool) {
        nutrientKey = target.nutrientKey
        unit = target.unit
        min = target.min
        max = target.max
        upperLimit = target.upperLimit
        sources = target.sources
        self.overridden = overridden
    }

    public var progressTarget: ProgressTarget {
        ProgressTarget(nutrientKey: nutrientKey, unit: unit, min: min, max: max, upperLimit: upperLimit)
    }
}

// MARK: - Calendar days

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// `day` ("YYYY-MM-DD") moved by `delta` calendar days. Pure date arithmetic, no time zone involved.
public func addDays(_ day: String, _ delta: Int) -> String {
    let parts = day.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3,
          let date = utcCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
          let moved = utcCalendar.date(byAdding: .day, value: delta, to: date)
    else { return day }
    let c = utcCalendar.dateComponents([.year, .month, .day], from: moved)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

/// The local calendar day of `date`, "YYYY-MM-DD".
public func localDay(_ date: Date, calendar: Calendar = .current) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

// MARK: - History

private let weightWindowDays = 7

/// The latest item with effectiveFrom <= day; among equal dates the last one in the list wins.
private func latestOnOrBefore<T>(_ items: [T], _ day: String, _ effectiveFrom: (T) -> String) -> T? {
    var best: T?
    for item in items {
        let from = effectiveFrom(item)
        if from > day { continue }
        if best == nil || from >= effectiveFrom(best!) { best = item }
    }
    return best
}

/// The weight to compute with on `day`: the mean of the entries of the 7 calendar days ending on `day`
/// (inclusive), rounded half-up to one decimal, which smooths day-to-day water swings. With no entry in that
/// window, the most recent earlier entry; with none at all, nil. Entries after `day` are ignored, so a past
/// day keeps the weight known then.
public func weightForDay(_ entries: [WeightEntry], day: String) -> Double? {
    let windowStart = addDays(day, -(weightWindowDays - 1))
    let inWindow = entries.filter { $0.date >= windowStart && $0.date <= day }
    if !inWindow.isEmpty {
        let mean = inWindow.reduce(0) { $0 + $1.kg } / Double(inWindow.count)
        return Double(roundHalfUp(mean * 10)) / 10
    }
    let earlier = entries.filter { $0.date < windowStart }
    guard let first = earlier.first else { return nil }
    return earlier.dropFirst().reduce(first) { a, b in b.date >= a.date ? b : a }.kg
}

/// The profile in force on `day`, ready for `dailyTargets`: the latest version on or before the day, with the
/// age on that day (calendar year minus birth year) and the weight from the log when it has one. Nil before
/// the first version: a day logged before the questionnaire was filled gets no target.
public func profileForDay(_ versions: [ProfileVersion], weights: [WeightEntry], day: String) -> TargetProfile? {
    guard let version = latestOnOrBefore(versions, day, \.effectiveFrom),
          let year = Int(day.prefix(4))
    else { return nil }
    return TargetProfile(
        ageYears: year - version.birthYear, basis: version.basis, situation: version.situation,
        trimester: version.trimester, lactation: version.lactation, postmenopausal: version.postmenopausal,
        pal: version.pal, weightKg: weightForDay(weights, day: day) ?? version.weightKg,
        phytateMgPerDay: version.phytateMgPerDay)
}

/// The overrides in force on `day` (empty when none).
public func overridesForDay(_ versions: [OverrideVersion], day: String) -> [String: TargetOverride] {
    latestOnOrBefore(versions, day, \.effectiveFrom)?.values ?? [:]
}

/// The computed `targets` with the overrides in force on `day` applied. An override replaces min and max and
/// keeps the EFSA upper limit and sources; an override on a nutrient with no computed target (salt, sugars)
/// adds one with no upper limit and no source. Sorted by nutrientKey.
public func applyOverrides(_ targets: [NutrientTarget], versions: [OverrideVersion], day: String) -> [DayTarget] {
    let values = overridesForDay(versions, day: day)
    var out = targets.map { target -> DayTarget in
        guard let o = values[target.nutrientKey] else { return DayTarget(target, overridden: false) }
        var t = DayTarget(target, overridden: true)
        t.min = o.min
        t.max = o.max
        return t
    }
    let known = Set(targets.map(\.nutrientKey))
    for (key, o) in values where !known.contains(key) {
        out.append(DayTarget(
            NutrientTarget(nutrientKey: key, unit: TargetUnit(key: key), min: o.min, max: o.max, upperLimit: nil, sources: []),
            overridden: true))
    }
    return out.sorted { nutrientKeyOrder($0.nutrientKey, $1.nutrientKey) }
}
