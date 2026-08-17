// SPDX-License-Identifier: MPL-2.0

import PocketNutritionCore

/// French copy for the app. The product is French-only.
///
/// WHERE THESE COME FROM
/// Every entry is transcribed **verbatim** from `contract/data/strings/fr.json`, the copy deck all
/// three clients share, and carries the contract key it came from. Nothing here is invented: the ten
/// strings this app once had to write for itself — the journal group, the single-add placeholder, and
/// the labels the sandbox has no equivalent for — went upstream in contracts 1.3.0, under a new `app`
/// scope for wording the native clients have and the prototype does not.
///
/// THE DRIFT THIS DOES NOT CATCH
/// `sync-contracts.sh --verify` proves `contract/` matches upstream. It cannot prove this file matches
/// `contract/`, because these are Swift literals rather than a parsed resource. That is a deliberate
/// MVP trade — the alternative is bundling the JSON and looking keys up at runtime, which turns a
/// typo into a silent blank instead of a compile error. Revisit if this list grows past a screenful:
/// the emitter that already produces Tokens.swift is the natural place to generate it.
enum Fr {

    // MARK: - App

    /// contract: app.brand — "Product name. Never translated."
    static let brand = "Pocket Nutrition"

    // MARK: - Journal
    //
    // contract: journal.*, scope `app`. The sandbox persists nothing and so has no journal; this group
    // was written for the native clients and lives in the deck under the scope that says so.

    /// contract: journal.title
    static let journalTitle = "Mon journal"

    /// contract: journal.empty
    static let journalEmpty = "Aucun repas enregistré pour le moment"

    /// contract: journal.add
    static let journalAdd = "Ajouter un repas"

    /// contract: journal.delete
    static let journalDelete = "Supprimer"

    /// contract: journal.privacy — marked REQUIRED there rather than optional.
    ///
    /// The deck's own `welcome.privacy` says "Aucune donnée personnelle n'est conservée", which is
    /// false for an app that persists a diary. Until contracts 1.3.0 the deck flagged that and offered
    /// no replacement, so both clients invented their own line; this is now the shared one.
    static let journalPrivacy = "Vos repas sont enregistrés uniquement sur cet appareil."

    // MARK: - About
    //
    // contract: about.*, scope `app`. Three obligations meet on one screen — MPL-2.0 §3.2 (tell the
    // recipient of a binary what rights they have), the ODbL attribution the Open Food Facts data
    // carries, and the reachable privacy-policy URL both consoles demand before a listing is accepted.

    /// contract: about.title
    static let aboutTitle = "À propos"

    /// contract: about.version — `{version}` is the marketing version, substituted at the call site.
    static func aboutVersion(_ version: String) -> String { "Version \(version)" }

    /// contract: about.privacyTitle
    static let aboutPrivacyTitle = "Confidentialité"

    /// contract: about.privacySummary
    static let aboutPrivacySummary =
        "Votre journal reste sur cet appareil. Aucun compte, aucune publicité, aucun traceur."

    /// contract: about.privacyNetwork — what keeps `aboutPrivacySummary` from reading as "nothing is
    /// ever sent", which would be false. Do not ship one without the other.
    static let aboutPrivacyNetwork =
        "Une recherche envoie le texte saisi. Une analyse envoie les aliments, les quantités et les "
        + "cuissons. Aucun identifiant n’accompagne ces requêtes."

    /// contract: about.privacyLink
    static let aboutPrivacyLink = "Lire la politique de confidentialité"

    /// contract: about.sourcesTitle
    static let aboutSourcesTitle = "Sources des données"

    /// contract: about.sourcesBody — attribution required by the ODbL, not a courtesy credit.
    static let aboutSourcesBody =
        "Valeurs nutritionnelles : table Ciqual (ANSES). Produits, marques et photos : "
        + "Open Food Facts, sous licence ODbL."

    /// contract: about.licenceTitle
    static let aboutLicenceTitle = "Licence"

    /// contract: about.licenceBody
    static let aboutLicenceBody =
        "Cette application est un logiciel libre, publié sous licence Mozilla Public License 2.0. "
        + "Vous pouvez en consulter, en modifier et en redistribuer le code source."

    /// contract: about.sourceLink
    static let aboutSourceLink = "Voir le code source"

