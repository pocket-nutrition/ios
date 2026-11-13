// SPDX-License-Identifier: MPL-2.0

import Testing

import PocketNutritionCore

/// Asserts `describeQuantity` against the `describe-quantity` suite of the shared corpus.
///
/// The largest suite, and the one with the most ways to be subtly wrong: two tolerance windows of
/// different widths, a nearest-match rule that a first-match port fails, an if/else-if whose nesting
/// changes what a sliver of carrot reads as, and two weight formats that differ by a space.
@Suite("describe-quantity vectors")
struct DescribeQuantityVectorTests {

    /// Covers both `describe-quantity` (French, no `lang` field — defaults to "fr") and
    /// `describe-quantity-en` (English, `lang: "en"` in every fixture).
    @Test("every case in the describe-quantity and describe-quantity-en suites holds", arguments: ["describe-quantity", "describe-quantity-en"])
    func describeQuantitySuiteHoldsForEveryCase(suiteName: String) throws {
        let suite = try VectorCorpus.load(suiteName)

        let declared = try VectorCorpus.index().suites[suiteName]
        #expect(suite.cases.count == declared, "\(suiteName) case count disagrees with index.json")
        #expect(!suite.cases.isEmpty, "the \(suiteName) suite is empty")

        var mismatches: [String] = []
        for testCase in suite.cases {
            guard let currentG = VectorCorpus.double(testCase.input["currentG"]),
                  let rawAnchors = testCase.input["anchors"] as? [[String: Any]],
                  let rawContext = testCase.input["ctx"] as? [String: Any],
                  let context = ScaleStepDecoding.quantityContext(rawContext)
            else {
                mismatches.append("\(suiteName)/\(testCase.id): input is malformed")
                continue
            }
            let lang = testCase.input["lang"] as? String ?? "fr"
            let anchors = rawAnchors.compactMap(ScaleStepDecoding.anchor)
            guard anchors.count == rawAnchors.count else {
                mismatches.append("\(suiteName)/\(testCase.id): an anchor is malformed")
                continue
            }
            guard let rawExpected = testCase.expected as? [String: Any],
                  let primary = rawExpected["primary"] as? String,
                  let secondary = rawExpected["secondary"] as? String
            else {
                mismatches.append("\(suiteName)/\(testCase.id): expected is malformed")
                continue
            }

            let actual = describeQuantity(currentG: currentG, anchors: anchors, context: context, lang: lang)
            let expected = QuantityDescription(primary: primary, secondary: secondary)
            if actual != expected {
                mismatches.append(
                    "\(suiteName)/\(testCase.id): got \(actual), expected \(expected) "
                        + "— \(testCase.why)"
                )
            }
        }

        #expect(mismatches == [], "\(suiteName) vectors that do not hold")
    }

    /// Nearest wins, not first. The corpus has one case for this; here it is asserted in both
    /// orderings, so a port that happens to scan in the lucky direction is still caught.
    @Test("the nearest anchor wins regardless of scan order")
    func nearestAnchorWinsInEitherOrder() {
        let small = QuantityAnchor(label: "Petite", grams: 63)
        let one = QuantityAnchor(label: "1 part", grams: 66)
        let context = QuantityContext(portionG: 64, displayUnit: "g")

        #expect(describeQuantity(currentG: 64, anchors: [small, one], context: context, lang: "fr").primary == "Petite")
        #expect(describeQuantity(currentG: 64, anchors: [one, small], context: context, lang: "fr").primary == "Petite")
    }

    /// The item branch is entered on having an item unit, not on `servingMode`. The corpus's sliver
    /// case proves it by omitting the mode; this proves the converse, that a mode of "item" with no
    /// item unit does not take the branch.
    @Test("the item branch keys on the item unit, not on servingMode")
    func itemBranchIgnoresServingMode() {
        let withMode = QuantityContext(
            servingMode: "item", itemUnitG: nil, itemLabel: nil, portionG: 64, displayUnit: "g"
        )
        // No item unit: falls to the portion ratio despite the mode saying item.
        #expect(describeQuantity(currentG: 80, anchors: [], context: withMode, lang: "fr").primary == "≈ 1,3 portion")

        let withoutMode = QuantityContext(
            servingMode: nil, itemUnitG: 74, itemLabel: "carotte", portionG: 74, displayUnit: "g"
        )
        // Item unit present, no mode: takes the item branch anyway.
        #expect(describeQuantity(currentG: 81, anchors: [], context: withoutMode, lang: "fr").primary == "≈ 1,1 carotte")
    }

    /// A sliver falls through to grams and specifically NOT to the portion ratio. Flattening the
    /// if/else-if would produce "≈ 0,1 portion" here, which still looks plausible.
    @Test("a sub-quarter item falls through to grams, not to the portion ratio")
    func slverFallsThroughToGramsOnly() {
        let context = QuantityContext(
            itemUnitG: 74, itemLabel: "carotte", portionG: 74, displayUnit: "g"
        )
        let described = describeQuantity(currentG: 10, anchors: [], context: context, lang: "fr")
        #expect(described == QuantityDescription(primary: "10g", secondary: ""))
    }

    /// Two formats that differ by a space and a capital, both user-visible, plus the guard that stops
    /// a trace of an ingredient rendering as "0g".
    @Test("weights render per unit, and never as zero")
    func weightFormatting() {
        let grams = QuantityContext(portionG: 0, displayUnit: "g")
        let millilitres = QuantityContext(portionG: 0, displayUnit: "ml")

        #expect(describeQuantity(currentG: 64, anchors: [], context: grams, lang: "fr").primary == "64g")
        #expect(describeQuantity(currentG: 270, anchors: [], context: millilitres, lang: "fr").primary == "270 mL")
        #expect(describeQuantity(currentG: 0.4, anchors: [], context: grams, lang: "fr").primary == "< 1g")
        #expect(describeQuantity(currentG: 0.5, anchors: [], context: millilitres, lang: "fr").primary == "< 1 mL")
    }

    /// The two windows are different widths on purpose: 4 % to claim an anchor, 8 % to describe a
    /// neighbourhood. 100 g against a 64 g portion sits between them — outside the 96 g anchor's
    /// window, inside Grande's — and is the case that proves they are not the same number.
    @Test("the anchor window is tighter than the named-descriptor window")
    func theTwoWindowsDiffer() {
        let anchors = [QuantityAnchor(label: "Grande", grams: 96)]
        let context = QuantityContext(portionG: 64, displayUnit: "g")
        #expect(describeQuantity(currentG: 100, anchors: anchors, context: context, lang: "fr").primary == "≈ Grande")
    }
}
