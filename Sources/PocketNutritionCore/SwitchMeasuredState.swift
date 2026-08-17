// SPDX-License-Identifier: MPL-2.0

/// Reinterprets a row's weight as a pre- or post-cooking measurement, converting it so the number
/// still describes the same food.
///
/// This is the one control where the user tells us what their kitchen scale was measuring, and it is
/// the only place in the product where a value can be wrong by 15–40% while looking entirely correct.
/// 100 g of raw chicken is 70 g grilled. If the user weighed the cooked portion and the app believes
/// it was raw, every nutrient is overstated by the inverse of the yield, and nothing on screen says so.
///
/// Multiply going to `cooked`, divide coming back — the same direction convention as
/// `applyMethodChange`'s first branch, so the two compose without a sign error.
///
/// **`roundHalfUp`, not `rounded()`.** Swift's `Double.rounded()` breaks ties away from zero and would
/// agree here, but `rounded(.toNearestOrEven)` — and Kotlin's `kotlin.math.round`, which the android
/// port must avoid — do not: 50 × 0.85 = 42.5 gives 43 half-up and 42 ties-to-even. The
/// `switch-measured-state` suite carries that case for exactly this reason.
///
/// Returns the row unchanged when it is already in the requested state. That guard is load-bearing
/// rather than defensive: a toggle re-emitting its current value is ordinary, and without it every such
/// event would multiply the weight by the yield again.
///
/// Pinned by the `switch-measured-state` suite of the shared behavioural corpus.
public func switchMeasuredState(_ ingredient: MealIngredient, to state: String) -> MealIngredient {
    guard ingredient.measuredState != state else { return ingredient }

    // A copy: struct value semantics mean the caller's row is untouched. See the note on MealIngredient.
    var updated = ingredient
    let factor = resolveYieldFactor(ingredient.yieldFactors, method: ingredient.cookingMethod)
    updated.measuredState = state
    updated.quantity = Double(
        roundHalfUp(state == "cooked" ? ingredient.quantity * factor : ingredient.quantity / factor)
    )
    return updated
}