    /// contract: about.thirdPartyTitle
    static let aboutThirdPartyTitle = "Composants tiers"

    /// contract: about.thirdPartyNone — true for this target, and checked rather than assumed: see
    /// AboutView's note on how to verify it before each release.
    static let aboutThirdPartyNone = "Aucune dépendance externe."

    /// contract: about.close
    static let aboutClose = "Fermer"

    // MARK: - Search

    /// contract: search.placeholderSingle.
    ///
    /// Not `search.placeholder` — that one advertises the sandbox's multi-term search, "Ajouter un ou
    /// plusieurs aliments… (riz poulet pomme)", and this app adds one food per tap. One field, two
    /// wordings, because the two clients genuinely differ. Added to the deck in contracts 1.3.0.
    static let searchPlaceholder = "Rechercher un aliment…"

    /// contract: search.noResults
    static let searchNoResults = "Aucun résultat"

    /// contract: search.multiTermHint — added in contracts 1.8.0.
    ///
    /// Carries what `search.placeholder` cannot on a phone. That string is "Ajouter un ou plusieurs
    /// aliments… (riz poulet pomme)" — 51 characters against a field that fits about 22, so the
    /// parenthetical doing the teaching is exactly what gets truncated. This goes under the field instead.
    static let multiTermHint = "Plusieurs aliments d'un coup : « riz poulet pomme »"

    /// contract: search.confirmAdd — "Ajouter ({count})". Multi-select confirm.
    static func confirmAdd(count: Int) -> String { "Ajouter (\(count))" }

    /// contract: search.alreadyAdded
    static let searchAlreadyAdded = "Déjà ajouté"

    /// contract: search.productBadge — marks an Open Food Facts product rather than an ingredient.
    static let searchProductBadge = "Produit"

    /// contract: search.recipePrefix — note the space before the colon, French typography.
    static let searchRecipePrefix = "Recette : %@"

    /// contract: search.recipeComponentCount
    ///
    /// Not pluralised, so a one-component recipe reads "1 ingrédients". That is a defect in the source
    /// the deck records verbatim, and it is transcribed verbatim here rather than quietly fixed: the
    /// three clients must read alike, and correcting it belongs in the deck.
    static let searchRecipeComponentCount = "%d ingrédients"

    /// contract: search.sectionRecipes
    static let searchSectionRecipes = "Recettes"

    /// contract: search.sectionIngredients
    static let searchSectionIngredients = "Ingrédients"

    /// contract: search.sectionProducts
    static let searchSectionProducts = "Produits de marque"

    /// contract: search.cancel
    static let searchCancel = "Annuler"

    // MARK: - Meal builder

    /// contract: mealBuilder.heading
    static let mealHeading = "Composez votre repas"

    /// contract: mealBuilder.empty
    static let mealEmpty = "Recherchez un aliment ci-dessus pour commencer"

    /// contract: mealBuilder.analysing — "Single-character ellipsis U+2026, not three dots."
    ///
    /// **Currently unused.** It labelled the blocking "Analyser" tap that computing the total used to
    /// require; the total now recomputes itself in the background (`MealBuilderView.scheduleRecompute`)
    /// and shows a small inline spinner instead of this text. Kept rather than deleted, same reasoning
    /// as `mealQuantity` below: it is a shared-deck entry, and a manual re-analyse affordance is the
    /// kind of thing that comes back.
    static let mealAnalysing = "Analyse en cours…"

    /// contract: mealBuilder.analyse — "Analyser le repas ({count} aliment{s})".
    ///
    /// **Currently unused**, for the same reason as `mealAnalysing` just above.
    ///
    /// The `{s}` rule in the contract is French: plural from 2, so it is `count > 1` and not the
    /// English `count != 1`. Built here rather than with frenchPlural because the corpus function
    /// pluralises a word against a count, and what varies here is a bare suffix inside a sentence.
    static func mealAnalyse(count: Int) -> String {
        "Analyser le repas (\(count) aliment\(count > 1 ? "s" : ""))"
    }

    /// contract: mealBuilder.remove
    static let mealRemove = "Retirer"

