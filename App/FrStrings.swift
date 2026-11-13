// SPDX-License-Identifier: MPL-2.0

import PocketNutritionCore

/// French copy. See `AppStrings` for where every entry comes from and what it means.
struct FrStrings: AppStrings {

    let brand = "Pocket Nutrition"

    let journalTitle = "Mon journal"
    let journalEmpty = "Aucun repas enregistré pour le moment"
    let journalAdd = "Ajouter un repas"
    let journalDelete = "Supprimer"
    let journalPrivacy = "Vos repas sont enregistrés sur cet appareil. Avec un compte coffre-fort, une copie chiffrée y est aussi conservée."

    let aboutTitle = "À propos"
    func aboutVersion(_ version: String) -> String { "Version \(version)" }
    let aboutPrivacyTitle = "Confidentialité"
    let aboutPrivacySummary =
        "Votre journal est enregistré sur cet appareil. Un compte coffre-fort dans le cloud est facultatif "
        + "(un identifiant, sans e-mail) : il conserve une copie chiffrée de votre journal et sert à la saisie "
        + "vocale. Aucune publicité, aucun traceur."
    let aboutPrivacyNetwork =
        "Une recherche envoie le texte saisi. Une analyse envoie les aliments, les quantités et les "
        + "cuissons. Aucun identifiant n’accompagne ces requêtes. Un enregistrement vocal est envoyé pour "
        + "analyse et conservé seulement jusqu’à son traitement, 48 heures au plus ; le résultat est "
        + "déposé dans votre propre coffre-fort, chiffré pour que seuls vos appareils puissent le lire. "
        + "Il en va de même pour la copie chiffrée de votre journal, que le serveur ne peut pas lire. "
        + "Votre phrase secrète ne quitte jamais ce téléphone."
    let aboutPrivacyLink = "Lire la politique de confidentialité"
    let aboutSourcesTitle = "Sources des données"
    let aboutSourcesBody =
        "Valeurs nutritionnelles : Ciqual 2025 (ANSES, Licence Ouverte), CoFID 2021 de McCance & Widdowson "
        + "(contient des informations du secteur public sous Open Government Licence v3.0), "
        + "USDA FoodData Central et table des rendements de cuisson USDA (domaine public). "
        + "Produits, marques et photos : Open Food Facts, sous licence ODbL."
    let aboutLicenceTitle = "Licence"
    let aboutLicenceBody =
        "Cette application est un logiciel libre, publié sous licence Mozilla Public License 2.0. "
        + "Vous pouvez en consulter, en modifier et en redistribuer le code source."
    let aboutSourceLink = "Voir le code source"
    let aboutThirdPartyTitle = "Composants tiers"
    let aboutThirdPartyNone = "Aucune dépendance externe."
    let aboutClose = "Fermer"

    let settingsTitle = "Paramètres"

    let aboutLanguageTitle = "Langue"
    let aboutLanguageAuto = "Automatique"
    let aboutLanguageFr = "Français"
    let aboutLanguageEn = "English"

    let aboutServerTitle = "Serveur"
    let aboutServerBody = "Adresse du serveur utilisé par l'application. Laissez vide pour rester sur le serveur officiel."
    let aboutServerApply = "Utiliser cette adresse"
    let aboutServerReset = "Revenir au serveur officiel"
    let aboutServerInvalid =
        "Adresse invalide. Utilisez une URL complète, par exemple https://exemple.org"

    let searchPlaceholder = "Rechercher un aliment…"
    let searchNoResults = "Aucun résultat"
    let multiTermHint = "Plusieurs aliments d'un coup : « riz poulet pomme »"
    func confirmAdd(count: Int) -> String { "Ajouter (\(count))" }
    let searchAlreadyAdded = "Déjà ajouté"
    let searchProductBadge = "Produit"
    let searchRecipePrefix = "Recette : %@"
    let searchRecipeComponentCount = "%d ingrédients"
    let searchSectionRecipes = "Recettes"
    let searchSectionIngredients = "Ingrédients"
    let searchSectionProducts = "Produits de marque"
    let searchCancel = "Annuler"

    let mealHeading = "Composez votre repas"
    func mealSlotName(_ slot: MealSlot) -> String {
        switch slot {
        case .breakfast: "Petit-déjeuner"
        case .lunch: "Déjeuner"
        case .dinner: "Dîner"
        case .snack: "En-cas"
        }
    }
    let mealChangeTime = "Changer l'heure…"
    let mealTimeTitle = "Heure du repas"
    func journalSameAsYesterday(_ items: String) -> String { "Comme hier : \(items)" }
    let dishesTitle = "Mes plats"
    func recentsTitle(_ slot: MealSlot) -> String {
        switch slot {
        case .breakfast: "Souvent au petit-déjeuner"
        case .lunch: "Souvent au déjeuner"
        case .dinner: "Souvent au dîner"
        case .snack: "Souvent en en-cas"
        }
    }
    func dishDetail(ingredients: Int, servings: Int) -> String {
        "\(ingredients) ingrédient\(ingredients > 1 ? "s" : "")" + (servings > 1 ? " · pour \(servings)" : "")
    }
    func recentDetail(grams: Double, method: String) -> String { "\(roundHalfUp(grams)) g" + (method.isEmpty || method == "raw" ? "" : " · \(cookingMethod(method).lowercased())") }
    let saveAsDish = "Enregistrer comme plat"
    let dishNameField = "Nom du plat"
    func dishServings(_ count: Int) -> String { "Pour \(count) portion\(count > 1 ? "s" : "")" }
    let dishSave = "Enregistrer"
    func dishUpdate(_ name: String) -> String { "Mettre à jour « \(name) »" }
    let dishMenuA11y = "Options du plat"
    func dishPartsUnit(servings: Int, parts: Double) -> String { servings > 1 ? "sur \(servings) portions" : "×" }
    let pin = "Épingler"
    let unpin = "Désépingler"
    let deleteDish = "Supprimer le plat"
    func quickAddRow(_ kcal: Int) -> String { "Ajouter \(kcal) kcal" }
    let quickAddNote = "Saisi manuellement"
    func shortcutAddA11y(_ name: String) -> String { "Ajouter \(name)" }
    let logAgainNow = "Refaire maintenant"
    func journalRepeatYesterdayA11y(_ slot: String) -> String { "Refaire le \(slot.lowercased()) d'hier" }
    let mealEmpty = "Recherchez un aliment ci-dessus pour commencer"
    let mealAnalysing = "Analyse en cours…"
    func mealAnalyse(count: Int) -> String {
        "Analyser le repas (\(count) aliment\(count > 1 ? "s" : ""))"
    }
    let mealRemove = "Retirer"
    let collapse = "Réduire"
    let done = "Terminé"
    let mealQuantity = "Quantité"
    let mealCooking = "Cuisson"

