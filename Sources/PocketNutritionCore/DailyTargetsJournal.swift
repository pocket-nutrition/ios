// SPDX-License-Identifier: MPL-2.0

import Foundation

// How the journal uses the daily-targets calculation (spec 05 §2, §5, §6): the targets in force on a day,
// what a saved meal contributes, week averages, the watch-list presets and the salt display. Everything here
// is arithmetic on data that came from the API or from the person; nothing embeds a nutrition value.

// MARK: - Targets for a day

/// What the targets of one day are, or why there are none.
public enum DayTargetsOutcome: Equatable, Sendable {
    /// No profile in force and no override: the day shows its totals only, exactly as before the feature.
    case none
    /// A profile is in force but the reference table has never been fetched (first launch offline).
    case needsTable
    /// The profile is outside what EFSA's table covers; any override still applies.
    case unsupported(UnsupportedTargetReason, overrides: [DayTarget])
    case targets([DayTarget])

    public var targets: [DayTarget] {
        switch self {
        case .none, .needsTable: []
        case .unsupported(_, let overrides): overrides
        case .targets(let targets): targets
        }
    }
}

/// The targets in force on `day` (spec 05 §2): the profile of that day, its EFSA targets, then the overrides
/// of that day. With no profile, the overrides alone ("Skip, I'll enter my own values").
public func targetsForDay(
    table: [ReferenceRow]?, profiles: [ProfileVersion], weights: [WeightEntry], overrides: [OverrideVersion],
    day: String
) -> DayTargetsOutcome {
    let overrideOnly = applyOverrides([], versions: overrides, day: day)
    guard let profile = profileForDay(profiles, weights: weights, day: day) else {
        return overrideOnly.isEmpty ? .none : .targets(overrideOnly)
    }
    guard let table else { return .needsTable }
    switch dailyTargets(table, profile: profile) {
    case .unsupported(let reason): return .unsupported(reason, overrides: overrideOnly)
    case .ok(let targets): return .targets(applyOverrides(targets, versions: overrides, day: day))
    }
}

// MARK: - What a meal contributes

/// A saved meal's nutrients for progress (spec 05 §2): its saved `nutrients` (record v2); for a v1 meal
/// without them, only its four macro totals; a meal made only of quick-add items contributes energy only.
/// Absent keys are unknown, never 0.
public func journalMealNutrients(_ meal: MealRecordPayload) -> MealNutrients {
    if let nutrients = meal.nutrients { return MealNutrients(nutrients.values) }
    let quickAdd = meal.items.compactMap { $0.ingredientId == nil ? $0.energyKcal : nil }
    if !meal.items.isEmpty && quickAdd.count == meal.items.count {
        return MealNutrients(["energyKcal": quickAdd.reduce(0, +)])
    }
    return MealNutrients([
        "energyKcal": meal.totals.energyKcal, "proteinG": meal.totals.proteinG,
        "carbohydratesG": meal.totals.carbohydratesG, "fatG": meal.totals.fatG,
    ])
}

/// The known total of `key` over `meals`, unrounded; nil when no meal knows it.
public func dayTotal(_ meals: [MealNutrients], key: String) -> Double? {
    let known = meals.compactMap { $0.nutrients[key] }
    return known.isEmpty ? nil : known.reduce(0, +)
}

// MARK: - Week

/// One day of a week view: its targets (nil when it had none) and its meals.
public struct WeekDayInput: Sendable {
    public var day: String
    public var targets: [DayTarget]?
    public var meals: [MealNutrients]

    public init(day: String, targets: [DayTarget]?, meals: [MealNutrients]) {
        self.day = day
        self.targets = targets
        self.meals = meals
    }
}

public struct WeekAverage: Equatable, Sendable {
    public var nutrientKey: String
    public var unit: TargetUnit
    /// Mean of the days that have a value, rounded like targets; nil when no day has one.
    public var averageTotal: Double?
    public var daysWithData: Int
    /// Mean of each day's total against that day's own target, rounded half-up; nil when no day had a target.
    public var averagePercent: Int?
    public var daysWithTarget: Int
}

/// The week's averages against the targets of each day (spec 05 §6). A day without a value is skipped for
/// the average total; for the percent, a day with a target and no value counts as 0 % of it, since a day
/// with meals but no figure for the nutrient is shown as unknown in the day view, not hidden.
public func weekAverages(_ days: [WeekDayInput], keys: [String]) -> [WeekAverage] {
    keys.map { key in
        var totals: [Double] = []
        var percents: [Double] = []
        var unit = TargetUnit(key: key)
        for day in days {
            let total = dayTotal(day.meals, key: key)
            if let total { totals.append(total) }
            guard let target = day.targets?.first(where: { $0.nutrientKey == key }) else { continue }
            unit = target.unit
            guard let reference = target.min ?? target.max, reference > 0, !day.meals.isEmpty else { continue }
            percents.append((total ?? 0) / reference * 100)
        }
        let mean = totals.isEmpty ? nil : totals.reduce(0, +) / Double(totals.count)
        return WeekAverage(
            nutrientKey: key, unit: unit, averageTotal: mean.map { roundTargetValue($0, unit: unit) },
            daysWithData: totals.count,
            averagePercent: percents.isEmpty ? nil : roundHalfUp(percents.reduce(0, +) / Double(percents.count)),
            daysWithTarget: percents.count)
    }
}

// MARK: - Watch list presets

/// The watch-list presets (spec 05 §5): nutrient keys only, never a value. Labelled as our choices.
public enum WatchListPreset: String, CaseIterable, Sendable {
    case standard, sport, kidney, hypertension, diabetes, everything

    /// The preset name stored once the keys were edited by hand.
    public static let custom = "custom"

    public var keys: [String] {
        switch self {
        case .standard: ["energyKcal", "proteinG", "carbohydratesG", "fatG", "fiberG", "sugarsG"]
        case .sport: ["energyKcal", "proteinG", "carbohydratesG", "fatG", "fiberG", "waterG"]
        case .kidney: ["energyKcal", "proteinG", "potassiumMg", "phosphorusMg", "sodiumMg"]
        case .hypertension: ["energyKcal", "sodiumMg", "potassiumMg", "saturatedFatG", "fiberG"]
        case .diabetes: ["energyKcal", "carbohydratesG", "sugarsG", "fiberG", "saturatedFatG"]
        case .everything: NutrientTotals.keys
        }
    }

    /// General-population values only: the screen asks for the care team's own targets.
    public var isMedical: Bool { self == .kidney || self == .hypertension || self == .diabetes }

    public var watchList: WatchList { WatchList(preset: rawValue, keys: keys) }
}

// MARK: - Salt

/// Salt as on food packaging, from the stored sodium: sodium mg x 2.5 / 1000 = salt g. Display arithmetic
/// only (spec 05 §6); the stored key stays `sodiumMg`.
public let saltPerSodium: Double = 2.5

public func saltGrams(sodiumMg: Double) -> Double { sodiumMg * saltPerSodium / 1000 }
