// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

import PocketNutritionCore

/// Asserts `shouldToggleSelection` against the `selection-mode` suite.
///
/// Six cases for a three-branch predicate, which is more than it looks like it needs. The one that earns
/// the suite is `multi-term-recipe-still-adds-immediately`: a port that dropped the recipe exception would
/// make recipes un-addable on any two-word query, and nothing else in this test suite would notice.
@Suite("selection-mode vectors")
struct SelectionModeVectorTests {

    @Test("every selection-mode vector holds")
    func everyVectorHolds() throws {
        let suite = try VectorCorpus.load("selection-mode")
        #expect(
            suite.cases.count == (try VectorCorpus.index().suites["selection-mode"]),
            "selection-mode count disagrees with index.json"
        )

        var failures: [String] = []
        for testCase in suite.cases {
            guard let rawCount = testCase.input["termCount"] as? NSNumber else {
                failures.append("\(testCase.id): input has no termCount")
                continue
            }
            // Nullable on purpose: one case pins that an absent productType does NOT take the recipe
            // branch, so a JSON null and a missing key have to be told apart rather than coalesced.
            let productType: String?
            switch testCase.input["productType"] {
            case let value as String: productType = value
            case is NSNull, nil: productType = nil
            default:
                failures.append("\(testCase.id): productType is neither string nor null")
                continue
            }

            guard let expected = testCase.expected as? Bool else {
                failures.append("\(testCase.id): expected is not a boolean")
                continue
            }
            let actual = shouldToggleSelection(termCount: rawCount.intValue, productType: productType)
            if actual != expected {
                failures.append("\(testCase.id): got \(actual), want \(expected) — \(testCase.why)")
            }
        }
        #expect(failures == [], "selection-mode vectors that do not hold")
    }
}