    func cookingMethod(_ id: String) -> String {
        switch id {
        case "raw": return "Cru"
        case "boiled": return "Bouilli"
        case "steamed": return "Vapeur"
        case "grilled": return "Grillé"
        case "roasted": return "Rôti"
        case "fried": return "Frit"
        default: return "cuit (générique)"
        }
    }

    let nutrientEnergy = "Énergie"
    let nutrientProtein = "Protéines"
    let nutrientCarbs = "Glucides"
    let nutrientFat = "Lipides"
    let nutrientProteinAbbr = "P"
    let nutrientCarbsAbbr = "G"
    let nutrientFatAbbr = "L"

    let resultsTotal = "Total du repas"
    let resultsEdit = "Modifier le repas"
    let resultsSave = "Enregistrer ce repas"
    let resultsUnavailable = "Données indisponibles pour cet aliment."
    let resultsTotalUnknown = "— kcal"
    func resultsRowSummary(quantity: Double, unit: String, method: String, state: String) -> String {
        "\(formatNumber(quantity, lang: "fr")) \(unit) · \(method) · pesé \(state)"
    }

    func measuredState(_ id: String) -> String {
        switch id {
        case "raw": return "cru"
        case "cooked": return "cuit"
        default: return id
        }
    }
    let measuredBeforeLong = "Avant cuisson"
    let measuredAfterLong = "Après cuisson"
    let weighedLabel = "Pesé\u{00A0}:"
    let weighedGroupAria = "Pesé avant ou après cuisson"
    func weighedInline(_ when: String) -> String { "(pesé \(when) cuisson)" }
    func measuredWhen(_ state: String) -> String { state == "cooked" ? "après" : "avant" }
    let changeCooking = "Changer la cuisson et l'état de pesée"
    let ingredientReport = "Signaler"
    let ingredientReportAria = "Signaler une imprécision"

    let feedbackTitle = "Signaler une imprécision"
    let feedbackIntro = "Choisissez une catégorie, puis l'erreur concernée."
    let feedbackReferenceWeight = "Poids de référence"
    let feedbackDisplayUnit = "Unité d'affichage"
    let feedbackUnits = "Unités"
    let feedbackComment = "Commentaire (optionnel)"
    let feedbackAdd = "Ajouter"
    let feedbackRemoveCorrection = "Retirer cette correction"
    let feedbackSubmit = "Envoyer le signalement"
    let feedbackSubmitting = "Envoi…"
    let feedbackSuccess = "Merci, votre signalement a été transmis à l'équipe."
    let feedbackFailure = "Envoi impossible pour le moment. Réessayez plus tard."
    let feedbackClose = "Fermer"
    let feedbackUnitAria = "unité"

    // Feedback form: current data and per-field help (client-authored)
    let feedbackPendingTitle = "Corrections à envoyer"
    let feedbackCurrentDataTitle = "Données actuelles"
    let feedbackCurrentDataLoading = "Chargement des données complètes…"
    let feedbackCorrectValue = "Valeur correcte"
    func feedbackCurrent(_ value: String) -> String { "actuel : \(value)" }
    func feedbackHelp(_ code: String) -> String? {
        switch code {
        case "energy", "protein", "fat", "carbs", "fiber": "Valeur pour 100 g de l'aliment cru."
        case "other_nutrient": "Indiquez le nutriment et sa valeur pour 100 g."
        case "name_fr", "name_en": "Le nom sous lequel cet aliment doit être affiché et trouvé."
        case "food_group": "La famille à laquelle appartient cet aliment."
        case "aliases": "D'autres noms sous lesquels on cherche cet aliment."
        case "wrong_ingredient": "La recherche a trouvé un autre aliment que celui voulu."
        case "reference_weight": "Poids d'une portion ou d'une pièce typique."
        case "serving_unit": "Une unité dans laquelle vous aimeriez compter cet aliment."
        case "display_unit": "L'unité dans laquelle les quantités sont affichées."
        case "serving_mode": "Si cet aliment se compte à la pièce, au poids ou au volume."
        case "density": "Grammes par millilitre, pour convertir un volume en poids."
        case "yield": "Poids cuit en pourcentage du poids cru : 100 g crus qui pèsent 75 g cuits, c'est 75 %."
        case "cooking_method": "Une façon de cuire cet aliment que l'app ne propose pas."
        case "raw_cooked": "Comment cet aliment se mange : cru, cuit, ou les deux. Choisissez la bonne réponse si l'actuelle est fausse."
        case "free": "Toute autre remarque, ou une information que nous n'avons pas."
        default: nil
        }
    }
    let feedbackTechIngredient = "Ingrédient"
    let feedbackTechCooking = "Cuisson choisie"
    let feedbackTechMeasured = "Poids saisi"
    let feedbackTechEatability = "Se mange"
    let feedbackTechYields = "Rendement après cuisson"
    let feedbackTechYieldNone = "non renseigné (poids inchangé)"
    let feedbackTechReferenceWeight = "Poids de référence"
    let feedbackTechUnits = "Unités"
    let feedbackTechFoodGroup = "Groupe alimentaire"
    let feedbackTechPer100 = "Pour 100 g (cru)"
    func feedbackEatability(raw: Bool?, cooked: Bool?) -> String? {
        switch (raw, cooked) {
        case (true, true): "cru ou cuit"
        case (true, _): "cru"
        case (false, _), (_, true): "cuit uniquement"
        default: nil
        }
    }
    func feedbackMeasuredState(_ state: String) -> String { state == "cooked" ? "poids cuit" : "poids cru" }

