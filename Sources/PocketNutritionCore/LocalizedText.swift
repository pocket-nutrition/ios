// SPDX-License-Identifier: MPL-2.0

/// One piece of text in one language. The single shape every multilingual field on the wire uses —
/// `ServingUnit.labels`, `IngredientDetail.names`/`.aliases`, `IngredientSuggestion.unitLabels` — in
/// place of what used to be a fixed `xxxFr`/`xxxEn` field pair per piece of text.
///
/// The point of the shape: a third language is a knowledge-base data change only. Nothing that reads
/// a `[LocalizedText]` needs to know how many languages exist or what their codes are.
public struct LocalizedText: Equatable, Sendable, Decodable {
    public let lang: String
    public let text: String

    public init(lang: String, text: String) {
        self.lang = lang
        self.text = text
    }
}

/// Picks the text matching `lang`, falling back to French, then to whichever entry happens to be
/// first. The one place this resolution rule is defined on this platform — every call site that used
/// to read `.labelFr` directly goes through this instead, mirroring the server's own
/// `preferred lang → fr → first` fallback in `IngredientSearchService.pickPreferred`.
///
/// Adding a third language never requires touching this function: it already treats `lang` as an
/// opaque string, not a closed set.
public func pickLocalized(_ items: [LocalizedText], preferring lang: String) -> String? {
    items.first { $0.lang == lang }?.text
        ?? items.first { $0.lang == "fr" }?.text
        ?? items.first?.text
}
