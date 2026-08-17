// SPDX-License-Identifier: MPL-2.0

/// The six cooking methods the app knows. `PnCooking.methods` in the design tokens is keyed by the
/// same ids, and the API may still hand back a value outside this set — see `cookingMethodFor`.
let cookingMethods: Set<String> = ["raw", "boiled", "steamed", "grilled", "roasted", "fried"]

/// Translates the server's `typicalState` into the cooking method to open a row with, or nil.
///
/// This is enum translation, not food knowledge. Five of Knowledge's state values already *are*
/// cooking methods and pass through unchanged, and `processed` means "eaten as sold" — no cooking
/// transform — which is what `raw` encodes here.
///
/// The generic `cooked` returns nil, and that is the interesting case. It says the food is eaten
/// cooked without saying how, and nothing here can choose between boiled and fried without inventing
/// an answer. Inventing one is exactly what the sandbox's deleted label table did: it answered
/// "grilled" whenever its regexes had no opinion. Roughly 274 ingredients — 8% of the catalogue — sit
/// on that value, and they are dropped rather than guessed until the API exposes a resolved
/// `defaultCookingMethod`.
public func cookingMethodFor(_ typicalState: String?) -> String? {
    guard let typicalState, typicalState != "cooked" else { return nil }
    if typicalState == "processed" { return "raw" }
    return cookingMethods.contains(typicalState) ? typicalState : nil
}

/// Builds a meal row from a server suggestion, or returns nil when the server did not supply the food
/// data the row needs.
///
/// THE CLIENT HOLDS NO FOOD DATA. There is no label-to-cooking-method table and no label-to-portion
/// table, and nothing here substitutes a weight or a state that the server omitted. `servingG`,
/// `typicalState` and `portionMeasuredState` are all documented as server-supplied — the API defaults
/// them when Knowledge has no value — so a nil is a contract violation on the server's side. The row
/// is dropped rather than guessed at, and **callers must handle nil by skipping the item**. Returning
/// a row with an invented weight would be worse than showing nothing: the user cannot tell a guessed
/// gram figure from a known one.
///
/// `id` is a parameter rather than something built here. The sandbox composes it from the ingredient
/// id, `Date.now()` and the item's index; this module has no clock by design, and the vectors exclude
/// `id` for exactly that reason — it embeds a timestamp. The app layer supplies it.
///
/// Pinned by the `build-meal-ingredient` suite of the shared behavioural corpus.
public func buildMealIngredient(_ item: AddItem, id: String) -> MealIngredient? {
    let suggestion = item.suggestion

    // `basePortionG` is the anchor every portion control scales from; without it there is no row.
    guard let base = suggestion.servingG else { return nil }

    // A recipe component carries its own method, so `typicalState` is only consulted without one.
    guard let defaultCooking = item.cookingMethod ?? cookingMethodFor(suggestion.typicalState) else {
        return nil
    }

    let isCooked = defaultCooking != "raw"

    // Whether `base` is a pre- or post-cooking weight decides whether the yield factor applies, so it
    // changes the number on screen. Refuse rather than assume. An overridden quantity needs no such
    // check: a recipe weight is a pre-cooking weight by definition.
    if item.quantityG == nil && isCooked && suggestion.portionMeasuredState == nil { return nil }

    let measureRaw = item.quantityG != nil
        ? isCooked
        : isCooked && suggestion.portionMeasuredState == "raw"

    // A gram override defeats a millilitre display unit: the caller gave a weight, so the row is a
    // weight. Only an un-overridden millilitre food is measured by volume.
    let isMl = item.quantityG == nil && suggestion.displayUnit == "ml"
    let firstUnit = suggestion.servingUnits?.first

    let quantity: Double
    if let override = item.quantityG {
        quantity = override
    } else if isMl {
        quantity = Double(roundHalfUp(base))
    } else if measureRaw {
        quantity = base
    } else if isCooked {
        let factor = resolveYieldFactor(suggestion.yieldFactors ?? [:], method: defaultCooking)
        quantity = Double(roundHalfUp(base * factor))
    } else {
        quantity = base
    }

    return MealIngredient(
        id: id,
        label: suggestion.label,
        ingredientId: suggestion.ingredientId,
        cookingMethod: defaultCooking,
        quantity: quantity,
        unit: isMl ? "ml" : "g",
        measuredState: measureRaw ? "raw" : (isCooked ? "cooked" : "raw"),
        basePortionG: base,
        portionFactor: 1,
        servingUnits: suggestion.servingUnits ?? [],
        selectedUnit: isMl ? firstUnit : nil,
        unitCount: 1,
        displayUnit: isMl ? "ml" : "g",
        canEatRaw: suggestion.canEatRaw,
        yieldFactors: suggestion.yieldFactors ?? [:],
        imageUrl: suggestion.imageUrl,
        servingMode: suggestion.servingMode
    )
}
