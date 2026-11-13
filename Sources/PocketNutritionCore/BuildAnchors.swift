// SPDX-License-Identifier: MPL-2.0

/// The coarse anchor set behind the collapsed-row summary — the handful of portions offered as
/// one-tap buttons.
///
/// Two ladders, and which one applies is not a matter of taste:
///
/// - **Countable foods get counted.** ½ · 1 · 2 · 3 carottes reads the way a person thinks about
///   carrots. This needs `servingMode == "item"` **and** an actual item unit to count. Branching on
///   the mode alone is the trap the corpus names: an ingredient can be marked countable while
///   offering only a tablespoon, and a port that trusts the mode returns an empty ladder or traps.
/// - **Everything else is scaled** by the five named factors.
///
/// Both ladders drop rungs that resolve too small to be worth a button, at different thresholds: 5 g
/// for an item, 1 g for a factor. Half a hazelnut is 4 g and is not a portion anyone wants to tap;
/// a quarter of a 2 g base portion is 0.5 g and is not either. The filters exist so that no button
/// resolves to nothing, which is why they are part of the contract rather than a nicety.
///
/// Pinned by the `build-anchors`/`build-anchors-en` suites of the shared behavioural corpus.
public func buildAnchors(
    basePortionG: Double,
    servingUnits: [ServingUnit],
    servingMode: String?,
    lang: String
) -> [ScaleStep] {
    if servingMode == "item", let item = servingUnits.first(where: { $0.isItem }) {
        return itemCounts
            .filter { $0 * item.grams >= minimumItemGrams }
            .map { .unit(unit: item, count: $0) }
    }

    return namedFactors(for: lang)
        .filter { $0.factor * basePortionG >= minimumFactorGrams }
        .map { .factor(factor: $0.factor, label: $0.label) }
}

/// The item ladder. Half an item is offered, quarters are not — you can halve a carrot, not quarter
/// one usefully.
private let itemCounts: [Double] = [0.5, 1, 2, 3]

/// The weight ladder, per language.
///
/// These five labels are also `portionAnchors.quarter` / `.small` / `.one` / `.large` / `.double` in
/// the copy deck. They are written here rather than injected because the corpus pins them as part of
/// this function's output — the vector test is what keeps the two copies honest, and it fails loudly
/// if the deck is reworded without the vectors following. Same rule for the English set against
/// `build-anchors-en`.
///
/// Internal rather than private because `describeQuantity` snaps its portion ratio to the same five.
/// One copy per language: a rung renamed here must change both surfaces at once, which is the
/// behaviour a user would expect and the opposite of what two lists would give.
func namedFactors(for lang: String) -> [(factor: Double, label: String)] {
    lang == "en" ? namedFactorsEn : namedFactorsFr
}

private let namedFactorsFr: [(factor: Double, label: String)] = [
    (0.25, "¼"),
    (0.5, "Petite"),
    (1, "1 part"),
    (1.5, "Grande"),
    (2, "Double"),
]

private let namedFactorsEn: [(factor: Double, label: String)] = [
    (0.25, "¼"),
    (0.5, "Small"),
    (1, "1 serving"),
    (1.5, "Large"),
    (2, "Double"),
]

/// A rung below this resolves to a button not worth offering. Different for the two ladders because
/// a countable thing at 4 g is absurd where a measured 4 g is ordinary.
private let minimumItemGrams: Double = 5
private let minimumFactorGrams: Double = 1
