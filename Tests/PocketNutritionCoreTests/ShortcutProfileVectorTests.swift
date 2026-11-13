// SPDX-License-Identifier: MPL-2.0

import Testing

import PocketNutritionCore

/// Asserts `shortcutProfile` against the `shortcut-profile` suite of the shared corpus.
@Suite("shortcut-profile vectors")
struct ShortcutProfileVectorTests {

    /// Covers both `shortcut-profile` (French, no `lang` field — defaults to "fr") and
    /// `shortcut-profile-en` (English, `lang: "en"` in every fixture).
    @Test("every case in the shortcut-profile and shortcut-profile-en suites holds", arguments: ["shortcut-profile", "shortcut-profile-en"])
    func shortcutProfileSuiteHoldsForEveryCase(suiteName: String) throws {
        let suite = try VectorCorpus.load(suiteName)

        let declared = try VectorCorpus.index().suites[suiteName]
        #expect(suite.cases.count == declared, "\(suiteName) case count disagrees with index.json")
        #expect(!suite.cases.isEmpty, "the \(suiteName) suite is empty")

        var mismatches: [String] = []
        for testCase in suite.cases {
            guard let rawUnits = testCase.input["servingUnits"] as? [[String: Any]],
                  let displayUnit = testCase.input["displayUnit"] as? String
            else {
                mismatches.append("\(suiteName)/\(testCase.id): input is malformed")
                continue
            }
            let lang = testCase.input["lang"] as? String ?? "fr"
            let units = rawUnits.compactMap(ScaleStepDecoding.servingUnit)
            guard units.count == rawUnits.count else {
                mismatches.append("\(suiteName)/\(testCase.id): a servingUnit is malformed")
                continue
            }
            guard let rawExpected = testCase.expected as? [[String: Any]] else {
                mismatches.append("\(suiteName)/\(testCase.id): expected is not an array")
                continue
            }
            let expected = rawExpected.compactMap(ScaleStepDecoding.shortcut)
            guard expected.count == rawExpected.count else {
                mismatches.append("\(suiteName)/\(testCase.id): an expected shortcut is malformed")
                continue
            }

            let actual = shortcutProfile(servingUnits: units, displayUnit: displayUnit, lang: lang)
            if actual != expected {
                mismatches.append(
                    "\(suiteName)/\(testCase.id): got \(actual), expected \(expected) "
                        + "— \(testCase.why)"
                )
            }
        }

        #expect(mismatches == [], "\(suiteName) vectors that do not hold")
    }

    /// The suite states an invariant in prose — "the result always has between 2 and 4 entries" —
    /// which no single vector can express. Checked across every case, and across the degenerate
    /// inputs the corpus does not contain.
    @Test("the row always holds between two and four entries")
    func rowSizeInvariantHolds() throws {
        let suite = try VectorCorpus.load("shortcut-profile")
        for testCase in suite.cases {
            guard let rawUnits = testCase.input["servingUnits"] as? [[String: Any]],
                  let displayUnit = testCase.input["displayUnit"] as? String
            else { continue }
            let count = shortcutProfile(
                servingUnits: rawUnits.compactMap(ScaleStepDecoding.servingUnit),
                displayUnit: displayUnit,
                lang: "fr"
            ).count
            #expect((2...4).contains(count), "shortcut-profile/\(testCase.id) produced \(count) entries")
        }

        #expect((2...4).contains(shortcutProfile(servingUnits: [], displayUnit: "g", lang: "fr").count))
        // Ten usable units must still cap at one anchor plus three increments.
        let many = (1...10).map {
            ServingUnit(unit: "cup", labels: [LocalizedText(lang: "fr", text: "tasse \($0)")], volumeMl: 0, grams: Double($0 * 10))
        }
        #expect(shortcutProfile(servingUnits: many, displayUnit: "g", lang: "fr").count == 4)
    }

    /// The naming wart, asserted directly: for a volume food the increment is read from `volumeMl`
    /// even though the output field is called `grams`. Reading the wrong one yields 0, the unit is
    /// dropped as sub-gram, and the row silently degrades to the multipliers.
    @Test("a volume food reads volumeMl, not grams")
    func volumeFoodsReadMillilitres() {
        let spoon = ServingUnit(unit: "tablespoon", labels: [LocalizedText(lang: "fr", text: "c. à soupe")], volumeMl: 15, grams: 0)
        #expect(
            shortcutProfile(servingUnits: [spoon], displayUnit: "ml", lang: "fr") == [
                .multiplier(label: "1 Part", factor: 1),
                .increment(label: "c. à soupe", emoji: "🥄", grams: 15),
            ]
        )
        // The same unit read as a weight food has nothing to offer, so the multipliers come back.
        #expect(shortcutProfile(servingUnits: [spoon], displayUnit: "g", lang: "fr").count == 3)
    }

    /// An unrecognised unit carries no emoji at all. The corpus omits the key rather than emitting
    /// null, so nil here is the correct model and "" would be a different thing.
    @Test("an unrecognised unit has no emoji")
    func unknownUnitsHaveNoEmoji() {
        let scoop = ServingUnit(unit: "scoop", labels: [LocalizedText(lang: "fr", text: "boule")], volumeMl: 0, grams: 50)
        #expect(
            shortcutProfile(servingUnits: [scoop], displayUnit: "g", lang: "fr") == [
                .multiplier(label: "1 Part", factor: 1),
                .increment(label: "boule", emoji: nil, grams: 50),
            ]
        )
    }
}
