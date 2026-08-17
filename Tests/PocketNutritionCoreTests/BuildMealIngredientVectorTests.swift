// SPDX-License-Identifier: MPL-2.0

import Testing
import PocketNutritionCore

/// Asserts `buildMealIngredient` against the `build-meal-ingredient` suite.
///
/// Three of the eleven cases expect `null`, and those are the point of the suite rather than edge-case
/// padding: the rule being pinned is that the client refuses to invent food data. A port that returned
/// a row with a guessed weight would pass the eight positive cases and fail exactly these three.
@Suite("build-meal-ingredient vectors")
struct BuildMealIngredientVectorTests {

    @Test("every build-meal-ingredient vector holds")
    func everyVectorHolds() throws {
        let suite = try VectorCorpus.load("build-meal-ingredient")
        #expect(
            suite.cases.count == (try VectorCorpus.index().suites["build-meal-ingredient"]),
            "case count disagrees with index.json"
        )

        var failures: [String] = []
        for testCase in suite.cases {
            guard let rawItem = testCase.input["item"] else {
                failures.append("\(testCase.id): input has no item")
                continue
            }
            let item = try SuggestionDecoding.decode(rawItem, as: AddItem.self)
            // The id is asserted by no case here, so any stable value serves. Deliberately not a
            // timestamp: the vectors exclude id precisely because the sandbox's embeds one.
            let actual = buildMealIngredient(item, id: "test-\(testCase.id)")

            if SuggestionDecoding.isNull(testCase.expected) {
                if let actual {
                    failures.append(
                        "\(testCase.id): expected nil, built \(actual.quantity)\(actual.unit) — \(testCase.why)"
                    )
                }
                continue
            }

            guard let actual else {
                failures.append("\(testCase.id): expected a row, got nil — \(testCase.why)")
                continue
            }
            let expected = try SuggestionDecoding.decode(testCase.expected, as: ComparableRow.self)
            let produced = ComparableRow(actual)
            if produced != expected {
                failures.append("\(testCase.id): \(produced) != \(expected) — \(testCase.why)")
            }
        }
        #expect(failures == [], "build-meal-ingredient vectors that do not hold")
    }

    /// The nil returns are a refusal to guess, and each has a distinct cause. Named individually so a
    /// port that collapses them into one early return still fails on the ones it no longer reaches.
    @Test("each refusal has its own cause")
    func eachRefusalHasItsOwnCause() {
        let base = IngredientSuggestion(
            ingredientId: "x", label: "x", lang: "fr",
            servingG: 80, displayUnit: "g", typicalState: "raw", portionMeasuredState: "raw"
        )

        // A generic "cooked" says the food is eaten cooked without saying how.
        #expect(cookingMethodFor("cooked") == nil)
        // "processed" means eaten as sold — no cooking transform, which is what raw encodes.
        #expect(cookingMethodFor("processed") == "raw")
        // An unrecognised state is refused rather than passed through as a method.
        #expect(cookingMethodFor("fermented") == nil)
        #expect(cookingMethodFor(nil) == nil)
        // All six that already are cooking methods pass through unchanged.
        for method in ["raw", "boiled", "steamed", "grilled", "roasted", "fried"] {
            #expect(cookingMethodFor(method) == method, "\(method) should pass through")
        }

        // No servingG: no anchor for the portion controls, so no row.
        var suggestion = IngredientSuggestion(
            ingredientId: "x", label: "x", lang: "fr", servingG: nil, typicalState: "raw"
        )
        #expect(buildMealIngredient(AddItem(suggestion: suggestion), id: "i") == nil)

        // A cooked row with no portionMeasuredState cannot know whether to apply the yield.
        suggestion = IngredientSuggestion(
            ingredientId: "x", label: "x", lang: "fr",
            servingG: 80, typicalState: "grilled", portionMeasuredState: nil
        )
        #expect(buildMealIngredient(AddItem(suggestion: suggestion), id: "i") == nil)

        // ...but an explicit quantity override removes the question: a recipe weight is pre-cooking
        // by definition, so the same suggestion now builds.
        #expect(
            buildMealIngredient(
                AddItem(suggestion: suggestion, cookingMethod: "grilled", quantityG: 200), id: "i"
            ) != nil
        )

        // A raw row needs no portionMeasuredState at all — nothing is being converted.
        #expect(buildMealIngredient(AddItem(suggestion: base), id: "i") != nil)
    }

    /// A gram override beats a millilitre display unit. Both are plausible readings of the same row and
    /// the suite has a case for it; asserted here too because getting it backwards silently relabels a
    /// weight as a volume.
    @Test("a gram override defeats a millilitre display unit")
    func gramOverrideDefeatsMillilitres() throws {
        let milk = IngredientSuggestion(
            ingredientId: "milk", label: "lait", lang: "fr",
            servingG: 200, displayUnit: "ml", typicalState: "raw", portionMeasuredState: "raw",
            servingUnits: [ServingUnit(unit: "glass", labelFr: "verre", volumeMl: 200, grams: 206)]
        )

        let byVolume = try #require(buildMealIngredient(AddItem(suggestion: milk), id: "i"))
        #expect(byVolume.unit == "ml")
        #expect(byVolume.selectedUnit != nil, "a millilitre row selects its first serving unit")

        let byWeight = try #require(
            buildMealIngredient(AddItem(suggestion: milk, quantityG: 150), id: "i")
        )
        #expect(byWeight.unit == "g")
        #expect(byWeight.quantity == 150)
        #expect(byWeight.selectedUnit == nil, "a gram row selects no serving unit")
    }
}
