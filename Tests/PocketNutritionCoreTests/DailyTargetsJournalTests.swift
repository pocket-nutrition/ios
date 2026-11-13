// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

import PocketNutritionCore

/// The journal glue around the vector-tested calculation, including the logic behind spec 05 §8's
/// simulator checks. The reference rows are built here as test fixtures, never shipped.
@Suite("daily targets in the journal")
struct DailyTargetsJournalTests {

    private func row(
        _ key: String, kind: String, min: Double, unit: String, pal: Double? = nil, link: String = "efsa/x"
    ) -> ReferenceRow {
        ReferenceRow(
            nutrient: key, nutrientKey: key, population: "Adults", populationDescription: "Adults", ageFrom: 18,
            ageTo: 999, ageUnit: "y", pal: pal, isMale: true, isFemale: true, valueKind: kind, valueMin: min,
            valueMax: min, isIncrement: false, unit: unit, sourceLink: link)
    }

    private var table: [ReferenceRow] {
        [
            row("energyKcal", kind: "ar_kcal", min: 2500, unit: "kcal/day", pal: 1.6),
            row("proteinG", kind: "pri", min: 0.83, unit: "g/kg bw per day"),
            row("ironMg", kind: "pri", min: 11, unit: "mg/day"),
        ]
    }

    private let profiles = [
        ProfileVersion(effectiveFrom: "2026-11-01", birthYear: 1990, basis: .male, situation: .none, pal: 1.6, weightKg: 80)
    ]

    private func protein(_ outcome: DayTargetsOutcome) -> Double? {
        outcome.targets.first { $0.nutrientKey == "proteinG" }?.min
    }

    @Test("logging a weight today changes today's protein target and not yesterday's")
    func weightChangesTodayOnly() {
        let before = targetsForDay(table: table, profiles: profiles, weights: [], overrides: [], day: "2026-11-05")
        let weights = [WeightEntry(date: "2026-11-06", kg: 70)]
        let yesterday = targetsForDay(table: table, profiles: profiles, weights: weights, overrides: [], day: "2026-11-05")
        let today = targetsForDay(table: table, profiles: profiles, weights: weights, overrides: [], day: "2026-11-06")
        #expect(protein(before) == 66)  // 0.83 x 80 = 66.4
        #expect(protein(yesterday) == 66)
        #expect(protein(today) == 58)  // 0.83 x 70 = 58.1
    }

    @Test("no profile and no override: no target; overrides alone give targets; no table: needs a connection")
    func outcomes() {
        #expect(targetsForDay(table: table, profiles: [], weights: [], overrides: [], day: "2026-11-06") == .none)
        let overrides = [OverrideVersion(effectiveFrom: "2026-11-06", values: ["sugarsG": TargetOverride(min: nil, max: 50)])]
        let skipped = targetsForDay(table: nil, profiles: [], weights: [], overrides: overrides, day: "2026-11-06")
        #expect(skipped.targets.map(\.nutrientKey) == ["sugarsG"])
        #expect(targetsForDay(table: nil, profiles: profiles, weights: [], overrides: [], day: "2026-11-06") == .needsTable)
        #expect(targetsForDay(table: table, profiles: profiles, weights: [], overrides: [], day: "2026-10-31") == .none)
    }

    @Test("an energy override is flagged as overridden and keeps its EFSA source")
    func energyOverride() {
        let overrides = [OverrideVersion(effectiveFrom: "2026-11-06", values: ["energyKcal": TargetOverride(min: 2200, max: 2200)])]
        let energy = targetsForDay(table: table, profiles: profiles, weights: [], overrides: overrides, day: "2026-11-06")
            .targets.first { $0.nutrientKey == "energyKcal" }
        #expect(energy?.overridden == true && energy?.min == 2200 && energy?.sources == ["efsa/x"])
    }

