// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Every nutrient `POST /nutrition` returns for an item or a meal, keyed by its API field name
/// (`energyKcal`, `fiberG`, `vitaminB12Ug`…).
///
/// Kept so a saved meal stores everything the engine computed, not only the four macros the journal
/// shows today. An **unknown value is absent, never 0**: the reference database simply has no figure for
/// some nutrients of some foods, and treating that as zero would make a day look poorer in iron than it
/// was. Encoded as a flat JSON object of known keys.
public struct NutrientTotals: Codable, Hashable, Sendable {

    /// The 24 nutrient fields of `NutritionalProfileResponse`, in the schema's order.
    public static let keys: [String] = [
        "energyKcal", "proteinG", "fatG", "carbohydratesG", "fiberG", "waterG", "sugarsG",
        "calciumMg", "ironMg", "magnesiumMg", "sodiumMg", "vitaminCMg", "saturatedFatG",
        "monounsaturatedFatG", "polyunsaturatedFatG", "cholesterolMg", "potassiumMg", "phosphorusMg",
        "zincMg", "vitaminAUg", "vitaminDUg", "vitaminB6Mg", "vitaminB12Ug", "niacinMg",
    ]
    private static let known = Set(keys)

    public private(set) var values: [String: Double]

    /// Keeps only known keys with finite values.
    public init(_ values: [String: Double] = [:]) {
        self.values = values.filter { Self.known.contains($0.key) && $0.value.isFinite }
    }

    public static let empty = NutrientTotals()

    public subscript(key: String) -> Double? { values[key] }

    public var isEmpty: Bool { values.isEmpty }

    /// Sum of the known values: a nutrient is absent only when absent on both sides.
    public static func + (lhs: NutrientTotals, rhs: NutrientTotals) -> NutrientTotals {
        NutrientTotals(lhs.values.merging(rhs.values, uniquingKeysWith: +))
    }

    public func scaled(by ratio: Double) -> NutrientTotals {
        NutrientTotals(values.mapValues { $0 * ratio })
    }

    /// Reads the nutrient fields of an API profile object (other fields are ignored).
    public init(profileFrom decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        var values: [String: Double] = [:]
        for key in Self.keys {
            if let value = try container.decodeIfPresent(Double.self, forKey: AnyKey(key)) { values[key] = value }
        }
        self.init(values)
    }

    public init(from decoder: Decoder) throws {
        self.init(try decoder.singleValueContainer().decode([String: Double].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
