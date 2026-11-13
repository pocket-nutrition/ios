// SPDX-License-Identifier: MPL-2.0

/// Renders a number the way the English UI writes it: a decimal point, and no decimal part at all on
/// a whole number — the mirror image of `formatFrenchNumber`.
///
/// **Do not reach for `NumberFormatter` here**, for the same reason `formatFrenchNumber` does not:
/// a locale-aware formatter inserts thousands separators that vary by platform and OS version. The
/// rule is pinned as "stringify, then leave the dot alone", which needs no formatter at all.
///
/// Pinned by the `english-number` suite of the shared behavioural corpus.
public func formatEnglishNumber(_ value: Double) -> String {
    if value == value.rounded() {
        return String(Int(value))
    }
    return String(value)
}

/// Formats `value` in whichever language `lang` names, defaulting to French for anything that is not
/// `"en"`. The one dispatcher every call site routes through — adding a third language means adding
/// a case here, not hunting down every `formatFrenchNumber` call across the app a second time.
public func formatNumber(_ value: Double, lang: String) -> String {
    lang == "en" ? formatEnglishNumber(value) : formatFrenchNumber(value)
}