    @Test("a meal without iron shows iron coverage 1 of 2")
    func ironCoverage() {
        let withIron = MealRecordPayload(
            id: "a", savedAt: 1, updatedAt: 1, items: [], totals: .init(energyKcal: 500, proteinG: 20, carbohydratesG: 50, fatG: 10),
            nutrients: NutrientTotals(["energyKcal": 500, "ironMg": 3.2]))
        let withoutIron = MealRecordPayload(
            id: "b", savedAt: 1, updatedAt: 1, items: [], totals: .init(energyKcal: 400, proteinG: 15, carbohydratesG: 40, fatG: 8))
        let meals = [withIron, withoutIron].map(journalMealNutrients)
        let targets = targetsForDay(table: table, profiles: profiles, weights: [], overrides: [], day: "2026-11-06").targets
        let iron = dayProgress(targets.map(\.progressTarget), meals: meals, keys: ["ironMg"])[0]
        #expect(iron.knownMeals == 1 && iron.totalMeals == 2 && iron.total == 3.2)
    }

    @Test("a v1 meal gives its four totals, a quick-add meal energy only")
    func mealNutrientSources() {
        let v1 = MealRecordPayload(
            id: "a", savedAt: 1, updatedAt: 1,
            items: [.init(id: "i", ingredientId: "apple", label: "apple", quantityG: 100, cookingMethod: "raw", measuredState: "raw")],
            totals: .init(energyKcal: 52, proteinG: 0.3, carbohydratesG: 14, fatG: 0.2))
        #expect(Set(journalMealNutrients(v1).nutrients.keys) == ["energyKcal", "proteinG", "carbohydratesG", "fatG"])
        let quick = MealRecordPayload(
            id: "b", savedAt: 1, updatedAt: 1,
            items: [.init(id: "i", ingredientId: nil, label: "snack", quantityG: 0, cookingMethod: "", measuredState: "", energyKcal: 150)],
            totals: .init(energyKcal: 150, proteinG: 0, carbohydratesG: 0, fatG: 0))
        #expect(journalMealNutrients(quick).nutrients == ["energyKcal": 150])
    }

    @Test("week averages use each day's own target and skip unknown days for the total")
    func weekAverage() {
        let t1 = [DayTarget(NutrientTarget(nutrientKey: "proteinG", unit: .g, min: 50, max: nil, upperLimit: nil, sources: []), overridden: false)]
        let t2 = [DayTarget(NutrientTarget(nutrientKey: "proteinG", unit: .g, min: 100, max: nil, upperLimit: nil, sources: []), overridden: false)]
        let days = [
            WeekDayInput(day: "2026-11-01", targets: t1, meals: [MealNutrients(["proteinG": 50])]),
            WeekDayInput(day: "2026-11-02", targets: t2, meals: [MealNutrients(["proteinG": 50])]),
            WeekDayInput(day: "2026-11-03", targets: nil, meals: []),
        ]
        let avg = weekAverages(days, keys: ["proteinG"])[0]
        #expect(avg.averageTotal == 50 && avg.daysWithData == 2)
        #expect(avg.averagePercent == 75 && avg.daysWithTarget == 2)
    }

    @Test("presets list keys in the spec's order; everything is every journal key")
    func presets() {
        #expect(WatchListPreset.standard.keys == ["energyKcal", "proteinG", "carbohydratesG", "fatG", "fiberG", "sugarsG"])
        #expect(WatchListPreset.everything.keys == NutrientTotals.keys)
        #expect(WatchListPreset.allCases.filter(\.isMedical) == [.kidney, .hypertension, .diabetes])
        #expect(saltGrams(sodiumMg: 2000) == 5)
    }

    @Test("each target reports the EFSA value kind and age band it came from")
    func bases() throws {
        let profile = try #require(profileForDay(profiles, weights: [], day: "2026-11-06"))
        let bases = dailyTargetBases(table, profile: profile)
        #expect(bases["energyKcal"]?.kinds == ["ar_kcal"])
        #expect(bases["ironMg"]?.kinds == ["pri"])
        #expect(bases["ironMg"]?.ageBands == [AgeBand(from: 18, to: 999)])
    }

    @Test("calendar days move across month and year ends")
    func days() {
        #expect(addDays("2026-03-01", -1) == "2026-02-28")
        #expect(addDays("2026-12-31", 1) == "2027-01-01")
    }
}
