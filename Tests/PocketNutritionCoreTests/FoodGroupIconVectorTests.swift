// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

import PocketNutritionCore

/// Asserts `foodGroupIcon` against the `food-group-icon` suite of the shared corpus.
///
/// The map exists because Open Food Facts supplies a photo for roughly four fifths of its products while
/// the knowledge base has no image field at all — so a row drawing only `imageUrl` gave every packaged
/// product a photograph and every curated ingredient a blank, making the industrial result look more
/// trustworthy than the reference one.
///
/// `expected` is an explicit JSON null for the three unmapped groups, not an absent key, so it decodes to
/// `NSNull` here rather than to nothing — the same distinction `serving-unit-emoji` preserves.
@Suite("food-group-icon vectors")
struct FoodGroupIconVectorTests {

    @Test("every case in the food-group-icon suite holds")
    func foodGroupIconSuiteHoldsForEveryCase() throws {
        let suite = try VectorCorpus.load("food-group-icon")

        let declared = try VectorCorpus.index().suites["food-group-icon"]
        #expect(suite.cases.count == declared, "food-group-icon count disagrees with index.json")
        #expect(!suite.cases.isEmpty, "the food-group-icon suite is empty")

        var mismatches: [String] = []
        for testCase in suite.cases {
            // The input is nullable on purpose — one case pins that a null group yields no icon rather
            // than throwing, so an absent key and a JSON null must be told apart here.
            let group: String?
            switch testCase.input["foodGroup"] {
            case let name as String: group = name
            case is NSNull: group = nil
            case nil:
                mismatches.append("food-group-icon/\(testCase.id): input has no foodGroup key")
                continue
            default:
                mismatches.append("food-group-icon/\(testCase.id): foodGroup is neither string nor null")
                continue
            }

            let expected: String?
            switch testCase.expected {
            case let glyph as String: expected = glyph
            case is NSNull: expected = nil
            default:
                mismatches.append("food-group-icon/\(testCase.id): expected is neither string nor null")
                continue
            }

            let actual = foodGroupIcon(group)
            if actual != expected {
                mismatches.append(
                    "food-group-icon/\(testCase.id): \(group ?? "nil") -> \(actual ?? "nil"), "
                        + "expected \(expected ?? "nil") — \(testCase.why)"
                )
            }
        }

        #expect(mismatches == [], "food-group-icon vectors that do not hold")
    }

    /// Every value the schema declares is accounted for, one way or the other. Asserted by name because
    /// the suite cannot catch a group added to Knowledge and forgotten here — an unmapped group and an
    /// unknown one both return nil, so the vectors would still pass while real ingredients lost an icon.
    @Test("all 21 declared food groups are accounted for")
    func theClosedVocabularyIsFullyAccountedFor() {
        let withGlyph = [
            "meat", "processed_meat", "fish", "shellfish", "egg", "dairy", "vegetable", "fruit",
            "cereal", "legume", "nut_seed", "fat", "spice_herb", "sweetener", "baked_good",
            "beverage", "alcohol", "prepared_dish"
        ]
        let withoutGlyph = ["sauce", "seaweed", "other"]

        for group in withGlyph {
            #expect(foodGroupIcon(group) != nil, "\(group) is mapped in the corpus but not here")
        }
        for group in withoutGlyph {
            #expect(foodGroupIcon(group) == nil, "\(group) has no glyph by contract")
        }
        #expect(
            withGlyph.count + withoutGlyph.count == 21,
            "ingredient.schema.json declares 21 food groups"
        )
    }

    /// No two groups may share a glyph. The suite asserts each mapping in isolation, so it would pass a
    /// port that mapped both `meat` and `processed_meat` to 🥩 — and the list's whole purpose is telling
    /// rows apart.
    @Test("no two food groups share a glyph")
    func everyGlyphIsDistinct() {
        let groups = [
            "meat", "processed_meat", "fish", "shellfish", "egg", "dairy", "vegetable", "fruit",
            "cereal", "legume", "nut_seed", "fat", "spice_herb", "sweetener", "baked_good",
            "beverage", "alcohol", "prepared_dish"
        ]
        let glyphs = groups.compactMap { foodGroupIcon($0) }
        #expect(glyphs.count == groups.count, "a mapped group returned nil")
        #expect(Set(glyphs).count == glyphs.count, "two food groups render the same glyph")
    }

    /// The two collisions the map was designed around, pinned so a later "tidy-up" cannot reintroduce
    /// them: 🍲 marks a recipe row in the suggestion list, and 🥛 is the `glass` serving unit.
    @Test("the glyphs reserved elsewhere in the UI are not reused")
    func reservedGlyphsAreNotReused() {
        #expect(foodGroupIcon("prepared_dish") != "🍲", "🍲 marks a recipe row")
        #expect(foodGroupIcon("dairy") != servingUnitEmoji("glass"), "🥛 is the glass serving unit")
    }
}
