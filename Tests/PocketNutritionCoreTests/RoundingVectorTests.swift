// SPDX-License-Identifier: MPL-2.0

import Testing

import PocketNutritionCore

/// Asserts `roundHalfUp` against the `rounding` suite of the shared corpus — the same 10 cases the web
/// client and Android assert, so a disagreement between platforms fails here rather than surfacing as
/// two different portion labels on two phones.
///
/// Mismatches are collected rather than tripping on the first, and each one quotes the `why` from the
/// corpus. A bare "expected 13, got 12" sends you to read this file; the rationale sends you to the
/// rule, which is where the answer is.
@Suite("rounding vectors")
struct RoundingVectorTests {

    @Test("every case in the rounding suite holds")
    func roundingSuiteHoldsForEveryCase() throws {
        let suite = try VectorCorpus.load("rounding")

        // Guards against asserting a suite that quietly shrank upstream: if a case is dropped in
        // contracts and the vendored copy re-synced, this catches it even though every remaining case
        // still passes.
        let declared = try VectorCorpus.index().suites["rounding"]
        #expect(suite.cases.count == declared, "rounding case count disagrees with index.json")
        #expect(!suite.cases.isEmpty, "the rounding suite is empty")

        var mismatches: [String] = []
        for testCase in suite.cases {
            guard let value = VectorCorpus.double(testCase.input["value"]) else {
                mismatches.append("rounding/\(testCase.id): input.value is not a number")
                continue
            }
            guard let expected = VectorCorpus.int(testCase.expected) else {
                mismatches.append("rounding/\(testCase.id): expected is not an integer")
                continue
            }
            let actual = roundHalfUp(value)
            if actual != expected {
                mismatches.append(
                    "rounding/\(testCase.id): \(value) -> \(actual), "
                        + "expected \(expected) — \(testCase.why)"
                )
            }
        }

        #expect(mismatches == [], "rounding vectors that do not hold")
    }

    /// The ties are the whole reason the rule is pinned rather than left to the platform, so they are
    /// named here too. If the suite is ever refactored, losing them should be loud.
    ///
    /// Parameterised so a failure names the input instead of just a line number.
    @Test("a tie rounds up, never to even", arguments: [(0.5, 1), (1.5, 2), (2.5, 3), (12.5, 13)])
    func tiesGoUpNotToEven(value: Double, expected: Int) {
        #expect(roundHalfUp(value) == expected)
    }
}
