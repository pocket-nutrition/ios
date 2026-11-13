// SPDX-License-Identifier: MPL-2.0

import Foundation
import PocketNutritionCore

// Bridges Core's `MealIngredient` to the two app-layer shapes it has to become: a request the API
// understands, and the `MealItem` the journal persists.
//
// WHY THE BUILDER USES MealIngredient AND THE JOURNAL DOES NOT
// `MealIngredient` carries the whole portion model — base portion, serving units, serving mode, yield
// factors — because `buildAnchors`, `shortcutProfile` and `describeQuantity` all need it. A *saved*
// meal needs none of that: it is a record of what was eaten, and storing the portion machinery would
// grow `journal.json` with fields nothing reads back. So the builder works in `MealIngredient` and
// converts once, at the save boundary. That also keeps the on-disk schema at version 1.

extension MealIngredient {

    /// One item of a `POST /nutrition` request body.
    ///
    /// `unit` is the row's own unit rather than a hardcoded "g", which matters for millilitre foods:
    /// before the ladder existed the app sent every quantity as grams, so 200 mL of milk was sent as
    /// 200 g. The two differ by the density — 206 g for a 200 mL glass in Knowledge's own numbers.
    func asRequest() -> FoodItemRequest {
        FoodItemRequest(
            name: label,
            quantity: quantity,
            unit: unit,
            cookingMethod: cookingMethod,
            measuredState: measuredState,
            ingredientId: ingredientId
        )
    }

    /// The journal's persisted shape. Drops the portion model deliberately — see the note above.
    /// A quick-add row: an energy figure typed in the search field, with no ingredient behind it. Held in
    /// the builder as a row whose unit is "kcal" and quantity the energy, and never sent to the server.
    var isQuickAddRow: Bool { unit == "kcal" }

    static func quickAdd(kcal: Double, id: String) -> MealIngredient {
        MealIngredient(
            id: id, label: "\(roundHalfUp(kcal)) kcal", ingredientId: "quick-add:\(id)", cookingMethod: "",
            quantity: kcal, unit: "kcal", measuredState: "", basePortionG: kcal, portionFactor: 1,
            servingUnits: [], selectedUnit: nil, unitCount: 1, displayUnit: "kcal", canEatRaw: nil,
            yieldFactors: [:], imageUrl: nil, servingMode: nil)
    }

    func asMealItem() -> MealItem {
        if isQuickAddRow {
            return MealItem(
                ingredientId: nil, label: label, quantityG: 0, cookingMethod: "", measuredState: "",
                energyKcal: quantity)
        }
        return MealItem(
            ingredientId: ingredientId,
            label: label,
            quantityG: quantity,
            cookingMethod: cookingMethod,
            measuredState: measuredState
        )
    }

    /// The ladder's rungs, resolved to weights.
    ///
    /// `buildAnchors` returns `ScaleStep`s and `describeQuantity` wants `QuantityAnchor`s; the bridge is
    /// `stepRawWeight` and `stepLabel`, both corpus functions. Resolving the weight here rather than in
    /// the view is what keeps `step-raw-weight`'s rule — unit steps ignore the base portion entirely —
    /// from being re-derived by hand somewhere it would be got wrong.
    func ladder(lang: String) -> [ScaleStep] {
        buildAnchors(basePortionG: basePortionG, servingUnits: servingUnits, servingMode: servingMode, lang: lang)
    }

    func anchors(lang: String) -> [QuantityAnchor] {
        ladder(lang: lang).map {
            QuantityAnchor(label: stepLabel($0, lang: lang), grams: stepRawWeight($0, basePortionG: basePortionG))
        }
    }

    /// The collapsed summary — "≈ 1,3 portion"/"≈ 1.3 servings" and the weight beneath it.
    func summary(lang: String) -> QuantityDescription {
        let itemUnit = servingUnits.first(where: { $0.isItem })
        return describeQuantity(
            currentG: quantity,
            anchors: anchors(lang: lang),
            context: QuantityContext(
                servingMode: servingMode,
                // The item unit's weight and label, when there is one. `describeQuantity` keys its item
                // branch on *these* rather than on servingMode — the corpus has a case with no
                // servingMode that still takes that branch — so passing them is what makes "≈ 2
                // carottes" possible at all.
                itemUnitG: itemUnit?.grams,
                itemLabel: itemUnit.flatMap { pickLocalized($0.labels, preferring: lang) },
                portionG: basePortionG,
                displayUnit: displayUnit
            ),
            lang: lang
        )
    }
}

