// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Why a recognised item was skipped on import, including the app-level lookup failure.
public enum ImportSkipKind: Equatable, Sendable {
    case noCandidate, unknownIngredient, notBuildable
    /// The by-id lookup failed for a transient reason (network, 5xx). Not a verdict on the food.
    case lookupFailed
}

/// A recognition entry may be deleted after an import only if every skip is definitive. A transient
/// lookup failure means the item might still have worked, so the entry must stay for a retry.
public func canDiscardAfterImport(skips: [ImportSkipKind]) -> Bool {
    !skips.contains(.lookupFailed)
}

/// True when the server host differs, so a key saved for the old host must not be sent to the new one.
///
/// With no host on record the answer depends on whether a key exists: a Keychain item survives an app
/// reinstall while the saved URL does not, and such a key has no known host to be trusted for.
public func recognitionHostChanged(from old: String?, to new: String, hasStoredKey: Bool = false) -> Bool {
    guard let old else { return hasStoredKey }
    let oldHost = URLComponents(string: old)?.host?.lowercased()
    let newHost = URLComponents(string: new)?.host?.lowercased()
    return oldHost == nil || oldHost != newHost
}

/// Why a recognised item did not become a meal row.
public enum ImportSkipReason: Equatable, Sendable {
    /// The server offered no candidate for it.
    case noCandidate
    /// The chosen candidate's id is not in the catalogue (the lookup returned 404, or failed).
    case unknownIngredient
    /// The catalogue knows the id but the corpus builder cannot make a row from it without inventing a
    /// weight or a cooking method.
    case notBuildable
}

public enum ImportOutcome: Equatable, Sendable {
    case row(MealIngredient)
    case skipped(ImportSkipReason)
}

/// Applies the import rules to one recognised item and the suggestion its chosen candidate resolved to.
///
/// - `quantity` is used only when `unit == "g"` (and is a positive finite number); it becomes the
///   pre-cooking weight override, the same path a recipe component takes. NOTE FOR THE USER-FACING
///   BEHAVIOUR: a spoken "200 g of rice" is therefore treated as 200 g BEFORE cooking, whatever the
///   speaker meant; the row can be edited in the meal builder. Any other unit leaves the
///   suggestion's own serving untouched — there is no piece-to-gram table, by design.
/// - `cooking_method` is used only if it is one of the six the app knows; anything else is dropped.
public func importAddItem(suggestion: IngredientSuggestion, item: RecognitionItem) -> AddItem {
    var grams: Double?
    if item.unit == "g", let quantity = item.quantity, quantity.isFinite, quantity > 0 {
        grams = quantity
    }
    let method = item.cookingMethod.flatMap { cookingMethods.contains($0) ? $0 : nil }
    return AddItem(suggestion: suggestion, cookingMethod: method, quantityG: grams)
}

/// Resolves one recognised item to a meal row, or says why it was skipped.
///
/// NEVER INVENTS FOOD DATA: a nil `suggestion` (id not found) or a suggestion `buildMealIngredient`
/// refuses is skipped, never substituted by a name search or filled with a default weight.
public func resolveImport(
    item: RecognitionItem, suggestion: IngredientSuggestion?, rowId: String
) -> ImportOutcome {
    guard item.bestCandidate != nil else { return .skipped(.noCandidate) }
    guard let suggestion else { return .skipped(.unknownIngredient) }
    guard let row = buildMealIngredient(importAddItem(suggestion: suggestion, item: item), id: rowId) else {
        return .skipped(.notBuildable)
    }
    return .row(row)
}
