// SPDX-License-Identifier: MPL-2.0

import Foundation
import Observation
import PocketNutritionCore

/// A meal the person saved to apply again: its ingredients, quantities and cooking, for `servings`
/// portions. Never its nutrition: that is recomputed through `POST /nutrition` each time it is applied,
/// so model improvements reach saved dishes and cooking keeps being accounted for.
struct Dish: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    /// How many portions the saved quantities make (a gratin for 4 is saved once, eaten a quarter at a time).
    var servings: Int
    var items: [MealItem]
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var useCount: Int = 0
}

/// What makes logging fast: saved dishes, and the ★ pins on dishes and on recent foods.
///
/// Local only, by decision (2026-11-02): dishes are "made on the phone". A JSON file beside the journal,
/// written atomically. Not synced through the vault yet; that would need the journal sync generalised to
/// other record types.
@MainActor
@Observable
final class MealShortcutsStore {

    private struct FileContents: Codable {
        var version = 1
        var dishes: [Dish]
        var pinned: [String]
    }

    private(set) var dishes: [Dish] = []
    private(set) var pinned: Set<String> = []

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("meal-shortcuts.json")
        }
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    /// Dishes to offer: pinned first, then most recently used (or created).
    var dishesByRelevance: [Dish] {
        dishes.sorted { a, b in
            let pa = isPinned(Self.dishKey(a.id)), pb = isPinned(Self.dishKey(b.id))
            if pa != pb { return pa }
            return (a.lastUsedAt ?? a.createdAt) > (b.lastUsedAt ?? b.createdAt)
        }
    }

    @discardableResult
    func saveDish(name: String, servings: Int, items: [MealItem]) -> Dish {
        let now = Date()
        let dish = Dish(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines), servings: max(1, servings),
            items: items.filter { !$0.isQuickAdd }.map { var copy = $0; copy.id = UUID(); return copy },
            createdAt: now, updatedAt: now)
        dishes.append(dish)
        persist()
        return dish
    }

    func updateItems(of id: UUID, to items: [MealItem]) {
        guard let index = dishes.firstIndex(where: { $0.id == id }) else { return }
        dishes[index].items = items.filter { !$0.isQuickAdd }
        dishes[index].updatedAt = Date()
        persist()
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = dishes.firstIndex(where: { $0.id == id }) else { return }
        dishes[index].name = trimmed
        dishes[index].updatedAt = Date()
        persist()
    }

    func delete(_ id: UUID) {
        dishes.removeAll { $0.id == id }
        pinned.remove(Self.dishKey(id))
        persist()
    }

    func markUsed(_ id: UUID) {
        guard let index = dishes.firstIndex(where: { $0.id == id }) else { return }
        dishes[index].lastUsedAt = Date()
        dishes[index].useCount += 1
        persist()
    }

    func isPinned(_ key: String) -> Bool { pinned.contains(key) }

    func togglePin(_ key: String) {
        if pinned.contains(key) { pinned.remove(key) } else { pinned.insert(key) }
        persist()
    }

    nonisolated static func dishKey(_ id: UUID) -> String { "dish:\(id.uuidString.lowercased())" }

    /// A recent food: the same ingredient cooked and weighed the same way.
    nonisolated static func foodKey(_ item: MealItem) -> String? {
        guard let ingredientId = item.ingredientId, !item.isQuickAdd else { return nil }
        return "food:\(ingredientId)|\(item.cookingMethod)|\(item.measuredState)"
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let contents = try? decoder.decode(FileContents.self, from: data)
        else { return }
        dishes = contents.dishes
        pinned = Set(contents.pinned)
    }

    private func persist() {
        let contents = FileContents(dishes: dishes, pinned: pinned.sorted())
        guard let data = try? encoder.encode(contents) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}

/// A food eaten before, as the empty search screen offers it: the last way it was logged.
struct RecentFood: Identifiable, Hashable {
    let key: String
    let item: MealItem
    var id: String { key }
}

extension JournalStore {
    /// Past foods ranked for [slot] (most eaten in that slot, then overall, then most recent), each with
    /// the quantity and cooking of its last use. Computed from the journal, never stored.
    func recentFoods(for slot: MealSlot, limit: Int) -> [RecentFood] {
        var uses: [LoggedUse] = []
        var latest: [String: (at: Date, item: MealItem)] = [:]
        for meal in meals {
            // An item the server could not compute is not offered again as a recent food.
            for item in meal.items where item.isAvailable {
                guard let key = MealShortcutsStore.foodKey(item) else { continue }
                uses.append(LoggedUse(key: key, slot: meal.effectiveSlot, at: meal.savedAt.timeIntervalSince1970))
                if latest[key].map({ meal.savedAt > $0.at }) ?? true { latest[key] = (meal.savedAt, item) }
            }
        }
        return rankRecents(uses, slot: slot, limit: limit).compactMap { key in
            latest[key].map { RecentFood(key: key, item: $0.item) }
        }
    }
}