extension MealItem {

    /// Rebuilds a builder row from a saved entry, for editing.
    ///
    /// The reverse of `asMealItem()` — but lossy in the other direction: a saved `MealItem` carries none
    /// of the portion metadata (`basePortionG`, `servingUnits`, `yieldFactors`) the ladder needs, because
    /// that metadata is deliberately dropped at save time (see the note above). This builds the same
    /// degraded shape `asMealRow`'s fallback branch already builds when the corpus can't resolve an
    /// ingredient: the saved weight becomes the base portion, with no serving units or yield factors to
    /// convert it. The one consequence worth knowing — switching cooking method on an edited row will not
    /// auto-adjust the weight, since there is no yield factor to convert with.
    func asMealIngredient(id: String) -> MealIngredient {
        if isQuickAdd, let energyKcal { return .quickAdd(kcal: energyKcal, id: id) }
        return MealIngredient(
            id: id,
            label: label,
            ingredientId: ingredientId ?? id,
            cookingMethod: cookingMethod,
            quantity: quantityG,
            unit: "g",
            measuredState: measuredState,
            basePortionG: quantityG,
            portionFactor: 1,
            servingUnits: [],
            selectedUnit: nil,
            unitCount: 1,
            displayUnit: "g",
            canEatRaw: nil,
            yieldFactors: [:],
            imageUrl: nil,
            servingMode: nil
        )
    }
}

extension IngredientSuggestion {

    /// Builds a meal row, falling back when the corpus function refuses.
    ///
    /// **This is a deliberate, documented divergence and the one place it lives.**
    /// `buildMealIngredient` returns nil rather than invent food data the server did not send — the
    /// right call for the sandbox, which is a reference implementation. Knowledge no longer emits a
    /// generic `typicalState: "cooked"` (every ingredient now names a specific method, or "raw" /
    /// "processed"), but the corpus can still refuse for other reasons — most commonly a `typicalState`
    /// the client's known method set does not recognise — and the fallback below is what keeps that
    /// ingredient addable rather than a dead end.
    ///
    /// So the corpus function is tried first and used whenever it succeeds, which keeps every pinned
    /// behaviour — the yield conversions, the millilitre handling, the raw/cooked weight semantics —
    /// exactly as verified. Only its refusals are overridden, and the fallback does not *invent* a
    /// weight: it seeds an editable field with a visible number the user is expected to correct. It
    /// defaults the method to "grilled" — a visible, correctable guess rather than the retired generic
    /// "cuit (générique)" bucket, which is no longer a value this app ever produces.
    func asMealRow(id: String) -> MealIngredient {
        if let row = buildMealIngredient(AddItem(suggestion: self), id: id) {
            return row.lockedToRawIfIndustrial(isProduct: isProduct)
        }

        let base = servingG ?? fallbackPortionG
        let fallback = MealIngredient(
            id: id,
            label: label,
            ingredientId: ingredientId,
            cookingMethod: typicalState == "raw" ? "raw" : "grilled",
            quantity: base,
            unit: displayUnit == "ml" ? "ml" : "g",
            measuredState: portionMeasuredState ?? typicalState ?? "cooked",
            basePortionG: base,
            portionFactor: 1,
            servingUnits: servingUnits ?? [],
            selectedUnit: nil,
            unitCount: 1,
            displayUnit: displayUnit == "ml" ? "ml" : "g",
            canEatRaw: canEatRaw,
            yieldFactors: yieldFactors ?? [:],
            imageUrl: imageUrl,
            servingMode: servingMode
        )
        return fallback.lockedToRawIfIndustrial(isProduct: isProduct)
    }
}

extension MealIngredient {

    /// Locks a row to "raw" the moment it wraps an Open Food Facts product: the backend now always
    /// analyses OFF items at their own values (source "off_direct", cookingMethod "raw") regardless of
    /// what the client sends, so offering a cooking-method choice here would be a UI lie. Goes through
    /// `applyMethodChange` rather than re-deriving the raw-weight math, so that conversion stays the
    /// one place it is pinned. Idempotent for a row that is already raw.
    func lockedToRawIfIndustrial(isProduct: Bool) -> MealIngredient {
        guard isProduct else { return self }
        var locked = applyMethodChange(self, to: "raw")
        locked.isIndustrialProduct = true
        return locked
    }
}

/// The weight to seed a row with when the server sent no reference portion. 100 g because it is the
/// unit every nutrition table is quoted per, so it is the number a user can most easily reason about
/// when correcting it.
private let fallbackPortionG: Double = 100
