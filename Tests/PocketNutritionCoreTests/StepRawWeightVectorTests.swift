// SPDX-License-Identifier: MPL-2.0

import Testing

import PocketNutritionCore

/// Asserts `stepRawWeight` against the `step-raw-weight` suite of the shared corpus.
@Suite("step-raw-weight vectors")
struct StepRawWeightVectorTests {

    @Test("every case in the step-raw-weight suite holds")
    func stepRawWeightSuiteHoldsForEveryCase() throws {
        let suite = try VectorCorpus.load("step-raw-weight")

        let declared = try VectorCorpus.index().suites["step-raw-weight"]
        #expect(suite.cases.count == declared, "step-raw-weight case count disagrees with index.json")
        #expect(!suite.cases.isEmpty, "the step-raw-weight suite is empty")

        var mismatches: [String] = []
        for testCase in suite.cases {
            guard let rawStep = testCase.input["step"] as? [String: Any],
                  let step = ScaleStepDecoding.step(rawStep)
            else {
                mismatches.append("step-raw-weight/\(testCase.id): input.step is malformed")
                continue
            }
            guard let basePortion = VectorCorpus.double(testCase.input["basePortionG"]),
                  let expected = VectorCorpus.double(testCase.expected)
            else {
                mismatches.append("step-raw-weight/\(testCase.id): a number is missing")
                continue
            }
            let actual = stepRawWeight(step, basePortionG: basePortion)
            if actual != expected {
                mismatches.append(
                    "step-raw-weight/\(testCase.id): got \(actual), expected \(expected) "
                        + "— \(testCase.why)"
                )
            }
        }

        #expect(mismatches == [], "step-raw-weight vectors that do not hold")
    }

    /// The base portion must have no influence on a unit step. Asserted across three wildly different
    /// base portions, because the corpus passes 75 every time and a port that multiplied by the base
    /// would need only that one value changed to be caught.
    @Test("a unit step ignores the base portion entirely", arguments: [0.0, 75.0, 1000.0])
    func unitStepsIgnoreTheBasePortion(basePortionG: Double) {
        let carrot = ServingUnit(unit: "item", labelFr: "carotte", volumeMl: 0, grams: 74)
        #expect(stepRawWeight(.unit(unit: carrot, count: 2), basePortionG: basePortionG) == 148)
    }

    /// Nothing is rounded here. The corpus says so in its description and pins it with 37.5; rounding
    /// in the middle of a chain is how a total stops matching the sum of its rows.
    @Test("a factor step is not rounded")
    func factorStepsAreNotRounded() {
        #expect(stepRawWeight(.factor(factor: 0.5, label: "½"), basePortionG: 75) == 37.5)
        #expect(stepRawWeight(.factor(factor: 0.25, label: "¼"), basePortionG: 10) == 2.5)
    }
}
