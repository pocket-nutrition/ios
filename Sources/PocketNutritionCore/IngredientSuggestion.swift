// SPDX-License-Identifier: MPL-2.0

/// One suggestion from `GET /ingredients/search`, and the shapes built on it.
///
/// WHY THIS LIVES IN CORE RATHER THAN THE API LAYER
/// `build-meal-ingredient`, `apply-method-change` and `unpack-recipe` all take this whole shape as
/// input, so it has to be visible to the functions they pin. Moving it here costs nothing: `Decodable`
/// is Swift standard library, so this module still imports nothing and still compiles on Linux, which
/// is where CI checks it. `JSONDecoder` — the Foundation half — stays in the app layer.
///
/// Most fields are optional in the spec and genuinely absent in practice: `nutrition` came back null
/// for every result when this was written. Fields the spec defines but nothing reads (`nutrition`,
/// `densityGMl`, `unitLabels`) are deliberately *not* declared — `Decodable` ignores unknown keys, so
/// they decode away harmlessly, and declaring them would suggest something consults them. That also
/// means two suggestions comparing equal here have only compared the fields that affect behaviour,
/// which is the comparison the vectors make.
public struct IngredientSuggestion: Equatable, Sendable, Decodable, Identifiable {
    public let ingredientId: String
    public let label: String
    public let lang: String
    public let servingG: Double?
    public let displayUnit: String?
    public let typicalState: String?
    public let portionMeasuredState: String?
    public let canEatRaw: Bool?
    public let canEatCooked: Bool?
    public let yieldFactors: [String: Double]?
    public let productType: String?
    public let servingMode: String?
    public let servingUnits: [ServingUnit]?
    public let imageUrl: String?
    /// Brand behind an Open Food Facts product; nil for curated ingredients and recipes.
    ///
    /// Part of the deduplication key, not decoration — see `deduplicateByLabel`. Thousands of OFF
    /// products carry a `product_name` that is the bare food word, so before this reached the row a
    /// search for "poulet" collapsed to a single result: every product keyed on the same label.
    public let brand: String?
    /// Knowledge food group, a closed 21-value vocabulary; `"other"` for products and recipes.
    ///
    /// Read only by `foodGroupIcon`, which gives a curated ingredient a category glyph in the
    /// thumbnail slot where a product would show its photo.
    public let foodGroup: String?
    public let recipeComponents: [RecipeComponent]?

    public init(
        ingredientId: String,
        label: String,
        lang: String,
        servingG: Double? = nil,
        displayUnit: String? = nil,
        typicalState: String? = nil,
        portionMeasuredState: String? = nil,
        canEatRaw: Bool? = nil,
        canEatCooked: Bool? = nil,
        yieldFactors: [String: Double]? = nil,
        productType: String? = nil,
        servingMode: String? = nil,
        servingUnits: [ServingUnit]? = nil,
        imageUrl: String? = nil,
        brand: String? = nil,
        foodGroup: String? = nil,
        recipeComponents: [RecipeComponent]? = nil
    ) {
        self.ingredientId = ingredientId
        self.label = label
        self.lang = lang
        self.servingG = servingG
        self.displayUnit = displayUnit
        self.typicalState = typicalState
        self.portionMeasuredState = portionMeasuredState
        self.canEatRaw = canEatRaw
        self.canEatCooked = canEatCooked
        self.yieldFactors = yieldFactors
        self.productType = productType
        self.servingMode = servingMode
        self.servingUnits = servingUnits
        self.imageUrl = imageUrl
        self.brand = brand
        self.foodGroup = foodGroup
        self.recipeComponents = recipeComponents
    }

    /// A response can mix a curated ingredient with Open Food Facts products, so identity is scoped by
    /// label as well rather than trusting `ingredientId` to be unique across those two sources.
    public var id: String { "\(ingredientId)#\(label)" }

    /// True for an Open Food Facts product rather than a curated ingredient. The copy deck has a badge
    /// for it: `search.productBadge`.
    ///
    /// The value is `"off_product"`. This used to read `productType == "product"`, which the server
    /// never emits — the whole vocabulary is `ingredient`, `recipe`, `off_product` — so the badge
    /// worked only by falling through to the id prefix. The prefix check stays as a belt-and-braces
    /// guard for a response that omits `productType` entirely, which the schema permits.
    public var isProduct: Bool { productType == "off_product" || ingredientId.hasPrefix("off:") }

    /// True for a recipe, which expands into several meal rows when tapped rather than adding one.
    ///
    /// Named here rather than compared inline at each call site: the list pins recipes to the top and
    /// renders them differently, and a string literal repeated across three files is how the
    /// `"product"` typo above survived.
    public var isRecipe: Bool { productType == "recipe" }
}

/// One component of a recipe suggestion.
///
/// `cookingMethod` and `weightG` are the recipe's decisions about this ingredient, and `unpack-recipe`
/// turns them into the explicit overrides that stop `buildMealIngredient` reaching for the
/// ingredient's own defaults. Both are optional because the server's schema makes them so; an absent
/// `cookingMethod` falls back to the ingredient's `typicalState`, which may then refuse the row.
public struct RecipeComponent: Equatable, Sendable, Decodable {
    public let ingredient: IngredientSuggestion
    public let cookingMethod: String?
    public let weightG: Double?

    public init(ingredient: IngredientSuggestion, cookingMethod: String? = nil, weightG: Double? = nil) {
        self.ingredient = ingredient
        self.cookingMethod = cookingMethod
        self.weightG = weightG
    }
}

/// One item on its way into the meal.
///
/// A plain search result carries only the suggestion. A recipe component carries overrides: the
/// per-person weight the recipe specifies and the method it cooks that ingredient by. The distinction
/// is load-bearing rather than cosmetic — `build-meal-ingredient` treats an overridden `quantityG` as
/// a *pre-cooking* weight by definition, and skips the yield conversion it would otherwise apply.
public struct AddItem: Equatable, Sendable, Decodable {
    public let suggestion: IngredientSuggestion
    public let cookingMethod: String?
    public let quantityG: Double?

    public init(suggestion: IngredientSuggestion, cookingMethod: String? = nil, quantityG: Double? = nil) {
        self.suggestion = suggestion
        self.cookingMethod = cookingMethod
        self.quantityG = quantityG
    }
}
