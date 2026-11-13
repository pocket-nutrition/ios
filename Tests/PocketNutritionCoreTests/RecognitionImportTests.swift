// SPDX-License-Identifier: MPL-2.0

import Testing

import PocketNutritionCore

@Suite("recognition import mapping")
struct RecognitionImportTests {

    private func suggestion(typicalState: String? = "raw", servingG: Double? = 100) -> IngredientSuggestion {
        IngredientSuggestion(
            ingredientId: "riz_blanc", label: "Rice", lang: "en", servingG: servingG,
            typicalState: typicalState, portionMeasuredState: "raw"
        )
    }

    private func item(
        quantity: Double? = nil, unit: String? = nil, cooking: String? = nil,
        candidates: [RecognitionCandidate] = [RecognitionCandidate(ingredientId: "riz_blanc", name: nil, score: 0.9)]
    ) -> RecognitionItem {
        RecognitionItem(rawText: "riz", quantity: quantity, unit: unit, cookingMethod: cooking, candidates: candidates)
    }

    @Test("grams are applied as the pre-cooking weight override")
    func gramsApplied() {
        let add = importAddItem(suggestion: suggestion(), item: item(quantity: 250, unit: "g"))
        #expect(add.quantityG == 250)
    }

    @Test("pieces leave the suggestion's own serving untouched")
    func piecesIgnored() {
        let add = importAddItem(suggestion: suggestion(), item: item(quantity: 2, unit: "piece"))
        #expect(add.quantityG == nil)
        guard case .row(let row) = resolveImport(
            item: item(quantity: 2, unit: "piece"), suggestion: suggestion(), rowId: "r"
        ) else { Issue.record("expected a row"); return }
        #expect(row.quantity == 100)
    }

    @Test("no unit, no quantity, zero, negative and non-finite quantities are ignored")
    func quantityEdges() {
        #expect(importAddItem(suggestion: suggestion(), item: item(quantity: 3, unit: nil)).quantityG == nil)
        #expect(importAddItem(suggestion: suggestion(), item: item(quantity: nil, unit: "g")).quantityG == nil)
        #expect(importAddItem(suggestion: suggestion(), item: item(quantity: 0, unit: "g")).quantityG == nil)
        #expect(importAddItem(suggestion: suggestion(), item: item(quantity: -5, unit: "g")).quantityG == nil)
        #expect(importAddItem(suggestion: suggestion(), item: item(quantity: .infinity, unit: "g")).quantityG == nil)
    }

    @Test("each known cooking method passes through, anything else is dropped")
    func cookingMethods() {
        for method in ["raw", "boiled", "steamed", "grilled", "roasted", "fried"] {
            #expect(importAddItem(suggestion: suggestion(), item: item(cooking: method)).cookingMethod == method)
        }
        for invalid in ["sauteed", "Fried", "", "cooked", "baked"] {
            #expect(importAddItem(suggestion: suggestion(), item: item(cooking: invalid)).cookingMethod == nil)
        }
    }

    @Test("an unresolvable id is skipped, never substituted")
    func unknownIdSkipped() {
        #expect(resolveImport(item: item(), suggestion: nil, rowId: "r") == .skipped(.unknownIngredient))
    }

    @Test("an item with no candidates is skipped")
    func noCandidates() {
        #expect(resolveImport(item: item(candidates: []), suggestion: nil, rowId: "r") == .skipped(.noCandidate))
    }

    @Test("a suggestion the corpus builder refuses is skipped, no weight or method invented")
    func notBuildable() {
        // No serving weight: the builder refuses rather than guess one.
        #expect(resolveImport(item: item(), suggestion: suggestion(servingG: nil), rowId: "r")
            == .skipped(.notBuildable))
        // Generic "cooked" with no method from the recogniser: nothing to choose between boiled and fried.
        #expect(resolveImport(item: item(), suggestion: suggestion(typicalState: "cooked"), rowId: "r")
            == .skipped(.notBuildable))
    }

    @Test("a valid recognised method makes an otherwise generic-cooked suggestion buildable with grams")
    func methodRescuesGenericCooked() {
        let outcome = resolveImport(
            item: item(quantity: 180, unit: "g", cooking: "boiled"),
            suggestion: suggestion(typicalState: "cooked"), rowId: "r"
        )
        guard case .row(let row) = outcome else { Issue.record("expected a row"); return }
        #expect(row.cookingMethod == "boiled")
        #expect(row.quantity == 180)
        #expect(row.ingredientId == "riz_blanc")
        #expect(row.id == "r")
    }

    @Test("the best candidate is the first one")
    func bestCandidate() {
        let candidates = [
            RecognitionCandidate(ingredientId: "x", name: nil, score: 0.9),
            RecognitionCandidate(ingredientId: "y", name: nil, score: 0.8),
        ]
        #expect(item(candidates: candidates).bestCandidate?.ingredientId == "x")
        #expect(item(candidates: []).bestCandidate == nil)
    }
}
