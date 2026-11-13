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

    /// Covers both `step-label` (French, no `lang` field — defaults to "fr") and `step-label-en`
    /// (English, `lang: "en"` in every fixture).
    @Test("every case in the step-label and step-label-en suites holds", arguments: ["step-label", "step-label-en"])
    func stepLabelSuiteHoldsForEveryCase(suiteName: String) throws {
        let suite = try VectorCorpus.load(suiteName)

        let declared = try VectorCorpus.index().suites[suiteName]
        #expect(suite.cases.count == declared, "\(suiteName) case count disagrees with index.json")
        #expect(!suite.cases.isEmpty, "the \(suiteName) suite is empty")

        var mismatches: [String] = []
        for testCase in suite.cases {
            guard let rawStep = testCase.input["step"] as? [String: Any],
                  let step = ScaleStepDecoding.step(rawStep)
            else {
                mismatches.append("\(suiteName)/\(testCase.id): input.step is malformed")
                continue
            }
            guard let expected = testCase.expected as? String else {
                mismatches.append("\(suiteName)/\(testCase.id): expected is not a string")
                continue
            }
            let lang = testCase.input["lang"] as? String ?? "fr"
            let actual = stepLabel(step, lang: lang)
            if actual != expected {
                mismatches.append(
                    "\(suiteName)/\(testCase.id): got \"\(actual)\", expected \"\(expected)\" "
                        + "— \(testCase.why)"
                )
            }
        }

        #expect(mismatches == [], "\(suiteName) vectors that do not hold")
    }

    /// A factor step is returned verbatim, whatever it says. Asserted with a label the function could
    /// not have produced, so a port that rebuilds the label instead of passing it through fails here
    /// rather than passing by coincidence.
    @Test("a factor step's label is passed through untouched")
    func factorLabelsArePassedThrough() {
        #expect(stepLabel(.factor(factor: 0.5, label: "Petite"), lang: "fr") == "Petite")
        #expect(stepLabel(.factor(factor: 1, label: "n'importe quoi"), lang: "fr") == "n'importe quoi")
    }

    /// The plural threshold in the label must be the French one — singular below 2. An inlined
    /// English rule would render "1,5 carottes" and every corpus case would still pass, because the
    /// suite has no fractional-count-above-one case.
    @Test("pluralisation follows the French rule, not an inlined English one")
    func pluralisationIsDelegatedToTheFrenchRule() {
        let carrot = ServingUnit(unit: "item", labels: [LocalizedText(lang: "fr", text: "carotte")], volumeMl: 0, grams: 74)
        #expect(stepLabel(.unit(unit: carrot, count: 1.5), lang: "fr") == "1,5 carotte")
        #expect(stepLabel(.unit(unit: carrot, count: 2.5), lang: "fr") == "2,5 carottes")
    }

    /// The mirror check for English: the threshold is "anything but exactly 1", so 1.5 already
    /// pluralises, unlike French's "1,5 carotte".
    @Test("pluralisation follows the English rule when lang is en")
    func pluralisationFollowsTheEnglishRule() {
        let carrot = ServingUnit(unit: "item", labels: [LocalizedText(lang: "en", text: "carrot")], volumeMl: 0, grams: 74)
        #expect(stepLabel(.unit(unit: carrot, count: 1.5), lang: "en") == "1.5 carrots")
        #expect(stepLabel(.unit(unit: carrot, count: 1), lang: "en") == "1 carrot")
    }

    /// Every fraction the contract names, including the two the vectors do not reach.
    @Test(
        "the fraction table covers the counts the contract names",
        arguments: [(0.25, "¼"), (0.33, "⅓"), (0.5, "½"), (0.75, "¾")]
    )
    func fractionTableIsComplete(count: Double, glyph: String) {
        let carrot = ServingUnit(unit: "item", labels: [LocalizedText(lang: "fr", text: "carotte")], volumeMl: 0, grams: 74)
        #expect(stepLabel(.unit(unit: carrot, count: count), lang: "fr") == "\(glyph) carotte")
    }
}
