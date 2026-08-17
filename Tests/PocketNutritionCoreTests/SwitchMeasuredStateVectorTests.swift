// SPDX-License-Identifier: MPL-2.0

import Testing
import PocketNutritionCore

/// Asserts `switchMeasuredState` against the `switch-measured-state` suite.
///
/// The suite exists because this conversion is the one that can be wrong by 15–40% while every screen
/// still looks right, and because it spent its whole life inline in a React component where no test
/// could reach it. The case worth knowing about is `to-cooked-hits-a-rounding-tie`: 50 × 0.85 = 42.5,
/// where the corpus rule gives 43 and `rounded(.toNearestOrEven)` gives 42.
@Suite("switch-measured-state vectors")
struct SwitchMeasuredStateVectorTests {

    @Test("every switch-measured-state vector holds")
    func everyVectorHolds() throws {
        let suite = try VectorCorpus.load("switch-measured-state")
        #expect(
            suite.cases.count == (try VectorCorpus.index().suites["switch-measured-state"]),
            "case count disagrees with index.json"
        )

        var failures: [String] = []
        for testCase in suite.cases {
            guard let rawIngredient = testCase.input["ingredient"] else {
                failures.append("\(testCase.id): input has no ingredient")
                continue
            }
            guard let state = testCase.input["to"] as? String else {
                failures.append("\(testCase.id): input has no `to`")
                continue
            }
            let ingredient = try SuggestionDecoding.decode(rawIngredient, as: MealIngredient.self)
            let expected = try SuggestionDecoding.decode(testCase.expected, as: MealIngredient.self)
            let actual = switchMeasuredState(ingredient, to: state)
            if actual != expected {
                failures.append(
                    """
                    \(testCase.id): \(actual.measuredState)/\(actual.quantity) \
                    != \(expected.measuredState)/\(expected.quantity) — \(testCase.why)
                    """
                )
            }
        }
        #expect(failures == [], "switch-measured-state vectors that do not hold")
    }

    /// Flipping twice must land on the number the user started from. Not a vector, because the corpus
    /// pins single calls and this is a property of composing two — and it is the property a user
    /// actually exercises, by pressing the wrong button and pressing the other one.
    @Test("the toggle round-trips")
    func toggleRoundTrips() {
        let raw = MealIngredient(
            id: "row-1", label: "poulet", ingredientId: "chicken",
            cookingMethod: "grilled", quantity: 100, unit: "g", measuredState: "raw",
            basePortionG: 100, portionFactor: 0, servingUnits: [], selectedUnit: nil,
            unitCount: 1, displayUnit: "g", canEatRaw: false,
            yieldFactors: ["grilled": 0.7], imageUrl: nil, servingMode: "weight"
        )

        let cooked = switchMeasuredState(raw, to: "cooked")
        let backToRaw = switchMeasuredState(cooked, to: "raw")

        #expect(cooked.quantity == 70, "100 g raw at yield 0.7 is 70 g cooked")
        #expect(backToRaw.quantity == 100, "the round trip must return the original weight")
        #expect(raw.quantity == 100, "the caller's row was mutated")
    }
}
