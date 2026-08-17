// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

import PocketNutritionCore

/// Asserts `servingUnitEmoji` against the `serving-unit-emoji` suite of the shared corpus.
///
/// This suite exists because `shortcut-profile` could only ever exercise the two or three units its
/// own cases happen to use, which left four of the seven mapped glyphs unpinned and this client
/// shipping an incomplete table. Every entry now has a vector.
///
/// `expected` is an explicit JSON null for the units with no glyph, not an absent key — so it decodes
/// to `NSNull` here rather than to nothing, which is exactly the distinction `VectorCorpus` documents
/// having preserved on purpose.
@Suite("serving-unit-emoji vectors")
struct ServingUnitEmojiVectorTests {

    @Test("every case in the serving-unit-emoji suite holds")
    func servingUnitEmojiSuiteHoldsForEveryCase() throws {
        let suite = try VectorCorpus.load("serving-unit-emoji")

        let declared = try VectorCorpus.index().suites["serving-unit-emoji"]
        #expect(suite.cases.count == declared, "serving-unit-emoji count disagrees with index.json")
        #expect(!suite.cases.isEmpty, "the serving-unit-emoji suite is empty")

        var mismatches: [String] = []
        for testCase in suite.cases {
            guard let unit = testCase.input["unit"] as? String else {
                mismatches.append("serving-unit-emoji/\(testCase.id): input.unit is not a string")
                continue
            }
            // null means "no glyph"; a string means that glyph. Anything else is a corpus error.
            let expected: String?
            switch testCase.expected {
            case let glyph as String: expected = glyph
            case is NSNull: expected = nil
            default:
                mismatches.append(
                    "serving-unit-emoji/\(testCase.id): expected is neither a string nor null"
                )
                continue
            }

            let actual = servingUnitEmoji(unit)
            if actual != expected {
                mismatches.append(
                    "serving-unit-emoji/\(testCase.id): \(unit) -> \(actual ?? "nil"), "
                        + "expected \(expected ?? "nil") — \(testCase.why)"
                )
            }
        }

        #expect(mismatches == [], "serving-unit-emoji vectors that do not hold")
    }

    /// The map must cover every unit the closed vocabulary declares, one way or the other. Asserted by
    /// name so that a unit added to Knowledge without a decision here is visible rather than silently
    /// iconless — the suite would still pass, since an unmapped unit and an unknown one look alike.
    @Test("every unit in the closed vocabulary is accounted for")
    func theClosedVocabularyIsFullyAccountedFor() {
        let withGlyph = ["pinch", "teaspoon", "tablespoon", "cup", "handful", "small_handful", "glass"]
        let withoutGlyph = ["shot", "bowl", "scoop"]

        for unit in withGlyph {
            #expect(servingUnitEmoji(unit) != nil, "\(unit) is mapped in the corpus but not here")
        }
        for unit in withoutGlyph {
            #expect(servingUnitEmoji(unit) == nil, "\(unit) has no glyph by contract")
        }
        #expect(withGlyph.count + withoutGlyph.count == 10, "serving_unit_types.yaml declares ten")
    }

    /// The two spoons share one glyph. `shortcut-profile` only ever asserts one of them per case, so a
    /// port that keys one and forgets the other passes that suite entirely.
    @Test("the two spoons share a glyph")
    func spoonsShareAGlyph() {
        #expect(servingUnitEmoji("teaspoon") == "🥄")
        #expect(servingUnitEmoji("tablespoon") == "🥄")
    }
}
