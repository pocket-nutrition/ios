// SPDX-License-Identifier: MPL-2.0

import Testing
import PocketNutritionCore

/// Asserts `applyMethodChange` against the `apply-method-change` suite.
///
/// The suite's own description says branch order "matters and is part of the contract". It does,
/// because the branches overlap: a row can have both a portion factor and a cooked weight, and the two
/// rules produce different numbers. `id` is supplied in this suite's input, so it is asserted too —
/// unlike `build-meal-ingredient`, nothing here is excluded.
@Suite("apply-method-change vectors")
struct ApplyMethodChangeVectorTests {

    @Test("every apply-method-change vector holds")
    func everyVectorHolds() throws {
        let suite = try VectorCorpus.load("apply-method-change")
        #expect(
            suite.cases.count == (try VectorCorpus.index().suites["apply-method-change"]),
            "case count disagrees with index.json"
        )

        var failures: [String] = []
        for testCase in suite.cases {
            guard let rawIngredient = testCase.input["ingredient"] else {
                failures.append("\(testCase.id): input has no ingredient")
                continue
            }
            guard let newMethod = testCase.input["newMethod"] as? String else {
                failures.append("\(testCase.id): input has no newMethod")
                continue
            }
            let ingredient = try SuggestionDecoding.decode(rawIngredient, as: MealIngredient.self)
            let expected = try SuggestionDecoding.decode(testCase.expected, as: MealIngredient.self)
            let actual = applyMethodChange(ingredient, to: newMethod)
            if actual != expected {
                failures.append(
                    """
                    \(testCase.id): \(actual.cookingMethod)/\(actual.measuredState)/\(actual.quantity) \
                    != \(expected.cookingMethod)/\(expected.measuredState)/\(expected.quantity) \
                    — \(testCase.why)
                    """
                )
            }
        }
        #expect(failures == [], "apply-method-change vectors that do not hold")
    }

    /// The caller's row must be untouched. `MealIngredient` uses `var` fields so the four branches can
    /// copy-and-replace instead of restating seventeen arguments; this is what proves that choice did
    /// not leak mutation into the caller.
    @Test("the input row is never mutated")
    func inputRowIsNeverMutated() {
        let original = MealIngredient(
            id: "row-1", label: "poulet", ingredientId: "chicken",
            cookingMethod: "grilled", quantity: 116, unit: "g", measuredState: "cooked",
            basePortionG: 100, portionFactor: 1, servingUnits: [], selectedUnit: nil,
            unitCount: 1, displayUnit: "g", canEatRaw: false,
            yieldFactors: ["cooked": 1.16, "roasted": 0.77], imageUrl: nil, servingMode: "weight"
        )

        let changed = applyMethodChange(original, to: "raw")

        #expect(original.cookingMethod == "grilled", "the caller's row changed method")
        #expect(original.measuredState == "cooked", "the caller's row changed measured state")
        #expect(original.quantity == 116, "the caller's row changed quantity")
        #expect(changed.cookingMethod == "raw")
        #expect(changed.id == original.id, "identity must survive a method change")
    }

    /// Branch 3 leaves `measuredState` alone: the weight was cooked before and is still cooked after,
    /// just cooked differently. Asserted by name because "fixing" it to `cooked` is a no-op today and
    /// would be a lie the moment branch 3 became reachable from a raw weight.
    @Test("a method swap on a cooked weight leaves the measured state alone")
    func methodSwapLeavesMeasuredStateAlone() {
        let row = MealIngredient(
            id: "row-1", label: "riz", ingredientId: "rice",
            cookingMethod: "boiled", quantity: 200, unit: "g", measuredState: "cooked",
            // portionFactor 0 so branch 2 cannot claim it — this is the branch-3 path.
            basePortionG: 80, portionFactor: 0, servingUnits: [], selectedUnit: nil,
            unitCount: 1, displayUnit: "g", canEatRaw: false,
            yieldFactors: ["boiled": 2.5, "steamed": 2.0], imageUrl: nil, servingMode: "weight"
        )

        let steamed = applyMethodChange(row, to: "steamed")

        #expect(steamed.measuredState == "cooked", "branch 3 must not rewrite measuredState")
        #expect(steamed.cookingMethod == "steamed")
        // 200 boiled -> 80 raw equivalent -> 160 steamed. Rounding lands once, at the end.
        #expect(steamed.quantity == 160)
    }

    /// `portionFactor > 0` rather than a truthiness test. A row where the user typed a weight directly
    /// carries 0, and treating that as "has a factor" would recompute from the base and silently
    /// discard what they typed.
    @Test("a zero portion factor does not recompute from the base")
    func zeroPortionFactorDoesNotRecompute() {
        let typed = MealIngredient(
            id: "row-1", label: "pomme de terre", ingredientId: "potato",
            cookingMethod: "raw", quantity: 237, unit: "g", measuredState: "raw",
            basePortionG: 80, portionFactor: 0, servingUnits: [], selectedUnit: nil,
            unitCount: 1, displayUnit: "g", canEatRaw: false,
            yieldFactors: ["boiled": 0.9], imageUrl: nil, servingMode: "weight"
        )

        // Target raw, raw weight, no factor: branch 1's final fallback keeps the quantity as typed.
        #expect(applyMethodChange(typed, to: "raw").quantity == 237)
        // Target cooked, no factor, weight already raw: branch 4, method only.
        let boiled = applyMethodChange(typed, to: "boiled")
        #expect(boiled.quantity == 237, "branch 4 must not touch the weight")
        #expect(boiled.measuredState == "raw")
        #expect(boiled.cookingMethod == "boiled")
    }
}
