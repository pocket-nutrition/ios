// SPDX-License-Identifier: MPL-2.0

import Testing

import PocketNutritionCore

/// Asserts `frenchPlural` against the `french-plural` suite of the shared corpus.
///
/// What the suite really pins is the boundary. An English-shaped rule — plural above one — passes four
/// of these six cases; only 1.5 and 2 tell the two rules apart. That is the whole reason both are in
/// the corpus, and the reason they are named again below.
@Suite("french-plural vectors")
struct FrenchPluralVectorTests {

    @Test("every case in the french-plural suite holds")
    func frenchPluralSuiteHoldsForEveryCase() throws {
        let suite = try VectorCorpus.load("french-plural")

        let declared = try VectorCorpus.index().suites["french-plural"]
        #expect(suite.cases.count == declared, "french-plural case count disagrees with index.json")
        #expect(!suite.cases.isEmpty, "the french-plural suite is empty")

        var mismatches: [String] = []
        for testCase in suite.cases {
            guard let label = testCase.input["label"] as? String else {
                mismatches.append("french-plural/\(testCase.id): input.label is not a string")
                continue
            }
            guard let count = VectorCorpus.double(testCase.input["count"]) else {
                mismatches.append("french-plural/\(testCase.id): input.count is not a number")
                continue
            }
            guard let expected = testCase.expected as? String else {
                mismatches.append("french-plural/\(testCase.id): expected is not a string")
                continue
            }
            let actual = frenchPlural(label, count: count)
            if actual != expected {
                mismatches.append(
                    "french-plural/\(testCase.id): (\"\(label)\", \(count)) -> \"\(actual)\", "
                        + "expected \"\(expected)\" — \(testCase.why)"
                )
            }
        }

        #expect(mismatches == [], "french-plural vectors that do not hold")
    }

    /// The French threshold is 2 and inclusive. An English rule pluralises above 1 and would differ on
    /// exactly one of these two inputs, so they are asserted as a pair rather than separately.
    @Test("the singular holds below two, not below one")
    func theThresholdIsTwoAndInclusive() {
        #expect(frenchPlural("carotte", count: 1.5) == "carotte")
        #expect(frenchPlural("carotte", count: 2) == "carottes")
    }

    /// An invariable word must not gain a second s. Cheap to get wrong, and the result — "ananass" —
    /// is the kind of thing that ships.
    @Test("a word already ending in s is left alone")
    func wordsEndingInSAreLeftAlone() {
        #expect(frenchPlural("ananas", count: 3) == "ananas")
    }
}
