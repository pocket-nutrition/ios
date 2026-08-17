// SPDX-License-Identifier: MPL-2.0

import Testing
import PocketNutritionCore

/// Asserts `deduplicateByLabel` against the `deduplicate-suggestions` suite.
///
/// This client shipped without any of these rules, which is why a search for "poulet" rendered four rows
/// all reading "Poulet / 100 g / Produit". The corpus cases carry only the four fields the function
/// reads, so they decode into `IngredientSuggestion` with everything else defaulted.
@Suite("deduplicate-suggestions vectors")
struct DeduplicateSuggestionsVectorTests {

    @Test("every deduplicate-suggestions vector holds")
    func everyVectorHolds() throws {
        let suite = try VectorCorpus.load("deduplicate-suggestions")
        #expect(
            suite.cases.count == (try VectorCorpus.index().suites["deduplicate-suggestions"]),
            "case count disagrees with index.json"
        )

        var failures: [String] = []
        for testCase in suite.cases {
            guard let rawItems = testCase.input["items"] else {
                failures.append("\(testCase.id): input has no items")
                continue
            }
            guard let preferLanguage = testCase.input["preferLang"] as? String else {
                failures.append("\(testCase.id): input has no preferLang")
                continue
            }
            let items = try SuggestionDecoding.decode(rawItems, as: [IngredientSuggestion].self)
            let expected = try SuggestionDecoding.decode(testCase.expected, as: [IngredientSuggestion].self)

            // maxResults is absent in most cases, and absent must mean "the default" rather than zero —
            // a zero cap would return only the recipes and pass nothing else.
            let actual: [IngredientSuggestion]
            if let cap = VectorCorpus.int(testCase.input["maxResults"]) {
                actual = deduplicateByLabel(items, preferLanguage: preferLanguage, maxResults: cap)
            } else {
                actual = deduplicateByLabel(items, preferLanguage: preferLanguage)
            }

            if actual.map(\.ingredientId) != expected.map(\.ingredientId) {
                failures.append(
                    """
                    \(testCase.id): \(actual.map(\.ingredientId)) != \(expected.map(\.ingredientId)) \
                    — \(testCase.why)
                    """
                )
            }
        }
        #expect(failures == [], "deduplicate-suggestions vectors that do not hold")
    }

    /// The threshold, asserted from both sides. Two same-language results keep the server order whole;
    /// three flip it. A port that always partitions by language passes the three case and fails the two.
    @Test("the language preference switches on at three, not below")
    func languagePreferenceThreshold() {
        func suggestion(_ id: String, _ label: String, _ lang: String) -> IngredientSuggestion {
            IngredientSuggestion(ingredientId: id, label: label, lang: lang, productType: "off_product")
        }

        let twoFrench = [
            suggestion("f1", "Pain", "fr"),
            suggestion("e1", "Bread", "en"),
            suggestion("f2", "Baguette", "fr")
        ]
        #expect(
            deduplicateByLabel(twoFrench, preferLanguage: "fr").map(\.ingredientId) == ["f1", "e1", "f2"],
            "below the threshold the server order must be kept whole"
        )

        let threeFrench = twoFrench + [suggestion("f3", "Brioche", "fr")]
        #expect(
            deduplicateByLabel(threeFrench, preferLanguage: "fr").map(\.ingredientId)
                == ["f1", "f2", "f3", "e1"],
            "at the threshold the same-language results must lead"
        )
    }

    /// Trimming, which is easy to omit when porting because lowercasing is the obvious half. OFF labels
    /// frequently carry a trailing space, so an untrimmed key lets the same food through twice.
    @Test("the label key is trimmed as well as lowercased")
    func labelKeyIsTrimmed() {
        let items = [
            IngredientSuggestion(ingredientId: "a", label: "Tofu", lang: "fr", productType: "off_product"),
            IngredientSuggestion(ingredientId: "b", label: "  tofu ", lang: "fr", productType: "off_product"),
            IngredientSuggestion(ingredientId: "c", label: "\tTOFU\n", lang: "fr", productType: "off_product")
        ]
        #expect(deduplicateByLabel(items, preferLanguage: "fr").map(\.ingredientId) == ["a"])
    }

    /// Never by ingredientId. Stated by name because that is the shape the bug took: every row has a
    /// unique id, so keying on it deduplicates nothing and the list looks untouched.
    @Test("deduplication is by label, never by ingredientId")
    func deduplicatesByLabelNotId() {
        let items = (1...5).map {
            IngredientSuggestion(
                ingredientId: "off:\($0)", label: "Yaourt", lang: "fr", productType: "off_product"
            )
        }
        #expect(deduplicateByLabel(items, preferLanguage: "fr").count == 1)
    }
}
