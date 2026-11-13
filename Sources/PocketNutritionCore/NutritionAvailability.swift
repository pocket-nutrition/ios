// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Whether `POST /nutrition` could compute an item: its `available` field.
///
/// When it could not (`available: false`, `source: "unavailable"`), the server still answers the item,
/// with placeholder 0.0 macros and null nutrients. Those zeros are not a measurement: the item's
/// nutrients are unknown. The contract's own copy deck says so (`results.unavailable`: "Must NOT be
/// replaced by zeros").
///
/// Decoded on its own so the tolerance rule lives in one tested place: a response without the field
/// (a server older than the field) counts as available, which is what every item was before it existed.
public struct NutritionAvailability: Decodable, Equatable, Sendable {
    public let available: Bool

    public init(available: Bool) {
        self.available = available
    }

    private enum CodingKeys: String, CodingKey { case available }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        available = try container.decodeIfPresent(Bool.self, forKey: .available) ?? true
    }
}

/// One analysed item, as far as a total is concerned.
public protocol NutritionAnalysedItem {
    /// False when the server could not compute the item: its nutrients are unknown, not zero.
    var isAvailable: Bool { get }
    var nutrients: NutrientTotals { get }
}

extension Sequence where Element: NutritionAnalysedItem {
    /// The items a total may count. An unavailable item contributes nothing to any total, not even a 0
    /// that would make the total look complete.
    public var countable: [Element] { filter(\.isAvailable) }

    /// Every nutrient summed over the countable items only.
    public var countableNutrients: NutrientTotals {
        countable.map(\.nutrients).reduce(NutrientTotals.empty, +)
    }
}
