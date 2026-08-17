// SPDX-License-Identifier: MPL-2.0

import Testing

import PocketNutritionCore

/// Asserts `resolveYieldFactor` against the `yield-factor` suite of the shared corpus.
///
/// Equality here is exact rather than tolerant, deliberately. The function performs no arithmetic — it
/// selects a value from Knowledge and returns it verbatim — so any drift from 2.2286 means the wrong
/// branch was taken, not that a float wobbled. A tolerance would hide exactly the bug the suite exists
/// to catch.
@Suite("yield-factor vectors")
struct YieldFactorVectorTests {

    @Test("every case in the yield-factor suite holds")
    func yieldFactorSuiteHoldsForEveryCase() throws {
        let suite = try VectorCorpus.load("yield-factor")

        let declared = try VectorCorpus.index().suites["yield-factor"]
        #expect(suite.cases.count == declared, "yield-factor case count disagrees with index.json")
        #expect(!suite.cases.isEmpty, "the yield-factor suite is empty")

        var mismatches: [String] = []
        for testCase in suite.cases {
            guard let rawFactors = testCase.input["yieldFactors"] as? [String: Any] else {
                mismatches.append("yield-factor/\(testCase.id): input.yieldFactors is not an object")
                continue
            }
            guard let method = testCase.input["method"] as? String else {
                mismatches.append("yield-factor/\(testCase.id): input.method is not a string")
                continue
            }
            guard let expected = VectorCorpus.double(testCase.expected) else {
                mismatches.append("yield-factor/\(testCase.id): expected is not a number")
                continue
            }

            var factors: [String: Double] = [:]
            var malformedKey: String?
            for (key, value) in rawFactors {
                guard let factor = VectorCorpus.double(value) else {
                    malformedKey = key
                    break
                }
                factors[key] = factor
            }
            if let malformedKey {
                mismatches.append(
                    "yield-factor/\(testCase.id): yieldFactors[\"\(malformedKey)\"] is not a number"
                )
                continue
            }

            let actual = resolveYieldFactor(factors, method: method)
            if actual != expected {
                mismatches.append(
                    "yield-factor/\(testCase.id): (\(factors), \"\(method)\") -> \(actual), "
                        + "expected \(expected) — \(testCase.why)"
                )
            }
        }

        #expect(mismatches == [], "yield-factor vectors that do not hold")
    }

    /// Branch order is the one thing a port can get wrong while still looking right. Checking `raw`
    /// after the dictionary lookup passes every other case in the suite and returns 2.2286 for raw
    /// food, so the precedence is asserted directly rather than left to the suite alone.
    @Test("raw wins over a present cooked factor")
    func rawIsAnsweredBeforeAnyLookup() {
        #expect(resolveYieldFactor(["cooked": 2.2286], method: "raw") == 1)
    }

    /// The rice bug, named: a method with no key of its own must fall back to the generic one rather
    /// than to 1.
    @Test("a method with no key of its own falls back to cooked")
    func genericCookedIsTheFallback() {
        #expect(resolveYieldFactor(["cooked": 2.2286], method: "boiled") == 2.2286)
        #expect(resolveYieldFactor(["boiled": 0.9, "cooked": 2.2], method: "boiled") == 0.9)
    }

    /// No yield at all means no conversion — never an estimate.
    @Test("an absent yield returns one rather than a guess")
    func nothingIsInvented() {
        #expect(resolveYieldFactor([:], method: "boiled") == 1)
    }
}
