// SPDX-License-Identifier: MPL-2.0

/// One way an ingredient can be portioned, as Knowledge describes it.
///
/// `grams` is what the step ultimately resolves to; `volumeMl` is 0 for countable things and non-zero
/// for spoons and cups. Both are carried even where only one is read, because they arrive together
/// from `IngredientSuggestion.servingUnits` and dropping one here would mean re-fetching to get it
/// back.
/// `Decodable` and not `Codable`: this module never writes JSON, and `Encodable` would imply it does.
/// Conformance lives here rather than on an app-layer mirror so `IngredientSuggestion` can synthesise
/// its own — and note that `Decodable` is Swift *standard library*. Only `JSONDecoder` is Foundation,
/// and that stays in the app layer, which is what keeps this module import-free and Linux-compilable.
public struct ServingUnit: Equatable, Sendable, Decodable {
    public let unit: String
    public let labelFr: String
    public let volumeMl: Double
    public let grams: Double

    public init(unit: String, labelFr: String, volumeMl: Double, grams: Double) {
        self.unit = unit
        self.labelFr = labelFr
        self.volumeMl = volumeMl
        self.grams = grams
    }

    /// The one unit kind that can be counted rather than measured. `build-anchors` needs both this
    /// *and* a serving mode of "item" before it will count anything.
    public var isItem: Bool { unit == "item" }
}

/// One rung of the portion ladder.
///
/// Two shapes rather than one with optional fields, because the two are read differently everywhere:
/// a factor step scales the base portion and carries a ready-made label, a unit step multiplies a
/// unit weight and has its label built from the count. `step-raw-weight` puts it plainly — unit steps
/// "IGNORE the base portion entirely".
public enum ScaleStep: Equatable, Sendable {
    case factor(factor: Double, label: String)
    case unit(unit: ServingUnit, count: Double)
}
