// SPDX-License-Identifier: MPL-2.0

import Testing

import PocketNutritionCore

/// Asserts `englishPlural` against the `english-plural` suite of the shared corpus — the mirror of
/// `FrenchPluralVectorTests`, added in contract 2.0.0.
///
/// What this suite really pins is the same boundary `french-plural` pins, from the other side: a
/// French-shaped rule (singular below 2) passes only the "exactly 1" and "already ends in s" cases
/// here; 1.5 and 0.5 are what tell the two rules apart.
@Suite("english-plural vectors")
struct EnglishPluralVectorTests {

    @Test("every case in the english-plural suite holds")
    func englishPluralSuiteHoldsForEveryCase() throws {
        let suite = try VectorCorpus.load("english-plural")

        let declared = try VectorCorpus.index().suites["english-plural"]
        #expect(suite.cases.count == declared, "english-plural case count disagrees with index.json")
        #expect(!suite.cases.isEmpty, "the english-plural suite is empty")

        var mismatches: [String] = []
        for testCase in suite.cases {
            guard let label = testCase.input["label"] as? String else {
                mismatches.append("english-plural/\(testCase.id): input.label is not a string")
                continue
            }
            guard let count = VectorCorpus.double(testCase.input["count"]) else {
                mismatches.append("english-plural/\(testCase.id): input.count is not a number")
                continue
            }
            guard let expected = testCase.expected as? String else {
                mismatches.append("english-plural/\(testCase.id): expected is not a string")
                continue
            }
            let actual = englishPlural(label, count: count)
            if actual != expected {
                mismatches.append(
                    "english-plural/\(testCase.id): (\"\(label)\", \(count)) -> \"\(actual)\", "
                        + "expected \"\(expected)\" — \(testCase.why)"
                )
            }
        }

        #expect(mismatches == [], "english-plural vectors that do not hold")
    }

    /// The English threshold is "anything but exactly 1" — the opposite shape of French's "below 2".
    /// 0.5 and 1.5 both pluralise, which is precisely where `frenchPlural` would keep them singular.
    @Test("anything but exactly one pluralises")
    func onlyExactlyOneStaysSingular() {
        #expect(englishPlural("carrot", count: 1) == "carrot")
        #expect(englishPlural("carrot", count: 0.5) == "carrots")
        #expect(englishPlural("carrot", count: 1.5) == "carrots")
        #expect(englishPlural("carrot", count: 2) == "carrots")
    }

    /// An invariable word must not gain a second s.
    @Test("a word already ending in s is left alone")
    func wordsEndingInSAreLeftAlone() {
        #expect(englishPlural("hummus", count: 3) == "hummus")
    }

    /// `pluralize` is the dispatcher every call site actually uses.
    @Test("the pluralize dispatcher picks the right language")
    func dispatcherPicksTheRightLanguage() {
        #expect(pluralize("carrot", count: 1.5, lang: "en") == "carrots")
        #expect(pluralize("carotte", count: 1.5, lang: "fr") == "carotte")
        #expect(pluralize("carotte", count: 1.5, lang: "und") == "carotte", "an unrecognised language falls back to French")
    }
}
