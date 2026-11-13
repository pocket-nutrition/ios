// SPDX-License-Identifier: MPL-2.0

import Foundation
import PocketNutritionCore

/// What the user decided for one recognised item on the review screen.
struct ImportSelection: Sendable {
    let item: RecognitionItem
    /// nil when the item has no candidates.
    let candidate: RecognitionCandidate?
}

struct SkippedItem: Sendable, Equatable {
    let rawText: String
    let kind: ImportSkipKind
}

struct ImportReport: Sendable {
    let rows: [MealIngredient]
    let skipped: [SkippedItem]
}

/// Resolves the chosen candidates to meal rows using the EXISTING by-id lookup
/// (`GET /ingredients/{id}`), then the corpus rules in Core (`resolveImport`).
///
/// An id the catalogue does not know, or a row the corpus builder will not make without inventing a
/// weight or a cooking method, is SKIPPED and reported. There is no name search and no fallback — the
/// POC server's ids are static samples, so skipping is common and expected.
enum RecognitionImporter {

    static func resolve(_ selections: [ImportSelection], lang: String) async -> ImportReport {
        var rows: [MealIngredient] = []
        var skipped: [SkippedItem] = []
        let batch = UUID().uuidString
        for (index, selection) in selections.enumerated() {
            guard let candidate = selection.candidate else {
                skipped.append(SkippedItem(rawText: selection.item.rawText, kind: .noCandidate))
                continue
            }
            // The id came from the server and becomes a URL path segment: anything outside the safe
            // alphabet is a definitive "not in the catalogue", never looked up.
            guard isValidIngredientId(candidate.ingredientId) else {
                skipped.append(SkippedItem(rawText: selection.item.rawText, kind: .unknownIngredient))
                continue
            }
            let suggestion: IngredientSuggestion?
            do {
                let detail = try await PocketNutritionApi.shared.ingredientDetail(candidate.ingredientId)
                suggestion = detail?.asSuggestion(id: candidate.ingredientId, fallbackLabel: candidate.name, lang: lang)
                // Found, but with no name to show: that is "cannot build a row", not "not found".
                if detail != nil, suggestion == nil {
                    skipped.append(SkippedItem(rawText: selection.item.rawText, kind: .notBuildable))
                    continue
                }
            } catch {
                skipped.append(SkippedItem(rawText: selection.item.rawText, kind: .lookupFailed))
                continue
            }
            switch resolveImport(item: selection.item, suggestion: suggestion, rowId: "\(candidate.ingredientId)-voice-\(batch)-\(index)") {
            case .row(let row):
                rows.append(row.lockedToRawIfIndustrial(isProduct: suggestion?.isProduct ?? false))
            case .skipped(let reason):
                let kind: ImportSkipKind = switch reason {
                case .noCandidate: .noCandidate
                case .unknownIngredient: .unknownIngredient
                case .notBuildable: .notBuildable
                }
                skipped.append(SkippedItem(rawText: selection.item.rawText, kind: kind))
            }
        }
        return ImportReport(rows: rows, skipped: skipped)
    }
}

extension IngredientDetail {
    /// The by-id endpoint returns a detail rather than a suggestion, so this carries across only what
    /// the server actually said. `portionMeasuredState` and `yieldFactors` are not in that response and
    /// are NOT invented: the corpus builder then refuses a cooked row it cannot size, and the item is
    /// skipped rather than guessed. Nil when there is no label to show.
    func asSuggestion(id: String, fallbackLabel: String?, lang: String) -> IngredientSuggestion? {
        guard let label = pickLocalized(names, preferring: lang) ?? fallbackLabel else { return nil }
        return IngredientSuggestion(
            ingredientId: id, label: label, lang: lang,
            servingG: referenceWeightG, displayUnit: displayUnit, typicalState: typicalState,
            canEatRaw: canEatRaw, canEatCooked: canEatCooked,
            servingUnits: servingUnits, foodGroup: foodGroup
        )
    }
}
