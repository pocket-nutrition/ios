// SPDX-License-Identifier: MPL-2.0

import Testing

import PocketNutritionCore

/// Asserts `buildAnchors` against the `build-anchors` suite of the shared corpus.
///
/// The suite's real subject is the branch condition. Three of its six cases are the same weight
/// ladder reached three different ways — no serving units at all, an item unit the mode does not
/// authorise, and a mode that authorises counting with nothing countable available. A port that
/// branches on `servingMode` alone passes the first and fails the other two.
@Suite("build-anchors vectors")
struct BuildAnchorsVectorTests {

    @Test("every case in the build-anchors suite holds")
    func buildAnchorsSuiteHoldsForEveryCase() throws {
        let suite = try VectorCorpus.load("build-anchors")

        let declared = try VectorCorpus.index().suites["build-anchors"]
        #expect(suite.cases.count == declared, "build-anchors case count disagrees with index.json")
        #expect(!suite.cases.isEmpty, "the build-anchors suite is empty")

        var mismatches: [String] = []
        for testCase in suite.cases {
            guard let basePortion = VectorCorpus.double(testCase.input["basePortionG"]) else {
                mismatches.append("build-anchors/\(testCase.id): input.basePortionG is not a number")
                continue
            }
            guard let rawUnits = testCase.input["servingUnits"] as? [[String: Any]] else {
                mismatches.append("build-anchors/\(testCase.id): input.servingUnits is not an array")
                continue
            }
            // servingMode is null in two cases and must stay nil rather than becoming "null".
            let servingMode = testCase.input["servingMode"] as? String

            let units = rawUnits.compactMap(ScaleStepDecoding.servingUnit)
            guard units.count == rawUnits.count else {
                mismatches.append("build-anchors/\(testCase.id): a servingUnit is malformed")
                continue
            }
            guard let rawExpected = testCase.expected as? [[String: Any]] else {
                mismatches.append("build-anchors/\(testCase.id): expected is not an array")
                continue
            }
            let expected = rawExpected.compactMap(ScaleStepDecoding.step)
            guard expected.count == rawExpected.count else {
                mismatches.append("build-anchors/\(testCase.id): an expected step is malformed")
                continue
            }

            let actual = buildAnchors(
                basePortionG: basePortion,
                servingUnits: units,
                servingMode: servingMode
            )
            if actual != expected {
                mismatches.append(
                    "build-anchors/\(testCase.id): got \(actual), expected \(expected) — \(testCase.why)"
                )
            }
        }

        #expect(mismatches == [], "build-anchors vectors that do not hold")
    }

    /// Both halves of the branch condition, asserted directly. Either one alone is not enough, and
    /// the failure mode of getting this wrong is an empty ladder rather than a visibly wrong one.
    @Test("counting needs the item mode and an item unit, not either alone")
    func bothHalvesOfTheItemConditionAreRequired() {
        let carrot = ServingUnit(unit: "item", labelFr: "carotte", volumeMl: 0, grams: 74)
        let spoon = ServingUnit(unit: "tablespoon", labelFr: "c. à soupe", volumeMl: 15, grams: 15)

        let counted = buildAnchors(basePortionG: 74, servingUnits: [carrot], servingMode: "item")
        #expect(counted.allSatisfy { if case .unit = $0 { return true } else { return false } })

        // Mode says item, nothing countable on offer.
        let noItemUnit = buildAnchors(basePortionG: 80, servingUnits: [spoon], servingMode: "item")
        #expect(noItemUnit.allSatisfy { if case .factor = $0 { return true } else { return false } })

        // Countable unit present, mode says weight.
        let notAuthorised = buildAnchors(basePortionG: 74, servingUnits: [carrot], servingMode: "weight")
        #expect(notAuthorised.allSatisfy { if case .factor = $0 { return true } else { return false } })
    }

    /// The two thresholds, at their boundaries. Both are inclusive, and a port that writes `>` rather
    /// than `>=` loses exactly one rung in each ladder without failing anything else.
    @Test("the drop thresholds are inclusive")
    func thresholdsAreInclusive() {
        // A 10 g item: the 0.5 rung resolves to exactly 5 g and is kept.
        let tenGramItem = ServingUnit(unit: "item", labelFr: "noix", volumeMl: 0, grams: 10)
        let kept = buildAnchors(basePortionG: 10, servingUnits: [tenGramItem], servingMode: "item")
        #expect(kept.count == 4, "0.5 x 10 g is exactly the 5 g floor and must survive")

        // A 4 g base portion: the 0.25 rung resolves to exactly 1 g and is kept.
        let atFactorFloor = buildAnchors(basePortionG: 4, servingUnits: [], servingMode: nil)
        #expect(atFactorFloor.count == 5, "0.25 x 4 g is exactly the 1 g floor and must survive")
    }
}
