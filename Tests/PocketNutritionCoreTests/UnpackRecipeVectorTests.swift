// SPDX-License-Identifier: MPL-2.0

import Testing
import PocketNutritionCore

/// Asserts `unpackRecipe` against the `unpack-recipe` suite.
///
/// Two cases, which is enough for what the function is: a flatten that preserves order and carries the
/// recipe's decisions through as explicit overrides. The named tests below cover what two cases cannot
/// — that those overrides are what stop `buildMealIngredient` reaching for the ingredient's own
/// defaults, which is the whole reason the override fields exist.
@Suite("unpack-recipe vectors")
struct UnpackRecipeVectorTests {

    @Test("every unpack-recipe vector holds")
    func everyVectorHolds() throws {
        let suite = try VectorCorpus.load("unpack-recipe")
        #expect(
            suite.cases.count == (try VectorCorpus.index().suites["unpack-recipe"]),
            "case count disagrees with index.json"
        )

        var failures: [String] = []
        for testCase in suite.cases {
            guard let rawRecipe = testCase.input["recipe"] else {
                failures.append("\(testCase.id): input has no recipe")
                continue
            }
            let recipe = try SuggestionDecoding.decode(rawRecipe, as: IngredientSuggestion.self)
            let expected = try SuggestionDecoding.decode(testCase.expected, as: [AddItem].self)
            let actual = unpackRecipe(recipe)
            if actual != expected {
                failures.append(
                    "\(testCase.id): produced \(actual.count) items, expected \(expected.count) — \(testCase.why)"
                )
            }
        }
        #expect(failures == [], "unpack-recipe vectors that do not hold")
    }

    /// A recipe the server sent without components is a data gap, not a client failure. Asserted for
    /// both an absent key and an empty array, because `recipeComponents` is optional in the schema and
    /// the two arrive differently.
    @Test("a recipe with no components yields no items, never an error")
    func noComponentsYieldsNoItems() {
        let absent = IngredientSuggestion(
            ingredientId: "recipe:x", label: "x", lang: "fr",
            servingG: 80, productType: "recipe", recipeComponents: nil
        )
        let empty = IngredientSuggestion(
            ingredientId: "recipe:x", label: "x", lang: "fr",
            servingG: 80, productType: "recipe", recipeComponents: []
        )
        #expect(unpackRecipe(absent).isEmpty)
        #expect(unpackRecipe(empty).isEmpty)
    }

    /// The point of the overrides: the component's own `typicalState` would have refused this row, and
    /// the recipe's method rescues it. This is the interaction the two vectors do not reach, and it is
    /// the reason `unpackRecipe` carries `cookingMethod` rather than letting each row re-derive one.
    @Test("recipe overrides override the ingredient's own defaults")
    func recipeOverridesWin() throws {
        // typicalState "cooked" is refused on its own — it says cooked without saying how.
        let ambiguous = IngredientSuggestion(
            ingredientId: "potato", label: "pomme de terre", lang: "fr",
            servingG: 80, displayUnit: "g", typicalState: "cooked", portionMeasuredState: "raw",
            yieldFactors: ["boiled": 0.9]
        )
        #expect(
            buildMealIngredient(AddItem(suggestion: ambiguous), id: "i") == nil,
            "a generic cooked state must be refused without an override"
        )

        let recipe = IngredientSuggestion(
            ingredientId: "recipe:gratin", label: "gratin", lang: "fr",
            servingG: 300, productType: "recipe",
            recipeComponents: [
                RecipeComponent(ingredient: ambiguous, cookingMethod: "boiled", weightG: 200)
            ]
        )

        let items = unpackRecipe(recipe)
        #expect(items.count == 1)
        let row = try #require(buildMealIngredient(items[0], id: "i"))
        #expect(row.cookingMethod == "boiled", "the recipe's method must win")
        // 200 g is the recipe's weight and a recipe weight is pre-cooking by definition, so the yield
        // factor must NOT be applied: 200, not 180.
        #expect(row.quantity == 200, "a recipe weight is a pre-cooking weight — no yield conversion")
        #expect(row.measuredState == "raw")
        // The base stays the ingredient's own portion, not the recipe's per-person weight.
        #expect(row.basePortionG == 80)
    }

    /// Order is preserved. Stated in the suite description, and trivially breakable by anything that
    /// groups or sorts components on the way through.
    @Test("component order is preserved")
    func componentOrderIsPreserved() {
        func component(_ id: String) -> RecipeComponent {
            RecipeComponent(
                ingredient: IngredientSuggestion(
                    ingredientId: id, label: id, lang: "fr", servingG: 50, typicalState: "raw"
                ),
                cookingMethod: "raw",
                weightG: 10
            )
        }
        let recipe = IngredientSuggestion(
            ingredientId: "recipe:x", label: "x", lang: "fr", servingG: 80, productType: "recipe",
            recipeComponents: [component("c"), component("a"), component("b")]
        )
        #expect(unpackRecipe(recipe).map(\.suggestion.ingredientId) == ["c", "a", "b"])
    }
}
