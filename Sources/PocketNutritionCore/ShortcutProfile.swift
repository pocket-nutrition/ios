// SPDX-License-Identifier: MPL-2.0

/// One quick button under the value field.
///
/// `emoji` is optional and genuinely absent rather than empty for an unrecognised unit — the corpus
/// emits no `emoji` key at all in that case, and the distinction matters: a port that substitutes ""
/// or a placeholder glyph renders a gap where the design expects nothing.
public enum Shortcut: Equatable, Sendable {
    case multiplier(label: String, factor: Double)
    case increment(label: String, emoji: String?, grams: Int)
}

/// The row of at most four quick buttons under the value field.
///
/// Two shapes:
///
/// - **No usable serving unit** → the three base-portion multipliers, Demi / 1 Part / Double. Three
///   entries, not four: no anchor is added on this path, because the multipliers already include 1.
/// - **At least one** → a single "1 Part" anchor followed by up to three Knowledge increments, in
///   whatever order Knowledge returned them. They are deliberately not sorted by weight.
///
/// Two filters decide "usable". The item unit is excluded, because a countable thing is already
/// covered by the multipliers and offering "1 carotte" beside "1 Part" is the same button twice. And
/// a unit whose weight rounds below 1 is dropped, because a 0,2 g pinch is a button that adds
/// nothing. Either filter can empty the list, and when it does the multipliers come back — which is
/// how the stated invariant holds: **the result always has between 2 and 4 entries.**
///
/// Pinned by the `shortcut-profile` suite of the shared behavioural corpus.
public func shortcutProfile(servingUnits: [ServingUnit], displayUnit: String) -> [Shortcut] {
    let increments = servingUnits
        .filter { !$0.isItem }
        .map { (unit: $0, grams: roundHalfUp(measure($0, displayUnit: displayUnit))) }
        .filter { $0.grams >= 1 }
        .prefix(maximumIncrements)
        .map { Shortcut.increment(label: $0.unit.labelFr, emoji: servingUnitEmoji($0.unit.unit), grams: $0.grams) }

    guard !increments.isEmpty else { return baseMultipliers }
    return [Shortcut.multiplier(label: "1 Part", factor: 1)] + increments
}

/// Which of the two weights a unit contributes.
///
/// **A naming wart worth knowing before porting.** For a volume food the increment comes from
/// `volumeMl` while the output field is still called `grams`. Reading `grams` for a millilitre food
/// gives 0, the unit is then dropped as sub-gram, and the row silently degrades to the multipliers —
/// no error anywhere.
private func measure(_ unit: ServingUnit, displayUnit: String) -> Double {
    displayUnit == "ml" ? unit.volumeMl : unit.grams
}

/// Rounded once, here, with the half-up rule: 15,5 g becomes 16 rather than 15. The unit keeps its
/// precise weight in Knowledge; only the button is rounded.
///
/// The fallback path when nothing is usable. Note these three labels differ from the anchor ladder's
/// — `portionAnchors.half` is "Demi" and `.onePart` is "1 Part", where the ladder uses "Petite" and
/// "1 part" with a lowercase p. Two similar-looking sets that are not the same set.
private let baseMultipliers: [Shortcut] = [
    .multiplier(label: "Demi", factor: 0.5),
    .multiplier(label: "1 Part", factor: 1),
    .multiplier(label: "Double", factor: 2),
]

/// One anchor plus three increments fills the row.
private let maximumIncrements = 3

/// Cosmetic icon per serving-unit type, hardcoded because this is a pure function over a closed
/// vocabulary — and pinned entry by entry by the `serving-unit-emoji` suite, so drift fails a test.
///
/// Seven of the ten units in `pocket-nutrition-knowledge/serving_unit_types.yaml` carry a glyph.
/// `shot`, `bowl` and `scoop` deliberately do not: none has an unambiguous glyph, 🥣 is already the
/// cup, and a wrong icon is worse than none. A unit outside the vocabulary is treated the same way, so
/// nothing here ever needs a placeholder.
///
/// Before contracts 1.3.0 the corpus pinned only three of these entries, so this table was shipped
/// incomplete. Filling it in from the sandbox was not an option — that repo was AGPL-3.0 to this one's
/// MPL-2.0 — so the map was pinned upstream as its own suite instead. Adding a glyph still means a
/// vector first.
public func servingUnitEmoji(_ unit: String) -> String? {
    switch unit {
    case "pinch": return "🤏"
    case "teaspoon", "tablespoon": return "🥄"
    case "cup": return "🥣"
    case "handful": return "✊"
    case "small_handful": return "🤲"
    case "glass": return "🥛"
    default: return nil
    }
}
