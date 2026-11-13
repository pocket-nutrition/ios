// SPDX-License-Identifier: MPL-2.0

import Foundation
import PocketNutritionCore

/// Reads the daily-targets view of the journal: the targets of a day, its progress, the person's own recent
/// days, the week and the trends. Every number comes from the cached reference table, the person's own data,
/// or the saved meals' nutrients; this type only routes them into Core's calculation.
@MainActor
struct TargetsReader {
    let journal: JournalStore
    let targets: TargetsStore
    let reference: ReferenceIntakesStore

    // MARK: - Days

    func meals(on day: String) -> [SavedMeal] {
        journal.meals.filter { localDay($0.savedAt) == day }.sorted { $0.savedAt < $1.savedAt }
    }

    func nutrients(on day: String) -> [MealNutrients] {
        meals(on: day).map { journalMealNutrients($0.record) }
    }

    func outcome(on day: String) -> DayTargetsOutcome {
        targetsForDay(
            table: reference.rows, profiles: targets.profiles, weights: targets.weightEntries,
            overrides: targets.overrides, day: day)
    }

    func progress(on day: String, keys: [String]) -> [NutrientProgress] {
        dayProgress(outcome(on: day).targets.map(\.progressTarget), meals: nutrients(on: day), keys: keys)
    }

    /// Today against the 7 days before, for a nutrient with no target.
    func comparison(for key: String, on day: String) -> SelfComparison {
        let history = (1...7).map { offset -> DayTotal in
            let previous = addDays(day, -offset)
            return DayTotal(date: previous, total: dayTotal(nutrients(on: previous), key: key))
        }
        return selfComparison(history, day: day, total: dayTotal(nutrients(on: day), key: key))
    }

    /// The meals that contributed most to `key` on `day`. Meals rather than single foods: a saved meal keeps
    /// its nutrients for the whole meal, not per food.
    func topContributors(for key: String, on day: String, limit: Int = 3) -> [(label: String, value: Double)] {
        meals(on: day)
            .compactMap { meal -> (String, Double)? in
                guard let value = journalMealNutrients(meal.record).nutrients[key], value > 0 else { return nil }
                return (meal.items.map(\.label).joined(separator: " · "), value)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { (label: $0.0, value: $0.1) }
    }

    // MARK: - Week and trends

    func week(ending day: String, keys: [String]) -> [WeekAverage] {
        let days = (0..<7).reversed().map { offset -> WeekDayInput in
            let d = addDays(day, -offset)
            let outcome = outcome(on: d)
            return WeekDayInput(day: d, targets: outcome == .none ? nil : outcome.targets, meals: nutrients(on: d))
        }
        return weekAverages(days, keys: keys)
    }

    struct TrendPoint: Identifiable {
        var day: String
        var date: Date
        var total: Double?
        /// The day's reference (min, else max), nil without a target.
        var target: Double?
        var id: String { day }
    }

    func trend(for key: String, days: Int, ending day: String) -> [TrendPoint] {
        (0..<days).reversed().map { offset in
            let d = addDays(day, -offset)
            let target = outcome(on: d).targets.first { $0.nutrientKey == key }
            return TrendPoint(
                day: d, date: Self.date(of: d), total: dayTotal(nutrients(on: d), key: key),
                target: target.flatMap { $0.min ?? $0.max })
        }
    }

    // MARK: - Explanation

    /// The EFSA basis of each computed target on `day`, for the explanation screen.
    func bases(on day: String) -> [String: TargetBasis] {
        guard let table = reference.rows,
              let profile = profileForDay(targets.profiles, weights: targets.weightEntries, day: day)
        else { return [:] }
        return dailyTargetBases(table, profile: profile)
    }

    /// The EFSA targets of `day` before any override, so an overridden value can show what it replaced.
    func computedTargets(on day: String) -> [String: NutrientTarget] {
        guard let table = reference.rows,
              let profile = profileForDay(targets.profiles, weights: targets.weightEntries, day: day),
              case .ok(let list) = dailyTargets(table, profile: profile)
        else { return [:] }
        return Dictionary(list.map { ($0.nutrientKey, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func date(of day: String) -> Date {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? Date()
    }
}

// MARK: - Display

/// How nutrients read on screen: names, groups, units, salt.
enum NutrientDisplay {

    /// The day detail's groups, covering every key of `NutrientTotals.keys` once.
    static func groups(_ s: any AppStrings) -> [(title: String, keys: [String])] {
        [
            (s.groupMacros, ["energyKcal", "proteinG", "carbohydratesG", "sugarsG", "fiberG", "fatG", "waterG"]),
            (s.groupFats, ["saturatedFatG", "monounsaturatedFatG", "polyunsaturatedFatG", "cholesterolMg"]),
            (s.groupMinerals, ["calciumMg", "ironMg", "magnesiumMg", "sodiumMg", "potassiumMg", "phosphorusMg", "zincMg"]),
            (s.groupVitamins, ["vitaminAUg", "vitaminCMg", "vitaminDUg", "vitaminB6Mg", "vitaminB12Ug", "niacinMg"]),
        ]
    }

    /// Vitamin D and B12 read better over a week (spec 05 §6).
    static let weeklyKeys: Set<String> = ["vitaminDUg", "vitaminB12Ug"]

    /// Rings and labels show salt for the sodium key.
    static func isSalt(_ key: String) -> Bool { key == "sodiumMg" }

    /// The ring label: salt for sodium, else the nutrient name.
    static func ringName(_ key: String, _ s: any AppStrings) -> String {
        isSalt(key) ? s.saltName : s.nutrientName(key)
    }

    /// A value in the key's own unit, "62 g", "11.7 mg".
    static func format(_ value: Double, unit: TargetUnit, lang: String) -> String {
        "\(formatNumber(roundTargetValue(value, unit: unit), lang: lang)) \(unit.rawValue)"
    }

    /// As the rings show it: sodium becomes salt in grams, one decimal.
    static func formatForRing(_ value: Double, key: String, unit: TargetUnit, lang: String) -> String {
        guard isSalt(key) else { return format(value, unit: unit, lang: lang) }
        let salt = Double(roundHalfUp(saltGrams(sodiumMg: value) * 10)) / 10
        return "\(formatNumber(salt, lang: lang)) g"
    }

    /// The kind of a target: goal (min only), limit (max only), range or point.
    static func kind(_ target: DayTarget?, _ s: any AppStrings) -> String {
        guard let target else { return s.targetKindNone }
        switch (target.min, target.max) {
        case (nil, nil): return s.targetKindNone
        case (_?, nil): return s.targetKindGoal
        case (nil, _?): return s.targetKindLimit
        case (let lo?, let hi?): return lo == hi ? s.targetKindGoal : s.targetKindRange
        }
    }

    static func isLimit(_ target: DayTarget?) -> Bool { target?.min == nil && target?.max != nil }

    /// "2,200 kcal", "45–60 g", "≤ 50 g".
    static func targetText(_ target: DayTarget, lang: String) -> String {
        let f = { (v: Double) in format(v, unit: target.unit, lang: lang) }
        switch (target.min, target.max) {
        case (let lo?, let hi?) where lo == hi: return f(lo)
        case (let lo?, let hi?):
            return "\(formatNumber(roundTargetValue(lo, unit: target.unit), lang: lang))–\(f(hi))"
        case (let lo?, nil): return "≥ \(f(lo))"
        case (nil, let hi?): return "≤ \(f(hi))"
        case (nil, nil): return "—"
        }
    }
}
