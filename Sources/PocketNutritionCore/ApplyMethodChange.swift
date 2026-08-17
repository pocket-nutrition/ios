// SPDX-License-Identifier: MPL-2.0

/// Re-derives a row's weight when the user changes its cooking method.
///
/// **Branch order is part of the contract**, not an implementation detail, because the branches
/// overlap: a row can simultaneously have a portion factor and a cooked weight, and which rule wins
/// changes the number. In order:
///
/// 1. Target is `raw` — recompute from the portion factor if there is one, otherwise invert the
///    current yield if the weight was cooked, otherwise leave the quantity alone.
/// 2. A portion factor is present — recompute from the base and force the result cooked.
/// 3. The weight was cooked — convert through the raw equivalent, leaving `measuredState` untouched.
/// 4. Otherwise only the method changes.
///
/// Branch 3 leaving `measuredState` alone is deliberate and easy to "fix" wrongly: the weight was
/// cooked before and is still cooked after, just cooked a different way. Setting it to `cooked` there
/// would be a no-op today and a lie if branch 3 ever became reachable from a raw weight.
///
/// The round trip is *through* the raw equivalent rather than a ratio of the two factors, so the
/// half-up rounding lands once, at the end, on the value the user sees. Rounding the intermediate
/// would drift by a gram on some pairs.
///
/// Pinned by the `apply-method-change` suite of the shared behavioural corpus.
public func applyMethodChange(_ ingredient: MealIngredient, to newMethod: String) -> MealIngredient {
    // A copy: struct value semantics mean the caller's row is untouched. See the note on MealIngredient.
    var updated = ingredient

    if newMethod == "raw" {
        let rawQuantity: Double
        if ingredient.portionFactor > 0 {
            rawQuantity = Double(roundHalfUp(ingredient.basePortionG * ingredient.portionFactor))
        } else if ingredient.measuredState == "cooked" {
            let factor = resolveYieldFactor(ingredient.yieldFactors, method: ingredient.cookingMethod)
            rawQuantity = Double(roundHalfUp(ingredient.quantity / factor))
        } else {
            rawQuantity = ingredient.quantity
        }
        updated.cookingMethod = "raw"
        updated.measuredState = "raw"
        updated.quantity = rawQuantity
        return updated
    }

    if ingredient.portionFactor > 0 {
        let rawBase = ingredient.basePortionG * ingredient.portionFactor
        let factor = resolveYieldFactor(ingredient.yieldFactors, method: newMethod)
        updated.cookingMethod = newMethod
        updated.measuredState = "cooked"
        updated.quantity = Double(roundHalfUp(rawBase * factor))
        return updated
    }

    if ingredient.measuredState == "cooked" {
        let currentFactor = resolveYieldFactor(ingredient.yieldFactors, method: ingredient.cookingMethod)
        let rawEquivalent = ingredient.quantity / currentFactor
        let targetFactor = resolveYieldFactor(ingredient.yieldFactors, method: newMethod)
        updated.cookingMethod = newMethod
        updated.quantity = Double(roundHalfUp(rawEquivalent * targetFactor))
        return updated
    }

    updated.cookingMethod = newMethod
    return updated
}

/// Flattens a recipe suggestion into one `AddItem` per component.
///
/// Each component becomes an item whose method and weight come from the *recipe*, not from the
/// ingredient's own defaults — that is what makes a recipe a recipe. Order is preserved, and a recipe
/// with no components gives an empty list rather than an error: a recipe the server sent without
/// components is a data gap, not a client failure, and the caller has nothing to add.
///
/// Pinned by the `unpack-recipe` suite of the shared behavioural corpus.
public func unpackRecipe(_ recipe: IngredientSuggestion) -> [AddItem] {
    (recipe.recipeComponents ?? []).map { component in
        AddItem(
            suggestion: component.ingredient,
            cookingMethod: component.cookingMethod,
            quantityG: component.weightG
        )
    }
}
