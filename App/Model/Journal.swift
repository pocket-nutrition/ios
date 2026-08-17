// SPDX-License-Identifier: MPL-2.0

import Foundation
import Observation

/// One food inside a meal, as the user is composing it or as it was saved.
///
/// `quantityG` is grams and only grams for now. The API's `unit` field accepts more, and
/// `IngredientSuggestion.servingUnits` describes them, but rendering a unit picker needs
/// `shortcut-profile` and `step-label`. Both are now ported and vector-verified, so this is no longer
/// blocked — it is simply not built yet, and the portion-scale UI is where it lands.
struct MealItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var ingredientId: String?
    var label: String
    var quantityG: Double
    var cookingMethod: String
    var measuredState: String

    func asRequest() -> FoodItemRequest {
        FoodItemRequest(
            name: label,
            quantity: quantityG,
            unit: "g",
            cookingMethod: cookingMethod,
            measuredState: measuredState,
            ingredientId: ingredientId
        )
    }
}

/// The four macros the journal shows. Deliberately not the full thirty-nutrient response: a saved
/// meal is a summary, and storing everything would grow the file without the UI ever reading it.
struct Macros: Codable, Hashable, Sendable {
    var energyKcal: Double
    var proteinG: Double
    var carbohydratesG: Double
    var fatG: Double

    static let zero = Macros(energyKcal: 0, proteinG: 0, carbohydratesG: 0, fatG: 0)

    static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(
            energyKcal: lhs.energyKcal + rhs.energyKcal,
            proteinG: lhs.proteinG + rhs.proteinG,
            carbohydratesG: lhs.carbohydratesG + rhs.carbohydratesG,
            fatG: lhs.fatG + rhs.fatG
        )
    }

    init(energyKcal: Double, proteinG: Double, carbohydratesG: Double, fatG: Double) {
        self.energyKcal = energyKcal
        self.proteinG = proteinG
        self.carbohydratesG = carbohydratesG
        self.fatG = fatG
    }

    init(_ profile: NutritionalProfile) {
        self.init(
            energyKcal: profile.energyKcal,
            proteinG: profile.proteinG,
            carbohydratesG: profile.carbohydratesG,
            fatG: profile.fatG
        )
    }
}

/// A meal the user chose to keep.
struct SavedMeal: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var savedAt: Date
    var items: [MealItem]
    var totals: Macros
}

/// The on-disk shape, versioned from the first write.
///
/// `version` exists so the next schema change can migrate rather than discard. Adding it later would
/// leave the first generation of files with nothing to branch on, which is the situation that forces
/// "delete the user's data on upgrade".
private struct JournalFile: Codable {
    var version: Int
    var meals: [SavedMeal]
}

/// The local diary. This is the app's one piece of user data, and it never leaves the device.
///
/// WHY A JSON FILE RATHER THAN CORE DATA OR SWIFTDATA
/// The whole store is a list of meals appended to and occasionally deleted from: no relationships, no
/// queries, no partial loading. A file read at launch and rewritten on change is the entire
/// requirement, and it keeps the app free of a persistence framework whose migration story would then
/// need managing. Revisit when the journal needs querying rather than listing.
@Observable
final class JournalStore {

    private(set) var meals: [SavedMeal] = []

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("journal.json")
        }
        // ISO-8601 rather than the default numeric timestamp, so the file stays legible and survives a
        // change of decoding strategy.
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    /// Newest first, the order the journal lists them in.
    var mealsNewestFirst: [SavedMeal] {
        meals.sorted { $0.savedAt > $1.savedAt }
    }

    /// Grouped by calendar day for the section headers, newest day first.
    var mealsByDay: [(day: Date, meals: [SavedMeal])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: mealsNewestFirst) {
            calendar.startOfDay(for: $0.savedAt)
        }
        return grouped
            .map { (day: $0.key, meals: $0.value) }
            .sorted { $0.day > $1.day }
    }

    func save(items: [MealItem], totals: Macros, at date: Date = Date()) {
        meals.append(SavedMeal(savedAt: date, items: items, totals: totals))
        persist()
    }

    func delete(_ meal: SavedMeal) {
        meals.removeAll { $0.id == meal.id }
        persist()
    }

    /// Replaces an existing entry's items and totals in place, keeping its original `savedAt`.
    func update(id: UUID, items: [MealItem], totals: Macros) {
        guard let index = meals.firstIndex(where: { $0.id == id }) else { return }
        meals[index].items = items
        meals[index].totals = totals
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let file = try? decoder.decode(JournalFile.self, from: data) else {
            // A file that will not decode is set aside, not overwritten: it is the user's only copy of
            // their diary, and an undecodable file is more often a schema change than real damage.
            // Renaming leaves it recoverable rather than silently destroyed by the next save.
            let salvage = fileURL.deletingLastPathComponent()
                .appendingPathComponent("journal.unreadable.json")
            try? FileManager.default.removeItem(at: salvage)
            try? FileManager.default.moveItem(at: fileURL, to: salvage)
            return
        }
        meals = file.meals
    }

    private func persist() {
        let file = JournalFile(version: 1, meals: meals)
        guard let data = try? encoder.encode(file) else { return }
        // Atomic, so an interrupted write cannot truncate the diary.
        try? data.write(to: fileURL, options: .atomic)
    }
}
