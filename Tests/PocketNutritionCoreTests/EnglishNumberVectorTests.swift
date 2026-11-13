// SPDX-License-Identifier: MPL-2.0

import Testing

import PocketNutritionCore

/// Asserts `formatEnglishNumber` against the `english-number` suite of the shared corpus — the mirror
/// of `FrenchNumberVectorTests`, added in contract 2.0.0.
@Suite("english-number vectors")
struct EnglishNumberVectorTests {

    @Test("every case in the english-number suite holds")
    func englishNumberSuiteHoldsForEveryCase() throws {
        let suite = try VectorCorpus.load("english-number")

        let declared = try VectorCorpus.index().suites["english-number"]
        #expect(suite.cases.count == declared, "english-number case count disagrees with index.json")
        #expect(!suite.cases.isEmpty, "the english-number suite is empty")

        var mismatches: [String] = []
        for testCase in suite.cases {
            guard let value = VectorCorpus.double(testCase.input["value"]) else {
                mismatches.append("english-number/\(testCase.id): input.value is not a number")
                continue
            }
            guard let expected = testCase.expected as? String else {
                mismatches.append("english-number/\(testCase.id): expected is not a string")
                continue
            }
            let actual = formatEnglishNumber(value)
            if actual != expected {
                mismatches.append(
                    "english-number/\(testCase.id): \(value) -> \"\(actual)\", "
                        + "expected \"\(expected)\" — \(testCase.why)"
                )
            }
        }

        #expect(mismatches == [], "english-number vectors that do not hold")
    }

    @Test(
        "a whole number carries no decimal part",
        arguments: [(0.0, "0"), (2.0, "2"), (10.0, "10")]
    )
    func wholeNumbersRenderWithoutDecimals(value: Double, expected: String) {
        #expect(formatEnglishNumber(value) == expected)
    }

    /// The mirror-image guard to `FrenchNumberVectorTests`'s comma check: the separator stays a dot,
    /// and a value below one keeps its leading zero.
    @Test("a fractional value uses a dot and keeps its leading zero")
    func fractionalValuesUseADotAndKeepTheLeadingZero() {
        #expect(formatEnglishNumber(1.1) == "1.1")
        #expect(formatEnglishNumber(0.5) == "0.5")
        #expect(!formatEnglishNumber(0.5).hasPrefix("."))
    }

    /// `formatNumber` is the dispatcher every call site actually uses — asserted here so a future
    /// change to the dispatch rule (e.g. a third language) is caught alongside the two functions it
    /// switches between.
    @Test("the formatNumber dispatcher picks the right language")
    func dispatcherPicksTheRightLanguage() {
        #expect(formatNumber(1.5, lang: "en") == "1.5")
        #expect(formatNumber(1.5, lang: "fr") == "1,5")
        #expect(formatNumber(1.5, lang: "und") == "1,5", "an unrecognised language falls back to French")
    }
}
