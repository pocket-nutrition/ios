// SPDX-License-Identifier: MPL-2.0

/// Minimum same-language results before the language preference applies at all.
///
/// Below this the server's order is kept **whole** — not same-language-first — so a French query that
/// matches only one or two French entries does not push them above better English matches. Three is the
/// point at which the same-language set is a usable list on its own.
let minimumSameLanguage = 3

/// Default cap. The caller over-fetches and this decides how much of it is offered.
public let maximumSuggestions = 30

/// Collapses duplicate labels, preferring the viewer's language, with recipes pinned on top.
///
/// Four rules, and the order between them is the contract:
///
/// 1. **Recipes are never deduplicated away and always lead.** They are the highest-value result — one
///    tap expands into a whole meal — so they are lifted out before anything else runs.
/// 2. **Language preference, but only above a threshold.** With at least `minimumSameLanguage` results
///    in the requested language, those come first and the rest follow; below it the server's own order
///    is kept whole. This is the rule most likely to be ported wrongly as "always sort by language",
///    and the `two-french-results-keep-server-order` vector is the one that catches it.
/// 3. **Deduplicate by lowercased, trimmed label *and* brand.** The API returns genuinely distinct
///    records — one curated ingredient plus N Open Food Facts barcodes — that a user could not tell
///    apart when the row showed only a name and a weight. Brand joins the key because it is now on the
///    row: two products of the same name from different brands are separate things to add, while the
///    same name *and* brand is still noise. A brandless product keys on the label alone, so it
///    collapses into the curated ingredient of that name — the winner that carries yield factors,
///    serving units and a food group. Never by `ingredientId`: that is unique per row and would
///    deduplicate nothing, which is exactly the bug this client shipped with.
/// 4. **Cap the result.** Recipes count toward the cap but are never dropped by it, so a response of
///    nothing but recipes can exceed it. Dropping a recipe to honour a display cap would lose the best
///    result to make room for a worse one.
///
/// Recipe labels are deliberately absent from the seen set, so a recipe and an ingredient sharing a name
/// both survive — they are two different things to add.
///
/// Pinned by the `deduplicate-suggestions` suite of the shared behavioural corpus.
public func deduplicateByLabel(
    _ items: [IngredientSuggestion],
    preferLanguage: String,
    maxResults: Int = maximumSuggestions
) -> [IngredientSuggestion] {
    let recipes = items.filter(\.isRecipe)
    let rest = items.filter { !$0.isRecipe }

    let sameLanguage = rest.filter { $0.lang == preferLanguage }
    let otherLanguage = rest.filter { $0.lang != preferLanguage }
    let ordered = sameLanguage.count >= minimumSameLanguage
        ? sameLanguage + otherLanguage
        : rest

    var seen: Set<String> = []
    var result = recipes
    for item in ordered {
        let key = identityKey(item)
        if seen.contains(key) { continue }
        seen.insert(key)
        result.append(item)
        if result.count == maxResults { break }
    }
    return result
}

/// The identity a viewer can actually perceive: name plus brand.
///
/// The two halves are joined by a character that cannot survive trimming in either of them, so
/// `("Jus", "Orange")` and `("Jus Orange", nil)` stay distinct — a naive concatenation would merge two
/// different products, and the `the-key-separator-cannot-be-forged-across-the-two-halves` vector is the
/// one that catches it.
private func identityKey(_ item: IngredientSuggestion) -> String {
    "\(normalisedLabel(item.label))\u{1F}\(normalisedLabel(item.brand ?? ""))"
}

/// Lowercased and whitespace-trimmed, without Foundation.
///
/// `trimmingCharacters(in:)` and `lowercased(with:)` are Foundation; this module imports nothing, so the
/// trim is written out and the lowercasing uses the stdlib's `lowercased()`. Trimming matters as much as
/// lowercasing here — Open Food Facts labels frequently carry a trailing space, and an untrimmed key
/// would let " tofu " and "Tofu" both through as separate rows. Brand gets the same treatment, because
/// contributors enter "Bonduelle", "BONDUELLE" and " bonduelle " for the same company.
private func normalisedLabel(_ label: String) -> String {
    var characters = Array(label.lowercased())
    while let first = characters.first, first.isWhitespace { characters.removeFirst() }
    while let last = characters.last, last.isWhitespace { characters.removeLast() }
    return String(characters)
}
