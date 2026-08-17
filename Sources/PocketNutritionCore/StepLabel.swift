// SPDX-License-Identifier: MPL-2.0

/// The label on one rung of the portion ladder.
///
/// A factor step is already labelled — `buildAnchors` gave it "Petite" or "¼" — so it is returned
/// verbatim and nothing is formatted.
///
/// A unit step is built: `"<count> <unit>"`, where the count becomes a typographic fraction when the
/// table has one, and the unit is pluralised by `frenchPlural` rather than by a second copy of that
/// rule living here. That delegation is deliberate and the corpus says so: the `unit-count-two`
/// vector exists specifically to tie this suite to the plural rule, so that fixing French plurals in
/// Knowledge later fixes them here too.
///
/// Pinned by the `step-label` suite of the shared behavioural corpus.
public func stepLabel(_ step: ScaleStep) -> String {
    switch step {
    case .factor(_, let label):
        return label
    case .unit(let unit, let count):
        return "\(countLabel(count)) \(frenchPlural(unit.labelFr, count: count))"
    }
}

/// "½ carotte" reads better on a button than "0,5 carotte".
///
/// **Keyed on the count, not on the factor** — the corpus is explicit about that. The same 0.5 can
/// arrive from a half-item step or from a factor step against a doubled base, and only the former is
/// a half of anything the label names.
///
/// A count with no entry falls back to `formatFrenchNumber`, so 3 renders "3" and an unexpected 2.5
/// renders "2,5" rather than breaking the row.
private func countLabel(_ count: Double) -> String {
    if let fraction = fractions[count] { return fraction }
    return formatFrenchNumber(count)
}

private let fractions: [Double: String] = [
    0.25: "¼",
    0.33: "⅓",
    0.5: "½",
    0.75: "¾",
]