    let scanBarcodeButton = "Scanner un code-barres"
    let scanExplainerTitle = "Scanner un produit"
    let scanExplainerBody =
        "Pocket Nutrition a besoin d'accéder à l'appareil photo pour scanner le code-barres d'un "
        + "produit et retrouver ses valeurs nutritionnelles. Aucune photo n'est enregistrée."
    let scanExplainerContinue = "Continuer"
    let scanExplainerNotNow = "Pas maintenant"
    let scanSettingsTitle = "Autoriser l'appareil photo"
    let scanSettingsBody =
        "L'accès à l'appareil photo a été refusé. Ouvrez les réglages pour l'autoriser."
    let scanSettingsOpenSettings = "Ouvrir Réglages"
    let scanLookingUp = "Recherche du produit…"
    let scanNotFoundTitle = "Produit introuvable"
    let scanNotFound = "Ce code-barres n'est pas encore dans notre base. Recherchez ses ingrédients par nom ; vous pourrez ensuite enregistrer le repas comme plat pour le réutiliser."
    let scanReport = "Signaler ce produit"
    let scanReportSent = "Merci, signalé"
    let scanErrorTitle = "Échec du scan"
    let scanUnavailableTitle = "Scan indisponible"
    let scanUnavailable = "Le scan de code-barres n'est pas disponible sur cet appareil."

    func yieldHint(display: String, heavier: Bool) -> String {
        "Cet aliment pèse \(display)x \(heavier ? "plus" : "moins") lourd une fois cuit"
    }

    func error(_ message: String) -> String { "Erreur : \(message)" }
    let retry = "Réessayer"

    // MARK: - Voice capture (client-authored; the recognition endpoint is not in contracts 2.0.0)

    let recognitionSettingsTitle = "Serveur de reconnaissance vocale"
    let recognitionSettingsBody = "La saisie vocale envoie l'enregistrement de votre voix au serveur indiqué ici, pour le transformer en liste d'aliments. L'enregistrement reste sur le téléphone jusqu'à la réception du résultat (7 jours au maximum), puis il est supprimé. N'indiquez qu'un serveur de confiance."
    let recognitionServerLabel = "Adresse du serveur"
    let recognitionKeyLabel = "Clé d'API"
    let recognitionKeySavedPlaceholder = "Clé enregistrée — laissez vide pour la conserver"
    let recognitionSave = "Enregistrer"
    let recognitionClear = "Effacer"
    let recognitionInvalidURL = "Adresse invalide. Utilisez une URL https:// complète, par exemple https://exemple.org"
    let recognitionMissingKey = "Saisissez la clé d'API du serveur."
    let recognitionSaveFailed = "Impossible d'enregistrer la clé dans le trousseau de l'appareil."
    let recognitionSaved = "Enregistré."
    let recognitionKeyRequiredForNewHost = "Le serveur a changé : saisissez à nouveau la clé d'API pour ce serveur."
    let recognitionClearFailed = "Impossible de supprimer la clé du trousseau de l'appareil."


    // MARK: - Cloud vault (client-authored)

