// SPDX-License-Identifier: MPL-2.0

/// Renders a number the way the French UI writes it: a decimal comma, and no decimal part at all on a
/// whole number.
///
/// **Do not reach for `NumberFormatter` here.** A locale-aware formatter is the obvious tool and the
/// wrong one: it inserts thousands separators, and which separator it picks — a space, a narrow
/// no-break space, nothing — varies by platform and by OS version. That turns a rendering rule into
/// something that depends on the device a user happens to hold. The contract pins the rule as
/// literally "stringify, then replace the dot with a comma", which is why this is string handling
/// rather than a configured formatter.
///
/// Pinned by the `french-number` suite of the shared behavioural corpus, which the sandbox and Android
/// assert against too.
public func formatFrenchNumber(_ value: Double) -> String {
    // A whole number renders "2" and not "2,0", so the integer branch comes first. The Int conversion
    // matches roundHalfUp, which makes the same assumption: these are human food quantities, nowhere
    // near the range where the conversion would trap.
    if value == value.rounded() {
        return String(Int(value))
    }
    // Character-mapped rather than replacingOccurrences, which would pull in Foundation. This module
    // is stdlib-only on purpose — it is the part CI compiles on Linux, and the fewer of its
    // behaviours come from a platform's Foundation, the less there is to diverge.
    return String(String(value).map { $0 == "." ? "," : $0 })
}