    /// Accessibility label for the expanded ingredient row's collapse chevron. App-only chrome — the
    /// sandbox's equivalent button carries the same word (`docs/SPECIFICATION.md` §7.8) but the shared
    /// deck has no `mealBuilder` entry for it yet.
    static let collapse = "Réduire"

    /// The weight field's decimal-pad keyboard toolbar button — app-only chrome, no sandbox equivalent
    /// since a web numeric input dismisses however the platform already dismisses any input. The
    /// standard iOS wording for a keyboard-toolbar dismiss button, not the shared deck's generic
    /// `errors.retry`-style "Valider": a decimal pad has already committed the typed value by the time
    /// this is tapped, so the button is closing the keyboard, not confirming a pending choice.
    static let done = "Terminé"

    /// contract: mealBuilder.quantity
    /// contract: mealBuilder.quantity.
    ///
    /// **Currently unused**, and kept deliberately rather than deleted. It labelled the bare grams field
    /// that the portion ladder replaced: the ladder's own summary line ("≈ 2,3 portions" over the
    /// weight) says what the number is, so a caption above it was repetition. Retained because the entry
    /// is in the shared deck — added in contracts 1.3.0 for this very label — and a field caption is the
    /// kind of thing that comes back. If it has not by the next deck revision, drop both together.
    static let mealQuantity = "Quantité"

    /// contract: mealBuilder.cooking. The sandbox needs no such label — its method is implied by which
    /// drop-lane a card sits in, and this app has no lanes.
    static let mealCooking = "Cuisson"

    // MARK: - Cooking methods
    //
    // contract: cookingMethods.*, keyed by the same ids as PnCooking.methods in the design tokens.

    static func cookingMethod(_ id: String) -> String {
        switch id {
        case "raw": return "Cru"
        case "boiled": return "Bouilli"
        case "steamed": return "Vapeur"
        case "grilled": return "Grillé"
        case "roasted": return "Rôti"
        case "fried": return "Frit"
        // contract: cookingMethods.cookedGeneric. Reachable because the API may return a method the
        // token set does not know; showing the raw id would leak an English identifier into French UI.
        default: return "cuit (générique)"
        }
    }

    // MARK: - Nutrients
    //
    // contract: nutrients.*

    static let nutrientEnergy = "Énergie"
    static let nutrientProtein = "Protéines"
    static let nutrientCarbs = "Glucides"
    static let nutrientFat = "Lipides"

    // MARK: - Results

    /// contract: results.total
    static let resultsTotal = "Total du repas"

    /// contract: results.edit
    ///
    /// **Currently unused.** It labelled the "back to editing" button on the separate results screen
    /// that `MealBuilderView` and `ResultsView` used to be; now that a total is shown inline while
    /// composing, there is no second screen to return from. Kept rather than deleted — same reasoning
    /// as `mealQuantity` above.
    static let resultsEdit = "Modifier le repas"

    /// contract: results.save
    static let resultsSave = "Enregistrer ce repas"

    /// contract: results.rowSummary — "{quantity} {unit} · {method} · pesé {state}".
    ///
    /// `quantity` goes through formatFrenchNumber so 150.0 renders "150" and not "150.0" — the corpus
    /// rule, not a formatter.
    static func resultsRowSummary(quantity: Double, unit: String, method: String, state: String) -> String {
        "\(formatFrenchNumber(quantity)) \(unit) · \(method) · pesé \(state)"
    }

    // MARK: - Measured state
    //
    // contract: measuredState.*

    static func measuredState(_ id: String) -> String {
        switch id {
        case "raw": return "cru"
        case "cooked": return "cuit"
        default: return id
        }
    }

    /// contract: measuredState.beforeLong — paired with 🌿, per the deck's own context note.
    static let measuredBeforeLong = "Avant cuisson"

    /// contract: measuredState.afterLong — paired with 🍽️.
    static let measuredAfterLong = "Après cuisson"

    /// contract: ingredientCard.weighedLabel — the source has a non-breaking space before the colon,
    /// so this string carries U+00A0 rather than a plain space. French typography, and it is what the
    /// deck records.
    static let weighedLabel = "Pesé\u{00A0}:"

    /// contract: ingredientCard.weighedGroupAria
    static let weighedGroupAria = "Pesé avant ou après cuisson"