    let vaultTitle = "Coffre-fort"
    let vaultIntro = "Gardez vos données dans le cloud et sur tous vos appareils. Elles sont chiffrées avant de quitter votre téléphone : le serveur ne peut jamais les lire."
    let vaultServerLabel = "Adresse du serveur"
    let vaultCheckServer = "Vérifier le serveur"
    let vaultRegistrationClosed = "Ce serveur n'accepte pas de nouveaux comptes. Vous pouvez seulement vous y connecter."
    let vaultUsernameLabel = "Nom d'utilisateur"
    let vaultPassphraseLabel = "Phrase secrète"
    let vaultPassphraseConfirmLabel = "Confirmer la phrase secrète"
    let vaultPassphraseHint = "12 caractères minimum. Elle ne quitte jamais votre téléphone et personne ne peut la récupérer pour vous."
    let vaultCreateAccount = "Créer un compte"
    let vaultLogin = "Se connecter"
    let vaultRecoveryTitle = "Votre kit de secours"
    let vaultRecoveryBody = "C'est ce qui vous permet de retrouver votre coffre-fort sur un nouveau téléphone ou si vous oubliez votre phrase secrète. Nous ne pouvons rien récupérer. Envoyez-le-vous ou enregistrez-le dans votre gestionnaire de mots de passe, pas seulement sur ce téléphone."
    let vaultRecoveryCopy = "Copier le kit"
    let vaultRecoveryCopied = "Kit copié"
    let vaultRecoveryContinue = "Terminer la création du compte"
    let vaultLogout = "Se déconnecter de cet appareil"
    let vaultLogoutUnreached = "Cet appareil est déconnecté, mais le serveur n'a pas pu être prévenu. Révoquez-le depuis un autre appareil connecté."
    let vaultDeleteAccount = "Supprimer mon compte et mes données"
    let vaultDeleteBody = "Efface définitivement le compte et tout ce qui est stocké sur le serveur. Saisissez votre phrase secrète pour confirmer."
    let vaultDeleteConfirm = "Supprimer définitivement"
    let vaultCancel = "Annuler"
    let vaultErrInvalidServer = "Adresse invalide. Utilisez une URL https:// complète, par exemple https://exemple.org"
    let vaultErrNotAVault = "Cette adresse ne répond pas comme un serveur coffre-fort."
    let vaultErrOffline = "Impossible de joindre le serveur. Vérifiez la connexion et réessayez."
    let vaultErrInvalidUsername = "Nom d'utilisateur invalide : 3 à 64 caractères parmi a-z, 0-9, « _ », « . » et « - »."
    let vaultErrPassphraseShort = "La phrase secrète doit contenir au moins 12 caractères."
    let vaultErrPassphraseMismatch = "Les deux phrases secrètes ne correspondent pas."
    let vaultErrUsernameTaken = "Ce nom d'utilisateur est déjà pris."
    let vaultErrRegistrationClosed = "Ce serveur n'accepte pas de nouveaux comptes."
    let vaultErrInvalidCredentials = "Nom d'utilisateur ou phrase secrète incorrect."
    let vaultErrUnsafeKdf = "Le serveur impose des paramètres de sécurité trop faibles. Connexion refusée par précaution."
    let vaultErrKeyring = "Le serveur a répondu, mais vos clés n'ont pas pu être ouvertes sur cette version de l'app."
    let vaultErrServer = "Le serveur a rencontré un problème. Réessayez plus tard."
    let vaultErrKeychain = "Impossible d'enregistrer la session dans le trousseau de l'appareil."
    let vaultErrCrypto = "Le calcul des clés a échoué sur cet appareil."
    func vaultServerFound(_ name: String) -> String { "Serveur trouvé : \(name)" }
    func vaultSignedInAs(_ username: String, host: String) -> String { "Connecté en tant que \(username) sur \(host)" }
    func vaultErrTooManyAttempts(_ seconds: Int?) -> String { seconds.map { "Trop de tentatives. Réessayez dans \(max(1, ($0 + 59) / 60)) min." } ?? "Trop de tentatives. Réessayez plus tard." }
    let vaultHeroTitle = "Votre coffre-fort privé"
    let vaultBenefitSync = "Tout votre journal y est sauvegardé et reste à jour sur tous vos appareils."
    func vaultTransferHint(_ meals: Int) -> String { "Vos \(meals) repas seront sauvegardés dans le coffre-fort tout de suite." }
    let vaultSyncing = "Synchronisation du journal…"
    func vaultSynced(_ meals: Int) -> String { "Journal synchronisé : \(meals) repas" }
    let vaultSyncOffline = "Hors ligne. Vos repas se synchroniseront dès que le coffre-fort sera joignable."
    let vaultSyncFull = "Votre coffre-fort est plein. Libérez de la place pour continuer à synchroniser."
    let vaultSyncFailed = "La synchronisation a rencontré un problème. Elle va réessayer."
    let vaultSyncNow = "Synchroniser maintenant"
    let vaultBenefitVoice = "Dictez vos repas à voix haute au lieu de les saisir."
    let vaultBenefitPrivate = "Vos données sont chiffrées avant de quitter votre téléphone et restent chiffrées dans le cloud. Personne d'autre ne peut les lire, nous non plus."
    func vaultOfficialServer(_ host: String) -> String { "Coffre-fort officiel : \(host)" }
    let vaultAdvanced = "Avancé"
    let vaultAdvancedHint = "La plupart des gens n'en ont jamais besoin. Utilisez votre propre serveur de coffre-fort au lieu du serveur officiel."
    let vaultCreateVault = "Créer mon coffre-fort"
    let vaultGeneratedHint = "Nous générons pour vous une phrase secrète solide. Vous la conserverez dans un kit de secours, à l'écran suivant."
    let vaultOwnPassphrase = "Choisir ma propre phrase secrète"
    let vaultGeneratePassphrase = "En générer une pour moi"
    let vaultRecoveryKeyLabel = "Clé de récupération"
    let vaultKitShare = "Me l'envoyer"
    func vaultKitText(host: String, username: String, passphrase: String?, recoveryKey: String) -> String {
        var lines = ["Coffre-fort Pocket Nutrition : kit de secours", "Serveur : \(host)", "Identifiant : \(username)"]
        if let passphrase { lines.append("Phrase secrète : \(passphrase)") }
        lines.append("Clé de récupération : \(recoveryKey)")
        lines.append("")
        lines.append("Gardez ceci en lieu sûr et privé. Personne, nous non plus, ne peut le récupérer pour vous.")
        return lines.joined(separator: "\n")
    }
    let vaultConnecting = "Connexion au coffre-fort…"
    let vaultRetry = "Réessayer"
    let journalVaultCardTitle = "Activez votre coffre-fort"
    let journalVaultCardBody = "Sauvegardez votre journal dans un coffre-fort chiffré que vous seul pouvez ouvrir, et dictez vos repas."
    let journalVaultCardAction = "Activer"
    let journalVaultCardLater = "Plus tard"

