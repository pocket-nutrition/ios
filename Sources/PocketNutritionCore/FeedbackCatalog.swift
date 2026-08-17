// SPDX-License-Identifier: MPL-2.0

/// One typed input a correction can take, and what it needs to render.
///
/// `.select`'s options and `.numberUnit`'s units are inline arrays rather than a lookup into a shared
/// table, mirroring `contract/data/strings/fr.json`'s `feedback.catalog.optionLists`: the deck
/// indirects through named lists (`"options": "foodGroups"`) only because JSON has no way to share a
/// literal; Swift does, so each error definition below just points at the same `let` array directly.
public enum FeedbackInputKind: Equatable, Sendable {
    case number(suffix: String?)
    case numberUnit(units: [String])
    case select(options: [FeedbackOption])
    case text(placeholder: String?)
}

/// One choice in a `.select` input — a code the server allowlist knows, and its French label.
public struct FeedbackOption: Equatable, Sendable, Identifiable {
    public var id: String { code }
    public let code: String
    public let label: String

    public init(code: String, label: String) {
        self.code = code
        self.label = label
    }
}

/// The current-value hint an error can carry, so the form can show what the app already believes
/// next to the field asking whether that is wrong. The first five mirror `feedbackCatalog.ts`'s
/// `CurrentValueHint` and resolve from data the row already holds locally (the `MealIngredient` from
/// `/ingredients/search`). The rest are this client's own addition — a hint has no wire meaning, it is
/// never sent to the server, only `category`+`code`+`value`+`unit` are — so extending this enum beyond
/// the shared deck's five is safe and does not need mirroring back into `fr.json` or the TS catalog.
/// They resolve from a `GET /ingredients/{id}` fetch instead, because neither the raw nutrient profile
/// nor the canonical name/food group are present on a search-result row.
public enum FeedbackCurrentValueHint: String, Equatable, Sendable {
    case referenceWeight = "reference_weight"
    case displayUnit = "display_unit"
    case servingUnits = "serving_units"
    case rawCooked = "raw_cooked"
    case cookingMethod = "cooking_method"
    case energy
    case protein
    case fat
    case carbs
    case fiber
    case nameFr = "name_fr"
    case nameEn = "name_en"
    case foodGroup = "food_group"
}

/// One specific, reportable error within a category — "Poids de référence", not just "Mesures".
public struct FeedbackErrorDef: Equatable, Sendable, Identifiable {
    public var id: String { code }
    /// Part of the server's allowlist together with the owning category's code. Transcribed verbatim
    /// from the deck — never paraphrase or invent one, or the submission is rejected with 400.
    public let code: String
    public let label: String
    public let input: FeedbackInputKind
    public let hint: FeedbackCurrentValueHint?

    public init(code: String, label: String, input: FeedbackInputKind, hint: FeedbackCurrentValueHint? = nil) {
        self.code = code
        self.label = label
        self.input = input
        self.hint = hint
    }
}

/// One group of related errors in the guided feedback form — "Valeurs nutritionnelles", "Cuisson", …
public struct FeedbackCategory: Equatable, Sendable, Identifiable {
    public var id: String { code }
    /// Same allowlist rule as `FeedbackErrorDef.code`.
    public let code: String
    public let label: String
    public let errors: [FeedbackErrorDef]

    public init(code: String, label: String, errors: [FeedbackErrorDef]) {
        self.code = code
        self.label = label
        self.errors = errors
    }
}

/// The guided-correction taxonomy behind "Signaler une imprécision": five categories of common
/// mistakes, each listing specific errors, each with the input its value needs.
///
/// Transcribed verbatim from `contract/data/strings/fr.json`'s `feedback.catalog` — the same source
/// `pocket-nutrition-sandbox/src/lib/feedbackCatalog.ts` transcribes into TypeScript, so all three
/// clients report against the identical codes the server's `FeedbackController` allowlists.
public enum FeedbackCatalog {

