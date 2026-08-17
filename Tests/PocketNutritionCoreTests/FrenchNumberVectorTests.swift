// SPDX-License-Identifier: MPL-2.0

import Testing

import PocketNutritionCore

/// Asserts `formatFrenchNumber` against the `french-number` suite of the shared corpus.
///
/// The suite is small and every case is aimed at a different way a locale-aware formatter would go
/// wrong: a dropped leading zero, an inserted thousands separator, a forced decimal place on a whole
/// number. Reading the `why` lines is faster than rediscovering any of them.
@Suite("french-number vectors")
struct FrenchNumberVectorTests {

    @Test("every case in the french-number suite holds")
    func frenchNumberSuiteHoldsForEveryCase() throws {
        let suite = try VectorCorpus.load("french-number")

        let declared = try VectorCorpus.index().suites["french-number"]
        #expect(suite.cases.count == declared, "french-number case count disagrees with index.json")
        #expect(!suite.cases.isEmpty, "the french-number suite is empty")

        var mismatches: [String] = []
        for testCase in suite.cases {
            guard let value = VectorCorpus.double(testCase.input["value"]) else {
                mismatches.append("french-number/\(testCase.id): input.value is not a number")
                continue
            }
            guard let expected = testCase.expected as? String else {
                mismatches.append("french-number/\(testCase.id): expected is not a string")
                continue
            }
            let actual = formatFrenchNumber(value)
            if actual != expected {
                mismatches.append(
                    "french-number/\(testCase.id): \(value) -> \"\(actual)\", "
                        + "expected \"\(expected)\" — \(testCase.why)"
                )
            }
        }

        #expect(mismatches == [], "french-number vectors that do not hold")
    }

    /// The whole-number rule is the one a formatter-based port breaks first, so it is named here as
    /// well as covered by the suite.
    @Test(
        "a whole number carries no decimal part",
        arguments: [(0.0, "0"), (2.0, "2"), (10.0, "10")]
    )
    func wholeNumbersRenderWithoutDecimals(value: Double, expected: String) {
        #expect(formatFrenchNumber(value) == expected)
    }

    /// Guards the two properties that make this a comma rule rather than a formatter call: the
    /// separator is a comma, and a value below one keeps its leading zero.
    @Test("a fractional value uses a comma and keeps its leading zero")
    func fractionalValuesUseACommaAndKeepTheLeadingZero() {
        #expect(formatFrenchNumber(1.1) == "1,1")
        #expect(formatFrenchNumber(0.5) == "0,5")
        #expect(!formatFrenchNumber(0.5).hasPrefix(","))
    }
}