    // Vault account security
    let vaultLockReason = "Déverrouiller les réglages du coffre"
    let vaultLockEnableReason = "Confirmez que c'est vous pour activer le verrouillage du coffre"
    let vaultLockPasscode = "le code de l'appareil"
    let vaultLockedTitle = "Coffre verrouillé"
    let vaultLockedBody = "Votre journal continue de se synchroniser. Déverrouillez pour gérer votre compte."
    let vaultUnlock = "Déverrouiller"
    let vaultSessionTitle = "Expiration de la session"
    func vaultLockToggle(_ biometry: String) -> String { "Verrouiller avec \(biometry)" }
    let vaultTimeoutLabel = "Délai d'expiration"
    func vaultTimeoutOption(_ timeout: VaultSessionTimeout) -> String {
        switch timeout {
        case .immediately: "Immédiatement"
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 heure"
        case .fourHours: "4 heures"
        case .onRestart: "Au redémarrage de l'app"
        case .never: "Jamais"
        }
    }
    let vaultTimeoutActionLabel = "Action à l'expiration"
    func vaultTimeoutAction(_ action: VaultTimeoutAction) -> String {
        switch action {
        case .lock: "Verrouiller"
        case .logOut: "Se déconnecter"
        }
    }
    let vaultSessionHint = "Temps passé avec l'app en arrière-plan. Se déconnecter garde vos repas sur ce téléphone ; vous vous reconnectez avec votre phrase secrète. Activez le verrouillage pour pouvoir verrouiller à la place."
    let vaultSessionHintLock = "Temps passé avec l'app en arrière-plan. Le verrouillage masque seulement ces réglages : votre journal continue de se synchroniser."
    let vaultDevicesTitle = "Gérer les appareils"
    let vaultDevices = "Appareils"
    let vaultDevicesHint = "Tous les appareils connectés à votre coffre. Révoquez celui que vous avez perdu ou n'utilisez plus : il arrête aussitôt de se synchroniser."
    let vaultDevicesEmpty = "Aucun appareil trouvé."
    let vaultDeviceUnnamed = "Appareil sans nom"
    func vaultDeviceLinked(_ date: String) -> String { "Connecté le \(date)" }
    let vaultThisDevice = "Cet appareil"
    let vaultRevoke = "Révoquer"
    func vaultRevokeTitle(_ label: String) -> String { "Révoquer \(label) ?" }
    let vaultRevokeBody = "Cet appareil est déconnecté du coffre. Ce qu'il a déjà téléchargé reste dessus."
    let vaultOtherOptions = "Autres options"
    let vaultFingerprintTitle = "Phrase d'empreinte"
    let vaultFingerprintExplanation = "Cette phrase identifie les clés de votre compte. Elle est la même sur tous vos appareils ; si un autre appareil affiche d'autres mots, il n'a pas reçu vos vraies clés."
    let vaultChangePassphraseTitle = "Changer la phrase secrète"
    let vaultNewPassphrase = "Nouvelle phrase secrète"
    let vaultTwoFactorTitle = "Authentification à deux facteurs"
    let vaultTwoFactorOff = "Double authentification désactivée"
    let vaultTwoFactorIntro = "La connexion sur un nouvel appareil demandera aussi un code d'une app d'authentification (Mots de passe, 1Password, Google Authenticator…). Les appareils déjà connectés ne sont pas concernés. Saisissez votre phrase secrète pour commencer."
    let vaultTwoFactorStart = "Configurer la double authentification"
    let vaultTwoFactorSetupTitle = "Ajoutez le coffre à votre app d'authentification"
    let vaultTwoFactorSetupBody = "Ajoutez ce compte à votre app d'authentification, puis saisissez le code à 6 chiffres qu'elle affiche."
    let vaultTwoFactorOpenApp = "Ouvrir dans mon app d'authentification"
    let vaultTwoFactorQR = "QR code à scanner avec une app d'authentification sur un autre appareil"
    let vaultTwoFactorManual = "Ou saisissez cette clé dans l'app :"
    let vaultTwoFactorCodeLabel = "Code à 6 chiffres"
    let vaultTwoFactorConfirm = "Activer la double authentification"
    let vaultTwoFactorOn = "Double authentification activée"
    func vaultTwoFactorOnBody(_ recoveryCodesLeft: Int) -> String { "Un code est demandé à la connexion sur un nouvel appareil. \(recoveryCodesLeft) code\(recoveryCodesLeft > 1 ? "s" : "") de secours restant\(recoveryCodesLeft > 1 ? "s" : ""). Pour la désactiver, saisissez votre phrase secrète et un code." }
    let vaultTwoFactorCodeOrRecovery = "Code ou code de secours"
    let vaultTwoFactorDisable = "Désactiver la double authentification"
    let vaultTwoFactorLoginHint = "Ce compte utilise la double authentification. Saisissez le code de votre app d'authentification, ou un code de secours."
    let vaultRecoveryCodesTitle = "Vos codes de secours"
    let vaultRecoveryCodesBody = "Chaque code vous connecte une fois si vous perdez votre app d'authentification. Ils ne sont affichés que maintenant : rangez-les avec votre kit de secours."
    let vaultRecoveryCodesDone = "Je les ai enregistrés"
    func vaultRecoveryCodesText(_ codes: [String]) -> String {
        (["Coffre Pocket Nutrition : codes de secours de la double authentification"] + codes + ["", "Chaque code ne fonctionne qu'une fois."]).joined(separator: "\n")
    }
    let vaultCopy = "Copier"
    let vaultCopied = "Copié"
    let vaultErrInvalidTwoFactor = "Code incorrect ou déjà utilisé."
    let vaultErrKeyringConflict = "Vos clés ont été modifiées depuis un autre appareil. Rouvrez cet écran et réessayez."
    let vaultErrNoPassphrase = "Ce compte n'a pas de phrase secrète à changer."
    let vaultErrTwoFactorChanged = "La double authentification a été modifiée depuis un autre appareil. Rouvrez cet écran."
    let vaultErrDeviceRevoked = "Cet appareil n'est plus connecté au coffre. Déconnectez-vous puis reconnectez-vous."
    let vaultErrTwoFactorRequired = "La double authentification est activée : saisissez un code de votre application d'authentification ou un code de récupération."

    let vaultFingerprintNotPassphrase = "Ce n'est pas votre phrase secrète : elle sert seulement à vérifier qu'un autre appareil a les mêmes clés."

    let vaultKitShareOrSave = "Partager ou enregistrer…"
    let vaultKitShared = "Kit partagé"
    let vaultKitCannotShowAgain = "Votre phrase secrète ne pourra plus être affichée. Sans elle ni la clé de récupération, impossible de connecter un nouvel appareil."
    let vaultKitSaveFirst = "Copiez d'abord le kit ou partagez-le en lieu sûr."
    func vaultKitWordPrompt(_ position: Int) -> String { "Tapez le mot \(position) de votre phrase secrète" }
    let vaultKitWholePrompt = "Tapez votre phrase secrète"
    let vaultKitWordWrong = "Ça ne correspond pas. Vérifiez votre kit enregistré."