    /// contract: ingredientCard.weighedInline — "(pesé {when} cuisson)", `when` being
    /// measuredState.before / .after. Shown inside the collapsed method pill.
    static func weighedInline(_ when: String) -> String { "(pesé \(when) cuisson)" }

    /// contract: measuredState.before / .after — the short forms, used only by `weighedInline`.
    static func measuredWhen(_ state: String) -> String { state == "cooked" ? "après" : "avant" }

    /// contract: ingredientCard.changeCooking — accessibility label on the method pill.
    static let changeCooking = "Changer la cuisson et l'état de pesée"

    /// contract: ingredientCard.report — "Discreet footer link opening the feedback dialog."
    static let ingredientReport = "Signaler"

    /// contract: ingredientCard.reportAria
    static let ingredientReportAria = "Signaler une imprécision"

    // MARK: - Feedback
    //
    // contract: feedback.*. Category and error labels are not here: they travel with their own code in
    // `FeedbackCatalog`, the same way the deck's `feedback.catalog` entries carry their own `fr` rather
    // than pointing back at this file.

    /// contract: feedback.title
    static let feedbackTitle = "Signaler une imprécision"

    /// contract: feedback.intro
    static let feedbackIntro = "Choisissez une catégorie, puis l'erreur concernée."

    /// contract: feedback.referenceWeight — current-value hint shown beside the form.
    static let feedbackReferenceWeight = "Poids de référence"

    /// contract: feedback.displayUnit
    static let feedbackDisplayUnit = "Unité d'affichage"

    /// contract: feedback.units
    static let feedbackUnits = "Unités"

    /// contract: feedback.comment
    static let feedbackComment = "Commentaire (optionnel)"

    /// contract: feedback.add — adds one correction to the pending list.
    static let feedbackAdd = "Ajouter"

    /// contract: feedback.removeCorrection
    static let feedbackRemoveCorrection = "Retirer cette correction"

    /// contract: feedback.submit
    static let feedbackSubmit = "Envoyer le signalement"

    /// contract: feedback.submitting
    static let feedbackSubmitting = "Envoi…"

    /// contract: feedback.success
    static let feedbackSuccess = "Merci, votre signalement a été transmis à l'équipe."

    /// contract: feedback.failure
    static let feedbackFailure = "Envoi impossible pour le moment. Réessayez plus tard."

    /// contract: feedback.close
    static let feedbackClose = "Fermer"

    /// contract: feedback.unitAria
    static let feedbackUnitAria = "unité"

    // MARK: - Barcode scan
    //
    // Client-authored, not yet in contract/data/strings/fr.json — no scan/camera/barcode keys exist in
    // the shared deck yet. Candidates for upstreaming under the `app` scope in a future
    // CONTRACTS_VERSION bump, the same path search.placeholderSingle and mealBuilder.* took in 1.3.0.

    static let scanBarcodeButton = "Scanner un code-barres"

    static let scanExplainerTitle = "Scanner un produit"
    static let scanExplainerBody =
        "Pocket Nutrition a besoin d'accéder à l'appareil photo pour scanner le code-barres d'un "
        + "produit et retrouver ses valeurs nutritionnelles. Aucune photo n'est enregistrée."
    static let scanExplainerContinue = "Continuer"
    static let scanExplainerNotNow = "Pas maintenant"

    static let scanSettingsTitle = "Autoriser l'appareil photo"
    static let scanSettingsBody =
        "L'accès à l'appareil photo a été refusé. Ouvrez les réglages pour l'autoriser."
    static let scanSettingsOpenSettings = "Ouvrir Réglages"

    static let scanLookingUp = "Recherche du produit…"

    static let scanNotFoundTitle = "Produit introuvable"
    static let scanNotFound = "Ce code-barres est introuvable dans notre base. Essayez une recherche par nom."

    static let scanErrorTitle = "Échec du scan"

    static let scanUnavailableTitle = "Scan indisponible"
    static let scanUnavailable = "Le scan de code-barres n'est pas disponible sur cet appareil."

    // MARK: - Errors

    /// contract: errors.prefix — "Erreur : {message}". Note the space before the colon: French
    /// typography, and it is in the contract deliberately.
    static func error(_ message: String) -> String { "Erreur : \(message)" }

    /// contract: errors.retry
    static let retry = "Réessayer"
}
