// SPDX-License-Identifier: MPL-2.0

/// The label on one rung of the portion ladder.
///
/// A factor step is already labelled — `buildAnchors` gave it "Petite" or "¼" — so it is returned
/// verbatim and nothing is formatted.
///
/// A unit step is built: `"<count> <unit>"`, where the count becomes a typographic fraction when the
/// table has one, and the unit is pluralised by `pluralize` rather than by a second copy of that rule
/// living here. That delegation is deliberate and the corpus says so: the `unit-count-two` vector
/// exists specifically to tie this suite to the plural rule, so that fixing French plurals in
/// Knowledge later fixes them here too.
///
/// Pinned by the `step-label`/`step-label-en` suites of the shared behavioural corpus.
public func stepLabel(_ step: ScaleStep, lang: String) -> String {
    switch step {
    case .factor(_, let label):
        return label
    case .unit(let unit, let count):
        let label = pickLocalized(unit.labels, preferring: lang) ?? unit.unit
        return "\(countLabel(count, lang: lang)) \(pluralize(label, count: count, lang: lang))"
    }
}

/// "½ carotte"/"½ carrots" reads better on a button than "0,5 carotte"/"0.5 carrots".
///
/// **Keyed on the count, not on the factor** — the corpus is explicit about that. The same 0.5 can
/// arrive from a half-item step or from a factor step against a doubled base, and only the former is
/// a half of anything the label names.
///
/// A count with no entry falls back to `formatNumber`, so 3 renders "3" and an unexpected 2.5
/// renders "2,5"/"2.5" rather than breaking the row.
private func countLabel(_ count: Double, lang: String) -> String {
    if let fraction = fractions[count] { return fraction }
    return formatNumber(count, lang: lang)
}

private let fractions: [Double: String] = [
    0.25: "¼",
    0.33: "⅓",
    0.5: "½",
    0.75: "¾",
]