    let vaultPassphraseChoiceGenerated = "Générer une phrase (recommandé)"
    let vaultPassphraseChoiceOwn = "Choisir la mienne"
    let vaultResetIntro = "Votre phrase secrète actuelle n'est pas demandée : ce téléphone est connecté et détient vos clés, il peut donc en définir une nouvelle même si vous l'avez oubliée. Voici ce qui va se passer :"
    let vaultResetEffects = [
        "Une nouvelle clé de récupération est créée et affichée une seule fois, avec votre nouvelle phrase secrète, dans un nouveau kit de secours.",
        "Vos autres appareils connectés et la consultation web sont déconnectés. Ils devront se reconnecter avec la nouvelle phrase secrète.",
        "Votre ancienne clé de récupération ne fonctionnera plus.",
        "Ce téléphone reste connecté et votre journal est conservé tel quel.",
    ]
    let vaultResetTwoFactorHint = "La double authentification est activée : saisissez un code de votre application d'authentification ou un code de récupération."
    let vaultResetConfirm = "Changer la phrase secrète"
    let vaultResetReason = "Confirmez votre identité pour changer la phrase secrète du coffre"
    let vaultResetNeedsPasscode = "Définissez d'abord un code sur cet appareil : c'est lui qui protège cette étape."
    let vaultResetAuthFailed = "L'appareil n'a pas pu confirmer votre identité. Rien n'a été modifié."
    let vaultResetDoneTitle = "Votre nouveau kit de secours"
    func vaultResetDoneBody(_ revokedDevices: Int) -> String {
        let devices = revokedDevices == 0 ? "Aucun autre appareil n'était connecté." : "\(revokedDevices) autre\(revokedDevices == 1 ? " appareil a été déconnecté" : "s appareils ont été déconnectés")."
        return "Votre phrase secrète a été remplacée. \(devices) Enregistrez ce kit avant de quitter cet écran."
    }
    let vaultResetFinish = "Terminé, mon kit est enregistré"

    let voiceRetryLookup = "Réessayer la recherche"
    let voiceStorageUnavailable = "Stockage indisponible — vos enregistrements sont conservés sur le téléphone. Réessayez."
    let voiceRecord = "Enregistrer un repas"
    let voiceStop = "Arrêter et envoyer"
    let voiceRecording = "Enregistrement…"
    let voiceMicExplainerTitle = "Accès au micro"
    let voiceMicExplainerBody = "Pocket Nutrition enregistre quelques secondes de votre voix pour décrire un repas. L'enregistrement est envoyé à votre serveur de reconnaissance vocale et reste sur le téléphone jusqu'à la réception du résultat (7 jours au maximum), puis il est supprimé."
    let voiceMicExplainerContinue = "Continuer"
    let voiceMicDeniedTitle = "Micro désactivé"
    let voiceMicDeniedBody = "L'accès au micro est refusé. Autorisez-le dans les Réglages de l'iPhone pour enregistrer un repas."
    let voiceMicFailed = "Impossible de démarrer l'enregistrement."
    let voiceSaveFailed = "Impossible de sauvegarder l'enregistrement sur le téléphone."
    let voiceStatusPendingUpload = "En attente d'envoi"
    let voiceStatusQueued = "Sera traité prochainement"
    let voiceStatusTranscribing = "Transcription…"
    let voiceStatusExtracting = "Analyse des aliments…"
    let voiceStatusFailed = "Échec"
    let voiceStatusInProgress = "En cours…"
    let voicePendingOffline = "En attente d'envoi — hors ligne"
    let voiceSendNow = "Envoyer maintenant"
    let voiceRetry = "Renvoyer"
    let voiceOpen = "Ouvrir"
    let voiceRefresh = "Actualiser"
    let voiceDismiss = "Masquer"
    let dictationStart = "Dicter un repas"
    func journalCaptureTitle(_ time: String) -> String { "Repas en cours · \(time)" }
    let photoStart = "Photographier un repas"
    let photoTake = "Prendre une photo"
    let photoChoose = "Choisir dans la photothèque"
    let photoSaveFailed = "La photo n'a pas pu être enregistrée."
    let photoCameraDeniedTitle = "Accès à l'appareil photo désactivé"
    let photoCameraDeniedBody = "Autorisez l'appareil photo pour Pocket Nutrition dans Réglages pour photographier un repas. Vous pouvez toujours choisir une photo dans votre photothèque."
    let photoDescriptionTitle = "Ce qui a été vu"
    let dictationAnalyzing = "Analyse de votre repas…"
    let dictationSlow = "Cela prend un moment. Vous pouvez continuer ou quitter : le résultat vous attendra dans votre journal."
    let dictationSavedOffline = "Enregistré. L'envoi se fera dès que vous serez de nouveau en ligne."
    let dictationFailed = "Votre repas n'a pas pu être analysé."
    let dictationNothing = "Rien n'a pu être ajouté."
    let dictationReview = "Vérifier"
    func dictationAdded(_ count: Int) -> String { "\(count) ingrédient\(count == 1 ? "" : "s") ajouté\(count == 1 ? "" : "s")." }
    func dictationSkipped(added: Int, names: String) -> String { "\(added) ajouté\(added == 1 ? "" : "s"). Impossible d'ajouter : \(names)." }
    let voiceApiKeyRefused = "Clé d'API refusée"
    let voiceExpiredKept = "Expiré — l'enregistrement est toujours sur votre téléphone"
    let voiceGoneKept = "Résultat introuvable sur le serveur — l'enregistrement est toujours sur votre téléphone"
    let voiceFailedKept = "Échec du traitement — l'enregistrement est toujours sur votre téléphone"
    let voiceUnrecoverable = "L'enregistrement n'est plus disponible : il ne peut pas être renvoyé."
    let voiceReviewTitle = "Vérification"
    let voiceTranscriptTitle = "Ce qui a été compris"
    let voiceSkipItem = "Ignorer cet élément"
    let voiceNoCandidates = "Aucun aliment proposé"
    let voiceAddToMeal = "Ajouter au repas"
    let voiceImporting = "Recherche des aliments…"
    let voiceSkippedTitle = "Éléments ignorés"
    let voiceNothingImported = "Aucun élément n'a pu être ajouté."
    let voiceContinue = "Continuer"
    let voiceReasonNoCandidate = "aucun aliment proposé"
    let voiceReasonUnknown = "aliment introuvable dans le catalogue"
    let voiceReasonNotBuildable = "données insuffisantes (poids ou mode de cuisson inconnu)"
    let voiceReasonLookupFailed = "recherche impossible (réseau)"
    func voiceElapsed(_ seconds: Int, of limit: Int) -> String { "\(seconds) s / \(limit) s" }
    func voiceReadyItems(_ count: Int) -> String { "Prêt — \(count) élément\(count > 1 ? "s" : "")" }
    func voiceSkippedItem(_ text: String, reason: String) -> String { "« \(text) » : \(reason)" }
}

