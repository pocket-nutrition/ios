// SPDX-License-Identifier: MPL-2.0

import Testing

import PocketNutritionCore

/// Asserts the meal-logging helpers against their five suites of the shared corpus.
@Suite("meal-logging vectors")
struct MealLoggingVectorTests {

    /// Loads a suite, checks its size against index.json, and returns its cases.
    private func cases(_ name: String) throws -> [VectorCorpus.Case] {
        let suite = try VectorCorpus.load(name)
        #expect(suite.cases.count == (try VectorCorpus.index().suites[name]), "\(name) case count disagrees with index.json")
        #expect(!suite.cases.isEmpty, "the \(name) suite is empty")
        return suite.cases
    }

    @Test("meal-slot")
    func slot() throws {
        for c in try cases("meal-slot") {
            let minutes = try #require(VectorCorpus.double(c.input["minutes"]), "\(c.id)")
            #expect(mealSlot(forMinutes: minutes).rawValue == c.expected as? String, "\(c.id): \(c.why)")
        }
    }

    @Test("meal-slot-default-time")
    func defaultTime() throws {
        for c in try cases("meal-slot-default-time") {
            let slot = try #require((c.input["slot"] as? String).flatMap(MealSlot.init(rawValue:)), "\(c.id)")
            #expect(defaultMinutes(for: slot) == VectorCorpus.int(c.expected), "\(c.id): \(c.why)")
            #expect(mealSlot(forMinutes: Double(defaultMinutes(for: slot))) == slot, "\(c.id): round trip")
        }
    }

    @Test("scale-dish-quantity")
    func scale() throws {
        for c in try cases("scale-dish-quantity") {
            let q = try #require(VectorCorpus.double(c.input["quantityG"]))
            let servings = try #require(VectorCorpus.double(c.input["servings"]))
            let parts = try #require(VectorCorpus.double(c.input["parts"]))
            #expect(scaleDishQuantity(q, servings: servings, parts: parts) == VectorCorpus.double(c.expected), "\(c.id): \(c.why)")
        }
    }

    @Test("parse-quick-add-kcal")
    func quickAdd() throws {
        for c in try cases("parse-quick-add-kcal") {
            let query = try #require(c.input["query"] as? String)
            #expect(parseQuickAddKcal(query) == VectorCorpus.int(c.expected), "\(c.id): \(c.why)")
        }
    }

    @Test("rank-recents")
    func recents() throws {
        for c in try cases("rank-recents") {
            let rawUses = try #require(c.input["uses"] as? [[String: Any]])
            let uses = try rawUses.map { u in
                LoggedUse(
                    key: try #require(u["key"] as? String),
                    slot: try #require((u["slot"] as? String).flatMap(MealSlot.init(rawValue:))),
                    at: try #require(VectorCorpus.double(u["at"]))
                )
            }
            let slot = try #require((c.input["slot"] as? String).flatMap(MealSlot.init(rawValue:)))
            let limit = try #require(VectorCorpus.int(c.input["limit"]))
            #expect(rankRecents(uses, slot: slot, limit: limit) == (c.expected as? [String]), "\(c.id): \(c.why)")
        }
    }
}
