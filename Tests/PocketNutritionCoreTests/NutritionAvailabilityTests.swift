// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

import PocketNutritionCore

@Suite("nutrition availability")
struct NutritionAvailabilityTests {

    /// A `POST /nutrition` item as the app reads it: availability and nutrients from the same object.
    private struct Item: Decodable, NutritionAnalysedItem {
        let isAvailable: Bool
        let nutrients: NutrientTotals

        init(isAvailable: Bool, nutrients: NutrientTotals) {
            self.isAvailable = isAvailable
            self.nutrients = nutrients
        }

        init(from decoder: Decoder) throws {
            isAvailable = try NutritionAvailability(from: decoder).available
            nutrients = try NutrientTotals(profileFrom: decoder)
        }
    }

    private func decode(_ json: String) throws -> Item {
        try JSONDecoder().decode(Item.self, from: Data(json.utf8))
    }

    @Test("available: false decodes as unavailable")
    func decodesFalse() throws {
        let item = try decode(
            #"{"name":"zorglub","energyKcal":0.0,"proteinG":0.0,"ironMg":null,"source":"unavailable","available":false}"#)
        #expect(item.isAvailable == false)
    }

    @Test("available: true decodes as available")
    func decodesTrue() throws {
        let item = try decode(#"{"name":"riz","energyKcal":195,"source":"ml","available":true}"#)
        #expect(item.isAvailable)
    }

    @Test("a response without the field counts as available")
    func missingIsAvailable() throws {
        let item = try decode(#"{"name":"riz","energyKcal":195}"#)
        #expect(item.isAvailable)
        #expect(try JSONDecoder().decode(NutritionAvailability.self, from: Data("{}".utf8)).available)
    }

    @Test("an unavailable item contributes nothing to the totals")
    func totalsSkipUnavailable() {
        let items = [
            Item(isAvailable: true, nutrients: NutrientTotals(["energyKcal": 200, "proteinG": 10])),
            // Placeholder values a server could send for an item it could not compute: never counted.
            Item(isAvailable: false, nutrients: NutrientTotals(["energyKcal": 0, "proteinG": 0, "ironMg": 3])),
            Item(isAvailable: true, nutrients: NutrientTotals(["energyKcal": 50])),
        ]
        #expect(items.countable.count == 2)
        let total = items.countableNutrients
        #expect(total["energyKcal"] == 250)
        #expect(total["proteinG"] == 10)
        // Present only on the unavailable item: stays unknown rather than becoming 3 or 0.
        #expect(total["ironMg"] == nil)
    }

    @Test("a meal of unavailable items has no known nutrient at all")
    func allUnavailable() {
        let items = [Item(isAvailable: false, nutrients: NutrientTotals(["energyKcal": 0]))]
        #expect(items.countable.isEmpty)
        #expect(items.countableNutrients.isEmpty)
    }
}

@Suite("meal record availability")
struct MealRecordAvailabilityTests {

    private func meal(items: [MealRecordPayload.Item]) -> MealRecordPayload {
        MealRecordPayload(
            id: "a", savedAt: 1, updatedAt: 2, items: items,
            totals: .init(energyKcal: 195, proteinG: 4, carbohydratesG: 42, fatG: 0.4))
    }

    @Test("the unavailable flag survives a round trip")
    func roundTrip() throws {
        let items: [MealRecordPayload.Item] = [
            .init(id: "1", ingredientId: "rice", label: "riz", quantityG: 150, cookingMethod: "boiled",
                  measuredState: "cooked"),
            .init(id: "2", ingredientId: nil, label: "zorglub", quantityG: 100, cookingMethod: "raw",
                  measuredState: "raw", available: false),
        ]
        let back = try decodeMealRecord(try encodeMealRecord(meal(items: items)), expectedId: "a")
        #expect(back.items == items)
        #expect(back.items[0].isAvailable)
        #expect(back.items[1].isAvailable == false)
    }

    @Test("an available item is written without the field, so the record is unchanged for it")
    func availableNotWritten() throws {
        let item = MealRecordPayload.Item(
            id: "1", ingredientId: "rice", label: "riz", quantityG: 150, cookingMethod: "boiled",
            measuredState: "cooked")
        let json = String(decoding: try encodeMealRecord(meal(items: [item])), as: UTF8.self)
        #expect(!json.contains("available"))
    }

    @Test("a record written before the field existed decodes as available")
    func oldRecord() throws {
        let v2 = #"""
        {"v":2,"id":"a","saved_at":1,"updated_at":2,"slot":"lunch",
         "items":[{"id":"1","ingredient_id":"rice","label":"riz","quantity_g":150,
                   "cooking_method":"boiled","measured_state":"cooked"}],
         "totals":{"energy_kcal":195,"protein_g":4,"carbohydrates_g":42,"fat_g":0.4}}
        """#
        let old = try decodeMealRecord(Data(v2.utf8), expectedId: "a")
        #expect(old.items[0].available == nil)
        #expect(old.items[0].isAvailable)
    }
}