// MARK: - Daily targets (client-authored, see `TargetsStrings`)

extension FrStrings {
    var targetsPreviewToggle: String { "Objectifs du jour (aperçu)" }
    var targetsPreviewBody: String {
        "Des objectifs quotidiens calculés à partir des valeurs de référence de l’EFSA, sur cet appareil. "
            + "Votre profil et votre poids ne sont jamais envoyés au serveur."
    }
    var targetsTitle: String { "Objectifs du jour" }
    var targetsSetMine: String { "Définir mes objectifs" }
    var targetsSetMineBody: String { "Facultatif : quelques questions pour des objectifs tirés des valeurs de l’EFSA." }
    var targetsEditAnswers: String { "Modifier mes réponses" }
    var targetsScreenTitle: String { "Nutriments et objectifs" }
    var targetsExplanationTitle: String { "Comment c’est calculé" }
    var targetsNeedConnection: String { "Les objectifs ont besoin d’une connexion la première fois." }
    var targetsNotMedicalAdvice: String { "Information, pas un avis médical." }
    func targetsUnsupported(_ reason: UnsupportedTargetReason) -> String {
        switch reason {
        case .infant: "Les besoins d’un enfant de moins d’un an relèvent d’un professionnel de santé."
        case .pregnancyUnder18, .lactationUnder18:
            "Les valeurs de l’EFSA pour la grossesse et l’allaitement concernent les adultes. "
                + "Demandez vos objectifs à un professionnel de santé ; vous pouvez les saisir vous-même."
        }
    }
    var targetsNoProfile: String { "Aucun profil : chaque objectif vient d’une valeur que vous avez saisie." }

    var qSkip: String { "Passer, je saisis mes valeurs" }
    var qNext: String { "Suivant" }
    var qBack: String { "Retour" }
    var qSave: String { "Enregistrer" }
    func qStep(_ index: Int, of total: Int) -> String { "Étape \(index) sur \(total)" }
    var qBirthYear: String { "Année de naissance" }
    var qBody: String { "Taille et poids" }
    var qHeight: String { "Taille (cm)" }
    var qWeight: String { "Poids (kg)" }
    var qHeightNote: String { "La taille est gardée pour plus tard : les valeurs de l’EFSA n’utilisent que le poids." }
    var qBasis: String { "Base de calcul" }
    var qBasisNote: String {
        "L’EFSA publie des valeurs différentes pour les femmes et les hommes. Nous ne demandons jamais votre genre : "
            + "choisissez les valeurs avec lesquelles calculer."
    }
    func basisName(_ basis: CalculationBasis) -> String {
        switch basis {
        case .female: "Valeurs de référence femmes"
        case .male: "Valeurs de référence hommes"
        case .average: "Une moyenne des deux"
        }
    }
    var qPostmenopausal: String { "Ménopausée ?" }
    var qYes: String { "Oui" }
    var qNo: String { "Non" }
    var qSituation: String { "Situation" }
    var qSituationFemaleOnly: String { "Proposé avec les valeurs de référence femmes." }
    func situationName(_ situation: TargetSituation) -> String {
        switch situation {
        case .none: "Aucune de ces situations"
        case .pregnant: "Enceinte"
        case .lactating: "J’allaite"
        }
    }
    var qTrimester: String { "Trimestre" }
    func trimesterName(_ trimester: Int) -> String { trimester == 1 ? "1er trimestre" : "\(trimester)e trimestre" }
    var qLactation: String { "Depuis la naissance" }
    func lactationName(_ period: LactationPeriod) -> String {
        switch period {
        case .firstSixMonths: "0 à 6 mois"
        case .afterSixMonths: "Plus de 6 mois"
        }
    }
    var qActivity: String { "Niveau d’activité" }
    func activityName(_ level: ActivityLevel) -> String {
        switch level {
        case .sedentary: "Sédentaire"
        case .moderate: "Modérément actif"
        case .active: "Actif"
        case .veryActive: "Très actif"
        }
    }
    func activityExample(_ level: ActivityLevel) -> String {
        switch level {
        case .sedentary: "Travail de bureau, peu de marche"
        case .moderate: "Debout une partie de la journée, ou 3 séances par semaine"
        case .active: "Travail physique, ou sport chaque jour"
        case .veryActive: "Travail physique dur ou entraînement intense quotidien"
        }
    }
    var qPreview: String { "Vos objectifs" }
    var qPreviewNeedsTable: String { "L’aperçu a besoin d’une connexion. Vos réponses seront tout de même enregistrées." }

