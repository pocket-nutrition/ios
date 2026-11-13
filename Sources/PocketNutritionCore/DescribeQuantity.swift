// SPDX-License-Identifier: MPL-2.0

/// One rung of the ladder as `describeQuantity` sees it: a label and the weight it resolves to.
///
/// Deliberately not `ScaleStep`. By the time a row is being summarised the steps have already been
/// resolved to weights, and carrying the factor/unit distinction this far would mean re-deriving
/// something the caller already knows.
public struct QuantityAnchor: Equatable, Sendable {
    public let label: String
    public let grams: Double

    public init(label: String, grams: Double) {
        self.label = label
        self.grams = grams
    }
}

/// What the row knows about the ingredient it is summarising.
public struct QuantityContext: Equatable, Sendable {
    /// Present in the corpus input and deliberately **not** the item branch's condition — see
    /// `describeQuantity`. Carried because the caller has it and a later suite may need it.
    public let servingMode: String?
    public let itemUnitG: Double?
    public let itemLabel: String?
    public let portionG: Double
    /// "g" or "ml". Drives both which weight is read and how it is rendered.
    public let displayUnit: String

    public init(
        servingMode: String? = nil,
        itemUnitG: Double? = nil,
        itemLabel: String? = nil,
        portionG: Double,
        displayUnit: String
    ) {
        self.servingMode = servingMode
        self.itemUnitG = itemUnitG
        self.itemLabel = itemLabel
        self.portionG = portionG
        self.displayUnit = displayUnit
    }
}

/// The two lines of the collapsed-row summary. `secondary` is empty, not nil, when there is nothing
/// to put under the headline.
public struct QuantityDescription: Equatable, Sendable {
    public let primary: String
    public let secondary: String

    public init(primary: String, secondary: String) {
        self.primary = primary
        self.secondary = secondary
    }
}

/// The collapsed-row quantity summary — the one line a user reads without expanding anything.
///
/// Three branches, tried in order:
///
/// 1. **On an anchor.** Within `max(2, grams × 4 %)` of one, show that anchor's clean label. The 2 g
///    floor is what keeps small portions usable: 4 % of a 16 g anchor is 0.64 g, a window nobody can
///    hit by dragging. When two anchors both fall inside tolerance the **nearest** wins, not the first
///    scanned — a port that returns on first match disagrees on that vector alone.
/// 2. **An "≈ descriptor" headline**, by item count when an item unit is known, otherwise by portion
///    ratio, snapping to a named anchor when within 8 %. That window is deliberately wider than the
///    4 % in branch 1: it is describing a neighbourhood, not claiming an exact hit.
/// 3. **Grams alone**, with an empty secondary line.
///
/// **The nesting in branch 2 is load-bearing.** The item path is an `if/else if`, not two independent
/// checks: below a quarter of an item, "≈ 0,1 carotte" is noise, so it falls through to grams — and
/// specifically *not* to the portion-ratio branch. Flattening those two into sibling conditions
/// changes what a 10 g sliver of carrot reads as.
///
/// Pinned by the `describe-quantity`/`describe-quantity-en` suites of the shared behavioural corpus.
public func describeQuantity(
    currentG: Double,
    anchors: [QuantityAnchor],
    context: QuantityContext,
    lang: String
) -> QuantityDescription {
    let weight = formatWeight(currentG, displayUnit: context.displayUnit)

    // ── 1. On an anchor ──────────────────────────────────────────────────────
    let withinTolerance = anchors.filter {
        abs(currentG - $0.grams) <= max(anchorFloorGrams, $0.grams * anchorTolerance)
    }
    if let nearest = withinTolerance.min(by: {
        abs(currentG - $0.grams) < abs(currentG - $1.grams)
    }) {
        return QuantityDescription(primary: nearest.label, secondary: weight)
    }

    // ── 2. An "≈ descriptor" headline ────────────────────────────────────────
    //
    // The item path is entered on having an item unit at all, NOT on servingMode. The corpus's
    // item-sliver case carries no servingMode and still takes this branch, which is what rules the
    // obvious reading out.
    if let itemUnitG = context.itemUnitG, let itemLabel = context.itemLabel, itemUnitG > 0 {
        let count = currentG / itemUnitG
        if count >= minimumItemCount {
            let rounded = roundToOneDecimal(count)
            let label = pluralize(itemLabel, count: rounded, lang: lang)
            return QuantityDescription(
                primary: "≈ \(formatNumber(rounded, lang: lang)) \(label)",
                secondary: weight
            )
        }
        // Deliberately falls through to branch 3, not to the portion ratio below.
    } else if context.portionG > 0 {
        let ratio = currentG / context.portionG
        if let named = namedFactors(for: lang).first(where: {
            abs(ratio - $0.factor) / $0.factor <= namedTolerance
        }) {
            return QuantityDescription(primary: "≈ \(named.label)", secondary: weight)
        }
        let rounded = roundToOneDecimal(ratio)
        // "portion"/"serving" is pluralised by the same rule as everything else in the active
        // language. No vector reaches a ratio of 2 or more, so this is the consistent choice rather
        // than a pinned one.
        let portionWord = lang == "en" ? "serving" : "portion"
        return QuantityDescription(
            primary: "≈ \(formatNumber(rounded, lang: lang)) \(pluralize(portionWord, count: rounded, lang: lang))",
            secondary: weight
        )
    }

    // ── 3. Grams alone ───────────────────────────────────────────────────────
    return QuantityDescription(primary: weight, secondary: "")
}

/// Two formats in one function, both user-visible: grams render "64g" with no space, millilitres
/// render "270 mL" with a space and a capital L. Not a typo on either side — it is what the contract
/// pins, and the sub-one guard reads "< 1g" / "< 1 mL" so a trace of an ingredient never shows "0g".
private func formatWeight(_ grams: Double, displayUnit: String) -> String {
    let isVolume = displayUnit == "ml"
    if grams < 1 { return isVolume ? "< 1 mL" : "< 1g" }
    return isVolume ? "\(roundHalfUp(grams)) mL" : "\(roundHalfUp(grams))g"
}

/// One decimal place, through the shared rounding rule rather than a formatter.
///
/// This is where the whole `rounding` suite earns its place: 80 g against a 64 g portion is exactly
/// 1.25, so this evaluates `roundHalfUp(12.5) / 10`. Half-up gives 1,3 and ties-to-even gives 1,2 —
/// no error either way, just two clients quietly disagreeing.
private func roundToOneDecimal(_ value: Double) -> Double {
    Double(roundHalfUp(value * 10)) / 10
}

private let anchorTolerance = 0.04
private let anchorFloorGrams = 2.0
private let namedTolerance = 0.08
/// Below a quarter of an item, "≈ 0,1 carotte" is noise rather than information.
private let minimumItemCount = 0.25
