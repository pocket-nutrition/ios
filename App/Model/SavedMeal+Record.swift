// SPDX-License-Identifier: MPL-2.0

import Foundation
import PocketNutritionCore

/// The journal's meals as vault records, and back. The record's id is the meal's id, lowercased.
extension SavedMeal {

    var recordId: String { id.uuidString.lowercased() }

    var record: MealRecordPayload {
        MealRecordPayload(
            id: recordId,
            savedAt: savedAt.timeIntervalSince1970,
            updatedAt: modifiedAt.timeIntervalSince1970,
            items: items.map {
                .init(
                    id: $0.id.uuidString.lowercased(), ingredientId: $0.ingredientId, label: $0.label,
                    quantityG: $0.quantityG, cookingMethod: $0.cookingMethod, measuredState: $0.measuredState,
                    energyKcal: $0.energyKcal, available: $0.available)
            },
            totals: .init(
                energyKcal: totals.energyKcal, proteinG: totals.proteinG,
                carbohydratesG: totals.carbohydratesG, fatG: totals.fatG),
            slot: effectiveSlot.rawValue,
            nutrients: nutrients)
    }

    /// Nil when the record's ids are not UUIDs: not something this app wrote, so not something to show.
    init?(record: MealRecordPayload) {
        guard let id = UUID(uuidString: record.id) else { return nil }
        var items: [MealItem] = []
        for item in record.items {
            guard let itemId = UUID(uuidString: item.id) else { return nil }
            items.append(
                MealItem(
                    id: itemId, ingredientId: item.ingredientId, label: item.label, quantityG: item.quantityG,
                    cookingMethod: item.cookingMethod, measuredState: item.measuredState,
                    energyKcal: item.energyKcal, available: item.available))
        }
        self.init(
            id: id, savedAt: Date(timeIntervalSince1970: record.savedAt), items: items,
            totals: Macros(
                energyKcal: record.totals.energyKcal, proteinG: record.totals.proteinG,
                carbohydratesG: record.totals.carbohydratesG, fatG: record.totals.fatG),
            updatedAt: Date(timeIntervalSince1970: record.updatedAt),
            slot: record.slot.flatMap(MealSlot.init(rawValue:)),
            nutrients: record.nutrients)
    }
}
