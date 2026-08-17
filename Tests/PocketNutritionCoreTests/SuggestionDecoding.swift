// SPDX-License-Identifier: MPL-2.0

import Foundation
import PocketNutritionCore

/// Bridges the corpus reader's untyped JSON to the typed Core shapes.
///
/// The reader hands back `[String: Any]` on purpose — `expected` has a different shape in every suite,
/// so it knows the corpus structure and nothing about any payload. These three suites are the ones
/// where that is inconvenient: their inputs are whole `IngredientSuggestion` trees, and unpacking
/// eighteen fields by hand from a dictionary would be both tedious and a second place for the shape to
/// drift. Re-serialising and decoding uses the same `Decodable` conformance the app uses against the
/// real server, so a mismatch between the corpus shape and the struct fails here rather than at runtime.
enum SuggestionDecoding {

    /// Round-trips a fragment of corpus JSON into a Core type.
    static func decode<T: Decodable>(_ value: Any, as type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: value)
        return try JSONDecoder().decode(type, from: data)
    }

    /// True when the corpus says the expectation is `null`.
    ///
    /// `NSNull`, not `nil`: the reader keeps `expected` as `Any` precisely so an explicit JSON null
    /// survives the trip instead of reading as "the key was absent". Three of the eleven
    /// `build-meal-ingredient` cases expect null, so conflating the two would silently pass them.
    static func isNull(_ value: Any) -> Bool { value is NSNull }
}

/// A `MealIngredient` minus its `id`, which is the projection `build-meal-ingredient` asserts.
///
/// The suite excludes `id` because the sandbox builds it from `Date.now()`. Rather than decode
/// `expected` into a `MealIngredient` and paper over the missing field with a placeholder — which
/// would make an `id` regression invisible — this states exactly what is and is not compared.
/// `apply-method-change` does not need it: `id` is supplied in that suite's input and asserted.
struct ComparableRow: Decodable, Equatable {
    let label: String
    let ingredientId: String
    let cookingMethod: String
    let quantity: Double
    let unit: String
    let measuredState: String
    let basePortionG: Double
    let portionFactor: Double
    let servingUnits: [ServingUnit]
    let selectedUnit: ServingUnit?
    let unitCount: Double
    let displayUnit: String
    let canEatRaw: Bool?
    let yieldFactors: [String: Double]
    let imageUrl: String?
    let servingMode: String?

    init(_ row: MealIngredient) {
        label = row.label
        ingredientId = row.ingredientId
        cookingMethod = row.cookingMethod
        quantity = row.quantity
        unit = row.unit
        measuredState = row.measuredState
        basePortionG = row.basePortionG
        portionFactor = row.portionFactor
        servingUnits = row.servingUnits
        selectedUnit = row.selectedUnit
        unitCount = row.unitCount
        displayUnit = row.displayUnit
        canEatRaw = row.canEatRaw
        yieldFactors = row.yieldFactors
        imageUrl = row.imageUrl
        servingMode = row.servingMode
    }
}
