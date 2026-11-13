// SPDX-License-Identifier: MPL-2.0

import Foundation

/// A journal meal as it is stored in the vault: the plaintext of one `meal` record, before encryption.
///
/// Its own type rather than the app's `SavedMeal`, so the wire format cannot change by accident when the
/// UI model does, and so that another client (Android, the web viewer) can implement exactly this.
/// Timestamps are seconds since 1970 (a number, not a date string) so no client has to agree on a
/// date format. Readers ignore fields they do not know.
///
/// Version 2 (2026-11) adds three optional fields: the meal's `slot` (breakfast, lunch, dinner, snack),
/// the full `nutrients` the engine returned, and `energy_kcal` on an item typed as a bare calorie figure
/// ("quick add", no ingredient). A v1 record still decodes, with those fields absent. A v1-only client
/// refuses a v2 record as `unsupportedVersion`, and the sync never overwrites what it cannot read.
public struct MealRecordPayload: Codable, Equatable, Sendable {

    /// Written by this client.
    public static let version = 2
    /// Read by this client.
    public static let readableVersions: ClosedRange<Int> = 1...2

    public struct Item: Codable, Equatable, Sendable {
        public var id: String
        public var ingredientId: String?
        public var label: String
        public var quantityG: Double
        public var cookingMethod: String
        public var measuredState: String
        /// v2: set only on a quick-add item (no ingredient, an energy figure typed by the person).
        public var energyKcal: Double?
        /// Written only as `false`: the server could not compute the item, so its nutrients are unknown
        /// and the meal's totals leave it out. Absent means available, which is how every record written
        /// before the field existed reads. Additive, so it does not change `version`: an older reader
        /// ignores it and still shows totals that already exclude the item.
        public var available: Bool?

        /// `available` absent counts as true.
        public var isAvailable: Bool { available ?? true }

        public init(
            id: String, ingredientId: String?, label: String, quantityG: Double, cookingMethod: String,
            measuredState: String, energyKcal: Double? = nil, available: Bool? = nil
        ) {
            self.id = id
            self.ingredientId = ingredientId
            self.label = label
            self.quantityG = quantityG
            self.cookingMethod = cookingMethod
            self.measuredState = measuredState
            self.energyKcal = energyKcal
            self.available = available
        }

        private enum CodingKeys: String, CodingKey {
            case id, label, available
            case ingredientId = "ingredient_id"
            case quantityG = "quantity_g"
            case cookingMethod = "cooking_method"
            case measuredState = "measured_state"
            case energyKcal = "energy_kcal"
        }
    }

    public struct Totals: Codable, Equatable, Sendable {
        public var energyKcal: Double
        public var proteinG: Double
        public var carbohydratesG: Double
        public var fatG: Double

        public init(energyKcal: Double, proteinG: Double, carbohydratesG: Double, fatG: Double) {
            self.energyKcal = energyKcal
            self.proteinG = proteinG
            self.carbohydratesG = carbohydratesG
            self.fatG = fatG
        }

        private enum CodingKeys: String, CodingKey {
            case energyKcal = "energy_kcal"
            case proteinG = "protein_g"
            case carbohydratesG = "carbohydrates_g"
            case fatG = "fat_g"
        }
    }

    public var version: Int
    /// The meal's id, which is also the vault record id. Lowercase UUID.
    public var id: String
    public var savedAt: Double
    /// Last edit; the newer side wins when two devices edited the same meal.
    public var updatedAt: Double
    public var items: [Item]
    public var totals: Totals
    /// v2: `breakfast`, `lunch`, `dinner` or `snack`. Absent in v1; readers then derive it from `saved_at`.
    public var slot: String?
    /// v2: every nutrient the engine returned for the meal, keyed by API field name. Absent in v1.
    public var nutrients: NutrientTotals?

    public init(
        id: String, savedAt: Double, updatedAt: Double, items: [Item], totals: Totals,
        slot: String? = nil, nutrients: NutrientTotals? = nil
    ) {
        self.version = Self.version
        self.id = id
        self.savedAt = savedAt
        self.updatedAt = updatedAt
        self.items = items
        self.totals = totals
        self.slot = slot
        self.nutrients = nutrients
    }

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case id, items, totals, slot, nutrients
        case savedAt = "saved_at"
        case updatedAt = "updated_at"
    }
}

public enum MealRecordError: Error, Equatable, Sendable {
    case malformed
    /// Written by a newer version of the app: leave it alone rather than overwrite what cannot be read.
    case unsupportedVersion(Int)
    /// The payload names another meal than the record it arrived in: a swapped record.
    case idMismatch
}

public func encodeMealRecord(_ meal: MealRecordPayload) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(meal)
}

public func decodeMealRecord(_ plaintext: Data, expectedId: String) throws(MealRecordError) -> MealRecordPayload {
    let meal: MealRecordPayload
    do { meal = try JSONDecoder().decode(MealRecordPayload.self, from: plaintext) } catch { throw .malformed }
    guard MealRecordPayload.readableVersions.contains(meal.version) else { throw .unsupportedVersion(meal.version) }
    guard meal.id == expectedId else { throw .idMismatch }
    return meal
}
