// SPDX-License-Identifier: MPL-2.0

/// Category glyph for a curated ingredient, which never carries a product photo.
///
/// Open Food Facts supplies a front image for roughly four fifths of its products; the knowledge base
/// has no image field at all. A row that draws only `imageUrl` therefore gives every packaged product a
/// photograph and every curated ingredient a blank slot — which makes the industrial result look more
/// trustworthy than the reference one, the opposite of what this app is for. This fills the curated slot
/// from data already on the wire.
///
/// The vocabulary is closed: 21 values, enumerated in
/// `pocket-nutrition-knowledge/schemas/ingredient.schema.json`. Three are deliberately unmapped and
/// return nil rather than a poor guess, following the same rule as `servingUnitEmoji` — a wrong icon is
/// worse than none, and nil falls back to the neutral thumbnail placeholder the row already has for a
/// missing photo. `sauce` is the notable one: it is the second-largest group in the catalogue, and no
/// glyph reads as "sauce" rather than as a jar, a bottle, or the honey already taken by `sweetener`.
///
/// Products and recipes are always `"other"` server-side, so this never distinguishes a product from an
/// ingredient — `isProduct` does that.
///
/// Pinned entry by entry by the `food-group-icon` suite of the shared behavioural corpus.
public func foodGroupIcon(_ foodGroup: String?) -> String? {
    guard let foodGroup, !foodGroup.isEmpty else { return nil }
    return foodGroupIcons[foodGroup]
}

/// Every glyph is distinct, and that is a constraint rather than a coincidence: two groups sharing one
/// icon would render as the same thing in a list whose whole purpose is telling rows apart. Two
/// near-misses were rejected for collisions elsewhere in the UI — 🍲 already marks a recipe row, so
/// `prepared_dish` takes 🍱; and 🥛 is the `glass` serving unit, so `dairy` takes 🧀.
private let foodGroupIcons: [String: String] = [
    "meat": "🥩",
    "processed_meat": "🥓",
    "fish": "🐟",
    "shellfish": "🦐",
    "egg": "🥚",
    "dairy": "🧀",
    "vegetable": "🥦",
    "fruit": "🍎",
    "cereal": "🌾",
    "legume": "🫘",
    "nut_seed": "🥜",
    "fat": "🧈",
    "spice_herb": "🌿",
    "sweetener": "🍯",
    "baked_good": "🥐",
    "beverage": "🥤",
    "alcohol": "🍷",
    "prepared_dish": "🍱"
    // sauce, seaweed and other are intentionally absent — see foodGroupIcon.
]
