// SPDX-License-Identifier: MPL-2.0

import Foundation

// How far a day has got toward its targets, for the watch-list rings, and how today compares with the
// person's own recent days for nutrients that have no target. Port of the sandbox's `dayProgress.ts`, held to
// the `day-progress` and `self-comparison` suites. Unknown values are never counted as zero: a meal without a
// figure for a nutrient lowers the coverage instead.

/// The target fields progress reads.
public struct ProgressTarget: Codable, Equatable, Sendable {
    public var nutrientKey: String
    public var unit: TargetUnit
    public var min: Double?
    public var max: Double?
    public var upperLimit: Double?

    public init(nutrientKey: String, unit: TargetUnit, min: Double?, max: Double?, upperLimit: Double?) {
        self.nutrientKey = nutrientKey
        self.unit = unit
        self.min = min
        self.max = max
        self.upperLimit = upperLimit
    }
}

/// One meal's nutrients, keyed like `NutritionalProfileResponse`; an absent key means unknown.
public struct MealNutrients: Codable, Equatable, Sendable {
    public var nutrients: [String: Double]

    public init(_ nutrients: [String: Double]) {
        self.nutrients = nutrients
    }
}

public enum ProgressStatus: String, Codable, Sendable {
    case noTarget = "no-target"
    case under, ok, over
}

public struct NutrientProgress: Codable, Equatable, Sendable {
    public var nutrientKey: String
    public var unit: TargetUnit
    /// Sum of the known values, rounded like targets; nil when no meal knows it.
    public var total: Double?
    /// Meals that have a value for this nutrient, out of `totalMeals`.
    public var knownMeals: Int
    public var totalMeals: Int
    /// Known total / reference x 100, rounded half-up; reference is min, else max. Nil without a target.
    public var percent: Int?
    public var status: ProgressStatus
    /// The known total exceeds EFSA's tolerable upper intake level.
    public var aboveUpperLimit: Bool

    public var isFullyCovered: Bool { knownMeals == totalMeals }
}

/// Progress of the day's `meals` for each nutrient of `keys`, in that order.
///
/// Status, computed on the unrounded known total t (0 when no meal knows the nutrient): no min and no max ->
/// no-target; t < min -> under; max set and t > max -> over; otherwise ok. So a goal (min only) is never over,
/// a limit (max only) is never under, and a point target such as energy (min = max) is ok only when hit
/// exactly or between the bounds.
public func dayProgress(_ targets: [ProgressTarget], meals: [MealNutrients], keys: [String]) -> [NutrientProgress] {
    var byKey: [String: ProgressTarget] = [:]
    for target in targets { byKey[target.nutrientKey] = target }
    return keys.map { key in
        let target = byKey[key]
        let unit = target?.unit ?? TargetUnit(key: key)
        let known = meals.compactMap { $0.nutrients[key] }
        let sum = known.reduce(0, +)
        let t = known.isEmpty ? 0 : sum
        let min = target?.min
        let max = target?.max
        let reference = min ?? max

        let status: ProgressStatus
        if min == nil && max == nil {
            status = .noTarget
        } else if let min, t < min {
            status = .under
        } else if let max, t > max {
            status = .over
        } else {
            status = .ok
        }

        var percent: Int?
        if let reference, reference > 0 { percent = roundHalfUp((t / reference) * 100) }
        return NutrientProgress(
            nutrientKey: key, unit: unit, total: known.isEmpty ? nil : roundTargetValue(sum, unit: unit),
            knownMeals: known.count, totalMeals: meals.count, percent: percent, status: status,
            aboveUpperLimit: target?.upperLimit.map { t > $0 } ?? false)
    }
}

public struct DayTotal: Codable, Equatable, Sendable {
    public var date: String
    /// The day's known total for the nutrient; nil when the day has no value for it.
    public var total: Double?

    public init(date: String, total: Double?) {
        self.date = date
        self.total = total
    }
}

public struct SelfComparison: Codable, Equatable, Sendable {
    /// Mean of the previous 7 calendar days that have a value, one decimal; nil when none has.
    public var average: Double?
    public var daysWithData: Int
    /// Today's total / average x 100, rounded half-up; nil when either is missing or the average is 0.
    public var percentOfAverage: Int?
}

/// Today against the person's own recent days, for a nutrient with no target (salt, sugars, saturated fat by
/// default). The window is the 7 calendar days before `day`, excluding `day`; days with no value are skipped,
/// not counted as zero.
public func selfComparison(_ history: [DayTotal], day: String, total: Double?) -> SelfComparison {
    let from = addDays(day, -7)
    let values = history.filter { $0.date >= from && $0.date < day }.compactMap(\.total)
    guard !values.isEmpty else { return SelfComparison(average: nil, daysWithData: 0, percentOfAverage: nil) }
    let mean = values.reduce(0, +) / Double(values.count)
    var percent: Int?
    if let total, mean > 0 { percent = roundHalfUp((total / mean) * 100) }
    return SelfComparison(
        average: Double(roundHalfUp(mean * 10)) / 10, daysWithData: values.count, percentOfAverage: percent)
}