    // MARK: - Option lists
    //
    // Each mirrors one entry of the deck's `feedback.catalog.optionLists`.

    /// Mirrors `pocket-nutrition-knowledge/serving_unit_types.yaml`. A closed vocabulary — do not
    /// extend it client-side.
    public static let servingUnits: [FeedbackOption] = [
        FeedbackOption(code: "pinch", label: "pincée"),
        FeedbackOption(code: "teaspoon", label: "cuillère à café"),
        FeedbackOption(code: "tablespoon", label: "cuillère à soupe"),
        FeedbackOption(code: "cup", label: "tasse"),
        FeedbackOption(code: "handful", label: "poignée"),
        FeedbackOption(code: "small_handful", label: "petite poignée"),
        FeedbackOption(code: "glass", label: "verre"),
    ]

    /// Mirrors the `food_group` enum in `ingredient.schema.json`. No French label for a food group
    /// exists elsewhere in this app — `FoodGroupIcon.swift` maps the same 21 codes to an emoji, never
    /// to text — so this is the first place these words are written down for the app to display.
    public static let foodGroups: [FeedbackOption] = [
        FeedbackOption(code: "meat", label: "viande"),
        FeedbackOption(code: "fish", label: "poisson"),
        FeedbackOption(code: "shellfish", label: "fruits de mer"),
        FeedbackOption(code: "vegetable", label: "légume"),
        FeedbackOption(code: "cereal", label: "céréale"),
        FeedbackOption(code: "dairy", label: "produit laitier"),
        FeedbackOption(code: "beverage", label: "boisson"),
        FeedbackOption(code: "egg", label: "œuf"),
        FeedbackOption(code: "fat", label: "matière grasse"),
        FeedbackOption(code: "fruit", label: "fruit"),
        FeedbackOption(code: "legume", label: "légumineuse"),
        FeedbackOption(code: "nut_seed", label: "fruit à coque / graine"),
        FeedbackOption(code: "spice_herb", label: "épice / herbe"),
        FeedbackOption(code: "sweetener", label: "édulcorant"),
        FeedbackOption(code: "baked_good", label: "produit de boulangerie"),
        FeedbackOption(code: "sauce", label: "sauce"),
        FeedbackOption(code: "processed_meat", label: "charcuterie"),
        FeedbackOption(code: "prepared_dish", label: "plat préparé"),
        FeedbackOption(code: "seaweed", label: "algue"),
        FeedbackOption(code: "alcohol", label: "alcool"),
        FeedbackOption(code: "other", label: "autre"),
    ]

    /// Lowercase forms, used in this form only. `Fr.cookingMethod(_:)` has the capitalised forms the
    /// method picker uses — a different string for a different control, not a duplicate to collapse.
    public static let cookingMethodsLowercase: [FeedbackOption] = [
        FeedbackOption(code: "raw", label: "cru"),
        FeedbackOption(code: "boiled", label: "bouilli"),
        FeedbackOption(code: "steamed", label: "vapeur"),
        FeedbackOption(code: "grilled", label: "grillé"),
        FeedbackOption(code: "roasted", label: "rôti"),
        FeedbackOption(code: "fried", label: "frit"),
        FeedbackOption(code: "cooked", label: "cuit (générique)"),
    ]

    public static let servingModes: [FeedbackOption] = [
        FeedbackOption(code: "item", label: "à l'unité"),
        FeedbackOption(code: "weight", label: "au poids"),
        FeedbackOption(code: "volume", label: "au volume"),
        FeedbackOption(code: "measure", label: "à la mesure"),
    ]

    public static let displayUnits: [FeedbackOption] = [
        FeedbackOption(code: "g", label: "grammes (g)"),
        FeedbackOption(code: "ml", label: "millilitres (ml)"),
    ]

    public static let rawCooked: [FeedbackOption] = [
        FeedbackOption(code: "raw", label: "cru"),
        FeedbackOption(code: "cooked", label: "cuit"),
        FeedbackOption(code: "both", label: "les deux"),
    ]

