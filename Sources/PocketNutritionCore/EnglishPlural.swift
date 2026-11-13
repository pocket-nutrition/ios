// SPDX-License-Identifier: MPL-2.0

/// Pluralises an English ingredient label for a count.
///
/// **A genuinely different rule from `frenchPlural`, not a translation of it.** English keeps the
/// singular only at exactly 1 — "1.5 carrots" and "0.5 carrots" are both plural — where French keeps
/// the singular below 2. A port that reuses `frenchPlural`'s threshold for English text produces
/// "1.5 carrot", which is wrong.
///
/// **This is deliberately naive, and every client is required to be naive in the same way**, for the
/// same reason `frenchPlural` is: the real forms belong in Knowledge, under `set_ingredient_plural`.
///
/// Pinned by the `english-plural` suite of the shared behavioural corpus.
public func englishPlural(_ label: String, count: Double) -> String {
    guard count != 1, !label.hasSuffix("s") else { return label }
    return label + "s"
}

/// Pluralises `label` for `count` in whichever language `lang` names, defaulting to French for
/// anything that is not `"en"`. The one dispatcher every call site routes through.
public func pluralize(_ label: String, count: Double, lang: String) -> String {
    lang == "en" ? englishPlural(label, count: count) : frenchPlural(label, count: count)
}