    var presetTitle: String { "Préréglage" }
    func presetName(_ preset: String) -> String {
        switch preset {
        case "standard": "Standard"
        case "sport": "Sport"
        case "kidney": "Rein"
        case "hypertension": "Hypertension"
        case "diabetes": "Diabète"
        case "everything": "Tout"
        default: "Personnalisé"
        }
    }
    var presetMedicalBanner: String {
        "Ce sont des valeurs pour la population générale. Saisissez les objectifs donnés par votre médecin ou votre diététicien."
    }
    var presetMedicalAction: String { "Saisir mes valeurs" }
    var watchShown: String { "Suivis" }
    var watchHidden: String { "Non suivis" }
    var targetKindGoal: String { "objectif" }
    var targetKindRange: String { "fourchette" }
    var targetKindLimit: String { "limite" }
    var targetKindNone: String { "pas d’objectif" }
    var targetEdit: String { "Modifier" }
    var targetReset: String { "Revenir à l’EFSA" }
    var targetResetAll: String { "Tout revenir à l’EFSA" }
    var targetOverridden: String { "modifié par vous" }
    var targetMin: String { "Minimum" }
    var targetMax: String { "Maximum" }
    var targetCancel: String { "Annuler" }
    var targetEditHint: String { "Laissez un champ vide pour n’avoir qu’un minimum ou qu’un maximum." }

    var ringLimit: String { "limite" }
    func ringUsual(_ value: String) -> String { "habituel \(value)" }
    func coverage(_ known: Int, of total: Int) -> String { "d’après \(known) repas sur \(total)" }
    var dayDetailTitle: String { "Détail du jour" }
    var groupMacros: String { "Énergie et macronutriments" }
    var groupFats: String { "Acides gras" }
    var groupMinerals: String { "Minéraux" }
    var groupVitamins: String { "Vitamines" }
    func statusName(_ status: ProgressStatus) -> String {
        switch status {
        case .noTarget: "pas d’objectif"
        case .under: "en dessous de l’objectif"
        case .ok: "dans l’objectif"
        case .over: "au-dessus de l’objectif"
        }
    }
    func aboveUpperLimit(_ value: String) -> String { "au-dessus de la limite de sécurité de l’EFSA (\(value))" }
    var topContributors: String { "Principaux apports" }
    var readWeekly: String { "Se lit mieux sur une semaine : voir la semaine" }
    var unknownValue: String { "inconnu" }
    var targetLabel: String { "Objectif" }
    var weekTitle: String { "Cette semaine" }
    func weekDaysWithData(_ count: Int) -> String { count <= 1 ? "\(count) jour renseigné" : "\(count) jours renseignés" }
    var trendsTitle: String { "Tendances" }
    func trendRange(_ days: Int) -> String { "\(days) j" }
    var trendTarget: String { "Objectif" }
    var trendTotal: String { "Total" }
    func nutrientName(_ key: String) -> String {
        switch key {
        case "energyKcal": "Énergie"
        case "proteinG": "Protéines"
        case "fatG": "Lipides"
        case "carbohydratesG": "Glucides"
        case "fiberG": "Fibres"
        case "waterG": "Eau"
        case "sugarsG": "Sucres"
        case "calciumMg": "Calcium"
        case "ironMg": "Fer"
        case "magnesiumMg": "Magnésium"
        case "sodiumMg": "Sodium"
        case "vitaminCMg": "Vitamine C"
        case "saturatedFatG": "Acides gras saturés"
        case "monounsaturatedFatG": "Acides gras mono-insaturés"
        case "polyunsaturatedFatG": "Acides gras polyinsaturés"
        case "cholesterolMg": "Cholestérol"
        case "potassiumMg": "Potassium"
        case "phosphorusMg": "Phosphore"
        case "zincMg": "Zinc"
        case "vitaminAUg": "Vitamine A"
        case "vitaminDUg": "Vitamine D"
        case "vitaminB6Mg": "Vitamine B6"
        case "vitaminB12Ug": "Vitamine B12"
        case "niacinMg": "Niacine (B3)"
        default: key
        }
    }
    var saltName: String { "Sel" }

    func valueKindName(_ kind: String) -> String {
        switch kind {
        case "pri": "PRI, apport de référence pour la population"
        case "ai": "AI, apport satisfaisant"
        case "ri": "RI, intervalle de référence"
        case "ul": "UL, limite supérieure de sécurité"
        case "ar_kcal", "ar": "AR, besoin moyen"
        default: kind
        }
    }
    var explanationSources: String { "Sources" }
    var explanationInputs: String { "Calculé avec" }
    func explanationAge(_ age: Int, band: String) -> String { "\(age) ans (tranche \(band))" }
    func explanationPal(_ pal: String) -> String { "Niveau d’activité physique (PAL) \(pal)" }
    func explanationWeight(_ kg: String) -> String { "Poids \(kg) kg" }
    func explanationBasis(_ basis: CalculationBasis) -> String { "Base : \(basisName(basis).lowercased())" }
    func explanationSituation(_ text: String) -> String { "Situation : \(text)" }
    var explanationChoicesTitle: String { "Nos choix" }
    var explanationChoices: [String] {
        [
            "Le PAL de chaque niveau d’activité : 1,4, 1,6, 1,8 et 2,0, la grille de l’EFSA.",
            "Le zinc pour une alimentation à 600 mg de phytates par jour, le niveau intermédiaire de l’EFSA.",
            "La base « moyenne des deux » fait la moyenne des valeurs femmes et hommes.",
            "Le poids utilisé est la moyenne de vos pesées des 7 derniers jours.",
            "Le sel est affiché à partir du sodium : sel (g) = sodium (mg) × 2,5 / 1000.",
        ]
    }
    func explanationProfileUpdated(_ date: String) -> String { "Profil mis à jour le \(date)" }
    var explanationOverriddenNote: String { "Valeur saisie par vous ; la valeur de l’EFSA reste affichée pour information." }
    func ageBandLabel(from: Int, to: Int?) -> String { to.map { "\(from)–\($0) ans" } ?? "\(from) ans et plus" }

    var weightTitle: String { "Poids" }
    var weightLog: String { "Noter mon poids" }
    var weightKg: String { "Poids (kg)" }
    var weightDate: String { "Date" }
    var weightSave: String { "Enregistrer" }
    var weightEntries: String { "Pesées" }
    var weightNone: String { "Aucune pesée pour le moment." }
    var weightTrend: String { "Évolution" }
    var weightMean: String { "Moyenne sur 7 jours" }
}