    // MARK: - Categories

    public static let categories: [FeedbackCategory] = [
        FeedbackCategory(
            code: "nutrition",
            label: "Valeurs nutritionnelles",
            errors: [
                FeedbackErrorDef(code: "energy", label: "Énergie", input: .number(suffix: "kcal"), hint: .energy),
                FeedbackErrorDef(code: "protein", label: "Protéines", input: .number(suffix: "g"), hint: .protein),
                FeedbackErrorDef(code: "fat", label: "Lipides", input: .number(suffix: "g"), hint: .fat),
                FeedbackErrorDef(code: "carbs", label: "Glucides", input: .number(suffix: "g"), hint: .carbs),
                FeedbackErrorDef(code: "fiber", label: "Fibres", input: .number(suffix: "g"), hint: .fiber),
                FeedbackErrorDef(
                    code: "other_nutrient",
                    label: "Autre nutriment",
                    input: .text(placeholder: "ex : vitamine C ~ 12 mg")
                ),
            ]
        ),
        FeedbackCategory(
            code: "identity",
            label: "Identité",
            errors: [
                FeedbackErrorDef(
                    code: "name_fr",
                    label: "Nom (français)",
                    input: .text(placeholder: "nom correct en français"),
                    hint: .nameFr
                ),
                FeedbackErrorDef(
                    code: "name_en",
                    label: "Nom (anglais)",
                    input: .text(placeholder: "correct English name"),
                    hint: .nameEn
                ),
                FeedbackErrorDef(
                    code: "food_group",
                    label: "Groupe alimentaire",
                    input: .select(options: foodGroups),
                    hint: .foodGroup
                ),
                FeedbackErrorDef(
                    code: "aliases",
                    label: "Noms alternatifs / synonymes",
                    input: .text(placeholder: "ex : poivre, poivre moulu")
                ),
                FeedbackErrorDef(
                    code: "wrong_ingredient",
                    label: "Mauvais ingrédient reconnu",
                    input: .text(placeholder: "le bon ingrédient serait…")
                ),
            ]
        ),
        FeedbackCategory(
            code: "measures",
            label: "Mesures & portions",
            errors: [
                FeedbackErrorDef(
                    code: "reference_weight",
                    label: "Poids de référence",
                    input: .numberUnit(units: ["g", "ml"]),
                    hint: .referenceWeight
                ),
                FeedbackErrorDef(
                    code: "serving_unit",
                    label: "Unité de mesure manquante (ex : pincée)",
                    input: .select(options: servingUnits),
                    hint: .servingUnits
                ),
                FeedbackErrorDef(
                    code: "display_unit",
                    label: "Unité d'affichage",
                    input: .select(options: displayUnits),
                    hint: .displayUnit
                ),
                FeedbackErrorDef(
                    code: "serving_mode",
                    label: "Mode de portion",
                    input: .select(options: servingModes)
                ),
                FeedbackErrorDef(code: "density", label: "Densité", input: .number(suffix: "g/ml")),
            ]
        ),
        FeedbackCategory(
            code: "cooking",
            label: "Cuisson",
            errors: [
                FeedbackErrorDef(code: "yield", label: "Rendement après cuisson", input: .number(suffix: "%")),
                FeedbackErrorDef(
                    code: "cooking_method",
                    label: "Méthode de cuisson manquante",
                    input: .select(options: cookingMethodsLowercase),
                    hint: .cookingMethod
                ),
                FeedbackErrorDef(
                    code: "raw_cooked",
                    label: "Se mange cru / cuit",
                    input: .select(options: rawCooked),
                    hint: .rawCooked
                ),
            ]
        ),
        FeedbackCategory(
            code: "other",
            label: "Autre / nouvelle information",
            errors: [
                FeedbackErrorDef(
                    code: "free",
                    label: "Autre remarque",
                    input: .text(placeholder: "décrivez le problème ou la nouvelle information")
                )
            ]
        ),
    ]
}
