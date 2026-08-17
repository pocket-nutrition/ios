// SPDX-License-Identifier: MPL-2.0

import Testing

import PocketNutritionCore

/// Asserts `stepLabel` against the `step-label` suite of the shared corpus.
///
/// One case in this suite is load-bearing beyond its own assertion: `unit-count-two-pluralises`
/// exists, in the corpus author's words, to tie this suite to the plural rule "not by a second copy
/// of the logic living here". If someone inlines an `if count > 1` here, that case still passes —
/// which is why the delegation is asserted separately below.
@Suite("step-label vectors")
struct StepLabelVectorTests {

    @Test("every case in the step-label suite holds")
    func stepLabelSuiteHoldsForEveryCase() throws {
        let suite = try VectorCorpus.load("step-label")

        let declared = try VectorCorpus.index().suites["step-label"]
        #expect(suite.cases.count == declared, "step-label case count disagrees with index.json")
        #expect(!suite.cases.isEmpty, "the step-label suite is empty")

        var mismatches: [String] = []
        for testCase in suite.cases {
            guard let rawStep = testCase.input["step"] as? [String: Any],
                  let step = ScaleStepDecoding.step(rawStep)
            else {
                mismatches.append("step-label/\(testCase.id): input.step is malformed")
                continue
            }
            guard let expected = testCase.expected as? String else {
                mismatches.append("step-label/\(testCase.id): expected is not a string")
                continue
            }
            let actual = stepLabel(step)
            if actual != expected {
                mismatches.append(
                    "step-label/\(testCase.id): got \"\(actual)\", expected \"\(expected)\" "
                        + "— \(testCase.why)"
                )
            }
        }

        #expect(mismatches == [], "step-label vectors that do not hold")
    }

    /// A factor step is returned verbatim, whatever it says. Asserted with a label the function could
    /// not have produced, so a port that rebuilds the label instead of passing it through fails here
    /// rather than passing by coincidence.
    @Test("a factor step's label is passed through untouched")
    func factorLabelsArePassedThrough() {
        #expect(stepLabel(.factor(factor: 0.5, label: "Petite")) == "Petite")
        #expect(stepLabel(.factor(factor: 1, label: "n'importe quoi")) == "n'importe quoi")
    }

    /// The plural threshold in the label must be the French one — singular below 2. An inlined
    /// English rule would render "1,5 carottes" and every corpus case would still pass, because the
    /// suite has no fractional-count-above-one case.
    @Test("pluralisation follows the French rule, not an inlined English one")
    func pluralisationIsDelegatedToTheFrenchRule() {
        let carrot = ServingUnit(unit: "item", labelFr: "carotte", volumeMl: 0, grams: 74)
        #expect(stepLabel(.unit(unit: carrot, count: 1.5)) == "1,5 carotte")
        #expect(stepLabel(.unit(unit: carrot, count: 2.5)) == "2,5 carottes")
    }

    /// Every fraction the contract names, including the two the vectors do not reach.
    @Test(
        "the fraction table covers the counts the contract names",
        arguments: [(0.25, "¼"), (0.33, "⅓"), (0.5, "½"), (0.75, "¾")]
    )
    func fractionTableIsComplete(count: Double, glyph: String) {
        let carrot = ServingUnit(unit: "item", labelFr: "carotte", volumeMl: 0, grams: 74)
        #expect(stepLabel(.unit(unit: carrot, count: count)) == "\(glyph) carotte")
    }
}
