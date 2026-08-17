// SPDX-License-Identifier: MPL-2.0

/// One row of the meal being composed: the output of `buildMealIngredient` and the subject of
/// `applyMethodChange`.
///
/// WHY `var` RATHER THAN `let`
/// The house rule is `let` by default, and this is the documented exception. `applyMethodChange` is
/// specified as `{ ...ingredient, cookingMethod, quantity }` — a copy with three fields replaced — and
/// with seventeen `let` fields that becomes a seventeen-argument initialiser call at each of four
/// branches, where a single mis-ordered argument compiles and silently swaps two values. `var` on a
/// struct keeps the value semantics that matter: `var copy = row` copies, so the caller's row is never
/// mutated. Immutability is preserved where it counts; only the spelling changes.
///
/// WEIGHT SEMANTICS, WHICH ARE THE EASY THING TO GET WRONG
/// `quantity` alone is ambiguous — `measuredState` says whether it is a raw or a cooked weight, and
/// `basePortionG` is always the raw anchor the portion controls scale from. A yield factor converts
/// between the two and is applied in exactly one direction: raw base to cooked weight. Read
/// `quantity` without `measuredState` and you will eventually divide by a yield factor twice.
/// `Identifiable` because the row genuinely has an identity — `id` survives every edit, including a
/// method change, which is what lets a list keep a row's position and focus while its weight is
/// recomputed. Stdlib protocol, so it costs the module nothing.
public struct MealIngredient: Equatable, Sendable, Decodable, Identifiable {
    public var id: String
    public var label: String
    public var ingredientId: String
    public var cookingMethod: String
    public var quantity: Double
    public var unit: String
    public var measuredState: String
    /// The raw anchor. Never a cooked weight, whatever `measuredState` says about `quantity`.
    public var basePortionG: Double
    /// Multiplier on `basePortionG`. `1` means "one portion"; `0` means the user typed a weight
    /// directly and the portion ladder no longer describes this row — which is why every branch of
    /// `applyMethodChange` tests `> 0` rather than truthiness.
    public var portionFactor: Double
    public var servingUnits: [ServingUnit]
    public var selectedUnit: ServingUnit?
    public var unitCount: Double
    public var displayUnit: String
    public var canEatRaw: Bool?
    public var yieldFactors: [String: Double]
    public var imageUrl: String?
    public var servingMode: String?

    public init(
        id: String,
        label: String,
        ingredientId: String,
        cookingMethod: String,
        quantity: Double,
        unit: String,
        measuredState: String,
        basePortionG: Double,
        portionFactor: Double,
        servingUnits: [ServingUnit],
        selectedUnit: ServingUnit?,
        unitCount: Double,
        displayUnit: String,
        canEatRaw: Bool?,
        yieldFactors: [String: Double],
        imageUrl: String?,
        servingMode: String?
    ) {
        self.id = id
        self.label = label
        self.ingredientId = ingredientId
        self.cookingMethod = cookingMethod
        self.quantity = quantity
        self.unit = unit
        self.measuredState = measuredState
        self.basePortionG = basePortionG
        self.portionFactor = portionFactor
        self.servingUnits = servingUnits
        self.selectedUnit = selectedUnit
        self.unitCount = unitCount
        self.displayUnit = displayUnit
        self.canEatRaw = canEatRaw
        self.yieldFactors = yieldFactors
        self.imageUrl = imageUrl
        self.servingMode = servingMode
    }
}
