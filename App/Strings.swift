// SPDX-License-Identifier: MPL-2.0

import PocketNutritionCore

/// Copy for the app, in whichever language is currently active.
///
/// WHERE THESE COME FROM
/// Every requirement here is transcribed **verbatim** from `contract/data/strings/fr.json`'s `fr`
/// and `en` values — the copy deck all three clients share — and carries the contract key it came
/// from. A few entries are marked "client-authored": no sandbox equivalent exists to transcribe
/// from, so both languages were written directly in this file, candidates for upstreaming into the
/// deck's `app` scope in a future `CONTRACTS_VERSION` bump — the same path the whole `about.*` group
/// and the barcode-scan strings once took.
///
/// TWO IMPLEMENTATIONS, ONE PROTOCOL, NOT TWO LOOSE ENUMS
/// Before contract 2.0.0 this was a single `enum Fr` of `static let`s — correct while there was only
/// one language. Splitting into `FrStrings`/`EnStrings` behind this protocol keeps every property a
/// compile-time-checked member (a typo is still a build error, the property this design always had
/// over a runtime dictionary lookup) while adding something the old enum could not: the compiler now
/// *enforces* that `EnStrings` has every member `FrStrings` has. Call sites read `Strings.active.x`,
/// which re-resolves to the active language on every read — see `Strings.active` below.
protocol AppStrings: TargetsStrings {

    // MARK: - App

    /// contract: app.brand — "Product name. Never translated."
    var brand: String { get }

    // MARK: - Journal
    //
    // contract: journal.*, scope `app`. The sandbox persists nothing and so has no journal; this group
    // was written for the native clients and lives in the deck under the scope that says so.

    /// contract: journal.title
    var journalTitle: String { get }
    /// contract: journal.empty
    var journalEmpty: String { get }
    /// contract: journal.add
    var journalAdd: String { get }
    /// contract: journal.delete
    var journalDelete: String { get }
    /// contract: journal.privacy — marked REQUIRED there rather than optional. The deck's own
    /// `welcome.privacy` claims no personal data is kept at all, which is false for an app that
    /// persists a diary — this is the corrected line for the apps.
    var journalPrivacy: String { get }

    // MARK: - About
    //
    // contract: about.*, scope `app`. Three obligations meet on one screen — MPL-2.0 §3.2 (tell the
    // recipient of a binary what rights they have), the ODbL attribution the Open Food Facts data
    // carries, and the reachable privacy-policy URL both consoles demand before a listing is accepted.

    var aboutTitle: String { get }
    /// contract: about.version — `{version}` is the marketing version, substituted at the call site.
    func aboutVersion(_ version: String) -> String
    var aboutPrivacyTitle: String { get }
    var aboutPrivacySummary: String { get }
    /// contract: about.privacyNetwork — what keeps `aboutPrivacySummary` from reading as "nothing is
    /// ever sent", which would be false. Do not ship one without the other.
    var aboutPrivacyNetwork: String { get }
    var aboutPrivacyLink: String { get }
    var aboutSourcesTitle: String { get }
    /// contract: about.sourcesBody — attribution required by the ODbL and the Open Government Licence, not a courtesy credit.
    var aboutSourcesBody: String { get }
    var aboutLicenceTitle: String { get }
    var aboutLicenceBody: String { get }
    var aboutSourceLink: String { get }
    var aboutThirdPartyTitle: String { get }
    /// contract: about.thirdPartyNone — true for this target, and checked rather than assumed: see
    /// `AboutView`'s note on how to verify it before each release.
    var aboutThirdPartyNone: String { get }
    var aboutClose: String { get }

    // MARK: - Settings
    //
    // The language switcher and the server override used to share the About screen with the
    // licence/attribution/privacy obligations above; contract 2.1.0 split them into their own
    // screen so the journal's menu can offer About and Settings as two distinct entries.

    /// contract: settings.title — also the label of the "Settings" menu row; About's own row
    /// reuses `aboutTitle` the same way.
    var settingsTitle: String { get }

    // MARK: - Language switcher (Settings screen)
    //
    // contract: about.language* — the key namespace still says "about" (it predates the Settings
    // screen split and renaming it would be a contract change of its own), but the strings now
    // render on the Settings screen.

    var aboutLanguageTitle: String { get }
    var aboutLanguageAuto: String { get }
    var aboutLanguageFr: String { get }
    var aboutLanguageEn: String { get }

    // MARK: - Server override (Settings screen)
    //
    // Client-authored, not yet in contract/data/strings/fr.json — the sandbox has no equivalent
    // screen, so there is no wording to transcribe from.

    var aboutServerTitle: String { get }
    var aboutServerBody: String { get }
    var aboutServerApply: String { get }
    var aboutServerReset: String { get }
    var aboutServerInvalid: String { get }

    // MARK: - Search

    /// contract: search.placeholderSingle. Not `search.placeholder` — that one advertises the
    /// sandbox's multi-term search; this app adds one food per tap.
    var searchPlaceholder: String { get }
    var searchNoResults: String { get }
    /// contract: search.multiTermHint. Carries what `search.placeholder` cannot on a phone-width field.
    var multiTermHint: String { get }
    /// contract: search.confirmAdd — "Ajouter ({count})". Multi-select confirm.
    func confirmAdd(count: Int) -> String
    var searchAlreadyAdded: String { get }
    var searchProductBadge: String { get }
    /// contract: search.recipePrefix.
    var searchRecipePrefix: String { get }
    /// contract: search.recipeComponentCount — not pluralised in the source even in French, a
    /// recorded defect transcribed verbatim rather than quietly fixed here.
    var searchRecipeComponentCount: String { get }
    var searchSectionRecipes: String { get }
    var searchSectionIngredients: String { get }
    var searchSectionProducts: String { get }
    var searchCancel: String { get }

    // MARK: - Meal builder

    var mealHeading: String { get }
    func mealSlotName(_ slot: MealSlot) -> String
    var mealChangeTime: String { get }
    var mealTimeTitle: String { get }
    func journalSameAsYesterday(_ items: String) -> String
    var dishesTitle: String { get }
    func recentsTitle(_ slot: MealSlot) -> String
    func dishDetail(ingredients: Int, servings: Int) -> String
    func recentDetail(grams: Double, method: String) -> String
    var saveAsDish: String { get }
    var dishNameField: String { get }
    func dishServings(_ count: Int) -> String
    var dishSave: String { get }
    func dishUpdate(_ name: String) -> String
    var dishMenuA11y: String { get }
    func dishPartsUnit(servings: Int, parts: Double) -> String
    var pin: String { get }
    var unpin: String { get }
    var deleteDish: String { get }
    func quickAddRow(_ kcal: Int) -> String
    var quickAddNote: String { get }
    func shortcutAddA11y(_ name: String) -> String
    var logAgainNow: String { get }
    var scanReport: String { get }
    var scanReportSent: String { get }
    func journalRepeatYesterdayA11y(_ slot: String) -> String
    var mealEmpty: String { get }
    /// contract: mealBuilder.analysing. Currently unused — kept for the reasons noted on `mealAnalyse`.
    var mealAnalysing: String { get }
    /// contract: mealBuilder.analyse — "Analyser le repas ({count} aliment{s})". Currently unused: the
    /// total recomputes itself in the background instead of behind a blocking tap. Kept because it is
    /// a shared-deck entry and a manual re-analyse affordance is the kind of thing that comes back.
    /// The plural rule is language-specific, not delegated to `pluralize`: what varies here is a bare
    /// suffix inside a sentence, not a whole word.
    func mealAnalyse(count: Int) -> String
    var mealRemove: String { get }
    /// Accessibility label for the expanded ingredient row's collapse chevron. App-only chrome.
    var collapse: String { get }
    /// The weight field's decimal-pad keyboard toolbar dismiss button — app-only chrome, the standard
    /// platform wording rather than the shared deck's generic "Valider".
    var done: String { get }
    /// contract: mealBuilder.quantity. Currently unused — the portion ladder's own summary line
    /// replaced the bare grams field this labelled. Kept because it is a shared-deck entry.
    var mealQuantity: String { get }
    /// contract: mealBuilder.cooking. The sandbox needs no such label — its method is implied by which
    /// drop-lane a card sits in, and this app has no lanes.
    var mealCooking: String { get }

    // MARK: - Cooking methods
    //
    // contract: cookingMethods.*, keyed by the same ids as PnCooking.methods in the design tokens.

    /// `cookingMethods.cookedGeneric` covers a method id the token set does not know, reachable
    /// because the API may return one — showing the raw id would leak an untranslated identifier.
    func cookingMethod(_ id: String) -> String

    // MARK: - Nutrients
    //
    // contract: nutrients.*

    var nutrientEnergy: String { get }
    var nutrientProtein: String { get }
    var nutrientCarbs: String { get }
    var nutrientFat: String { get }
    /// contract: nutrients.proteinAbbr — compact per-ingredient row, "P: 12.0 g".
    var nutrientProteinAbbr: String { get }
    /// contract: nutrients.carbsAbbr.
    var nutrientCarbsAbbr: String { get }
    /// contract: nutrients.fatAbbr.
    var nutrientFatAbbr: String { get }

    // MARK: - Results

    /// contract: results.total
    var resultsTotal: String { get }
    /// contract: results.edit. Currently unused — kept for the same reason as `mealQuantity`.
    var resultsEdit: String { get }
    /// contract: results.save
    var resultsSave: String { get }
    /// contract: results.unavailable — shown when `available` is false. Must NOT be replaced by zeros.
    var resultsUnavailable: String { get }
    /// Client-authored: the meal total when no row could be computed — unknown, never "0 kcal".
    var resultsTotalUnknown: String { get }
    /// contract: results.rowSummary — "{quantity} {unit} · {method} · pesé {state}". `quantity` goes
    /// through `formatNumber` in the active language, not a locale formatter — the corpus rule.
    func resultsRowSummary(quantity: Double, unit: String, method: String, state: String) -> String

    // MARK: - Measured state
    //
    // contract: measuredState.*

    func measuredState(_ id: String) -> String
    /// contract: measuredState.beforeLong — paired with 🌿, per the deck's own context note.
    var measuredBeforeLong: String { get }
    /// contract: measuredState.afterLong — paired with 🍽️.
    var measuredAfterLong: String { get }
    /// contract: ingredientCard.weighedLabel — the French source carries a non-breaking space before
    /// the colon (French typography); the English translation does not, since that convention is
    /// French-specific.
    var weighedLabel: String { get }
    var weighedGroupAria: String { get }
    /// contract: ingredientCard.weighedInline — "(pesé {when} cuisson)", shown inside the collapsed
    /// method pill. `when` comes from `measuredWhen`.
    func weighedInline(_ when: String) -> String
    /// contract: measuredState.before / .after — the short forms, used only by `weighedInline`.
    func measuredWhen(_ state: String) -> String
    var changeCooking: String { get }
    /// contract: ingredientCard.report — discreet footer link opening the feedback dialog.
    var ingredientReport: String { get }
    var ingredientReportAria: String { get }

    // MARK: - Feedback
    //
    // contract: feedback.*. Category and error labels are not here: they travel with their own code in
    // `FeedbackCatalog`, which stays French-only — see that type for why.

    var feedbackTitle: String { get }
    var feedbackIntro: String { get }
    /// contract: feedback.referenceWeight — current-value hint shown beside the form.
    var feedbackReferenceWeight: String { get }
    var feedbackDisplayUnit: String { get }
    var feedbackUnits: String { get }
    var feedbackComment: String { get }
    /// contract: feedback.add — adds one correction to the pending list.
    var feedbackAdd: String { get }
    var feedbackRemoveCorrection: String { get }
    var feedbackSubmit: String { get }
    var feedbackSubmitting: String { get }
    var feedbackSuccess: String { get }
    var feedbackFailure: String { get }
    var feedbackClose: String { get }
    var feedbackUnitAria: String { get }

    // Feedback form: current data and per-field help (client-authored)
    var feedbackPendingTitle: String { get }
    var feedbackCurrentDataTitle: String { get }
    var feedbackCurrentDataLoading: String { get }
    var feedbackCorrectValue: String { get }
    func feedbackCurrent(_ value: String) -> String
    func feedbackHelp(_ code: String) -> String?
    var feedbackTechIngredient: String { get }
    var feedbackTechCooking: String { get }
    var feedbackTechMeasured: String { get }
    var feedbackTechEatability: String { get }
    var feedbackTechYields: String { get }
    var feedbackTechYieldNone: String { get }
    var feedbackTechReferenceWeight: String { get }
    var feedbackTechUnits: String { get }
    var feedbackTechFoodGroup: String { get }
    var feedbackTechPer100: String { get }
    func feedbackEatability(raw: Bool?, cooked: Bool?) -> String?
    func feedbackMeasuredState(_ state: String) -> String

    // MARK: - Barcode scan
    //
    // Client-authored, not yet in contract/data/strings/fr.json — no scan/camera/barcode keys exist in
    // the shared deck yet.

    var scanBarcodeButton: String { get }
    var scanExplainerTitle: String { get }
    var scanExplainerBody: String { get }
    var scanExplainerContinue: String { get }
    var scanExplainerNotNow: String { get }
    var scanSettingsTitle: String { get }
    var scanSettingsBody: String { get }
    var scanSettingsOpenSettings: String { get }
    var scanLookingUp: String { get }
    var scanNotFoundTitle: String { get }
    var scanNotFound: String { get }
    var scanErrorTitle: String { get }
    var scanUnavailableTitle: String { get }
    var scanUnavailable: String { get }

    // MARK: - Cooking method picker — yield hint
    //
    // Client-authored, not yet in contract/data/strings/fr.json. Explains why the weight moves when a
    // different cooking method is chosen.

    /// `display` is the ratio, already formatted in the active language; `heavier` is whether the food
    /// gains weight (true, e.g. rice absorbing water) or loses it (false, e.g. grilled meat).
    func yieldHint(display: String, heavier: Bool) -> String

    // MARK: - Errors

    /// contract: errors.prefix — "Erreur : {message}" / "Error: {message}".
    func error(_ message: String) -> String
    /// contract: errors.retry
    var retry: String { get }

    // MARK: - Voice capture (client-authored; the recognition endpoint is not in contracts 2.0.0)

    var recognitionSettingsTitle: String { get }
    var recognitionSettingsBody: String { get }
    var recognitionServerLabel: String { get }
    var recognitionKeyLabel: String { get }
    var recognitionKeySavedPlaceholder: String { get }
    var recognitionSave: String { get }
    var recognitionClear: String { get }
    var recognitionInvalidURL: String { get }
    var recognitionMissingKey: String { get }
    var recognitionSaveFailed: String { get }
    var recognitionSaved: String { get }
    var recognitionKeyRequiredForNewHost: String { get }
    var recognitionClearFailed: String { get }


    // MARK: - Cloud vault (client-authored; the vault is not in contracts 2.0.0)

    var vaultTitle: String { get }
    var vaultIntro: String { get }
    var vaultServerLabel: String { get }
    var vaultCheckServer: String { get }
    var vaultRegistrationClosed: String { get }
    var vaultUsernameLabel: String { get }
    var vaultPassphraseLabel: String { get }
    var vaultPassphraseConfirmLabel: String { get }
    var vaultPassphraseHint: String { get }
    var vaultCreateAccount: String { get }
    var vaultLogin: String { get }
    var vaultRecoveryTitle: String { get }
    var vaultRecoveryBody: String { get }
    var vaultRecoveryCopy: String { get }
    var vaultRecoveryCopied: String { get }
    var vaultRecoveryContinue: String { get }
    var vaultLogout: String { get }
    var vaultLogoutUnreached: String { get }
    var vaultDeleteAccount: String { get }
    var vaultDeleteBody: String { get }
    var vaultDeleteConfirm: String { get }
    var vaultCancel: String { get }
    var vaultErrInvalidServer: String { get }
    var vaultErrNotAVault: String { get }
    var vaultErrOffline: String { get }
    var vaultErrInvalidUsername: String { get }
    var vaultErrPassphraseShort: String { get }
    var vaultErrPassphraseMismatch: String { get }
    var vaultErrUsernameTaken: String { get }
    var vaultErrRegistrationClosed: String { get }
    var vaultErrInvalidCredentials: String { get }
    var vaultErrUnsafeKdf: String { get }
    var vaultErrKeyring: String { get }
    var vaultErrServer: String { get }
    var vaultErrKeychain: String { get }
    var vaultErrCrypto: String { get }
    func vaultServerFound(_ name: String) -> String
    func vaultSignedInAs(_ username: String, host: String) -> String
    func vaultErrTooManyAttempts(_ seconds: Int?) -> String
    var vaultHeroTitle: String { get }
    var vaultBenefitSync: String { get }
    func vaultTransferHint(_ meals: Int) -> String
    var vaultSyncing: String { get }
    func vaultSynced(_ meals: Int) -> String
    var vaultSyncOffline: String { get }
    var vaultSyncFull: String { get }
    var vaultSyncFailed: String { get }
    var vaultSyncNow: String { get }
    var vaultBenefitVoice: String { get }
    var vaultBenefitPrivate: String { get }
    func vaultOfficialServer(_ host: String) -> String
    var vaultAdvanced: String { get }
    var vaultAdvancedHint: String { get }
    var vaultCreateVault: String { get }
    var vaultGeneratedHint: String { get }
    var vaultOwnPassphrase: String { get }
    var vaultGeneratePassphrase: String { get }
    var vaultRecoveryKeyLabel: String { get }
    var vaultKitShare: String { get }
    func vaultKitText(host: String, username: String, passphrase: String?, recoveryKey: String) -> String
    var vaultConnecting: String { get }
    var vaultRetry: String { get }
    var journalVaultCardTitle: String { get }
    var journalVaultCardBody: String { get }
    var journalVaultCardAction: String { get }
    var journalVaultCardLater: String { get }

    // Vault account security
    var vaultLockReason: String { get }
    var vaultLockEnableReason: String { get }
    var vaultLockPasscode: String { get }
    var vaultLockedTitle: String { get }
    var vaultLockedBody: String { get }
    var vaultUnlock: String { get }
    var vaultSessionTitle: String { get }
    func vaultLockToggle(_ biometry: String) -> String
    var vaultTimeoutLabel: String { get }
    func vaultTimeoutOption(_ timeout: VaultSessionTimeout) -> String
    var vaultTimeoutActionLabel: String { get }
    func vaultTimeoutAction(_ action: VaultTimeoutAction) -> String
    var vaultSessionHint: String { get }
    var vaultSessionHintLock: String { get }
    var vaultDevicesTitle: String { get }
    var vaultDevices: String { get }
    var vaultDevicesHint: String { get }
    var vaultDevicesEmpty: String { get }
    var vaultDeviceUnnamed: String { get }
    func vaultDeviceLinked(_ date: String) -> String
    var vaultThisDevice: String { get }
    var vaultRevoke: String { get }
    func vaultRevokeTitle(_ label: String) -> String
    var vaultRevokeBody: String { get }
    var vaultOtherOptions: String { get }
    var vaultFingerprintTitle: String { get }
    var vaultFingerprintExplanation: String { get }
    var vaultChangePassphraseTitle: String { get }
    var vaultNewPassphrase: String { get }
    var vaultTwoFactorTitle: String { get }
    var vaultTwoFactorOff: String { get }
    var vaultTwoFactorIntro: String { get }
    var vaultTwoFactorStart: String { get }
    var vaultTwoFactorSetupTitle: String { get }
    var vaultTwoFactorSetupBody: String { get }
    var vaultTwoFactorOpenApp: String { get }
    var vaultTwoFactorQR: String { get }
    var vaultTwoFactorManual: String { get }
    var vaultTwoFactorCodeLabel: String { get }
    var vaultTwoFactorConfirm: String { get }
    var vaultTwoFactorOn: String { get }
    func vaultTwoFactorOnBody(_ recoveryCodesLeft: Int) -> String
    var vaultTwoFactorCodeOrRecovery: String { get }
    var vaultTwoFactorDisable: String { get }
    var vaultTwoFactorLoginHint: String { get }
    var vaultRecoveryCodesTitle: String { get }
    var vaultRecoveryCodesBody: String { get }
    var vaultRecoveryCodesDone: String { get }
    func vaultRecoveryCodesText(_ codes: [String]) -> String
    var vaultCopy: String { get }
    var vaultCopied: String { get }
    var vaultErrInvalidTwoFactor: String { get }
    var vaultErrKeyringConflict: String { get }
    var vaultErrNoPassphrase: String { get }
    var vaultErrTwoFactorChanged: String { get }
    var vaultErrDeviceRevoked: String { get }
    var vaultErrTwoFactorRequired: String { get }

    // Fingerprint phrase vs passphrase
    var vaultFingerprintNotPassphrase: String { get }

    // Emergency kit: must be saved before finishing
    var vaultKitShareOrSave: String { get }
    var vaultKitShared: String { get }
    var vaultKitCannotShowAgain: String { get }
    var vaultKitSaveFirst: String { get }
    func vaultKitWordPrompt(_ position: Int) -> String
    var vaultKitWholePrompt: String { get }
    var vaultKitWordWrong: String { get }

    // Reset a forgotten passphrase from a linked device
    var vaultPassphraseChoiceGenerated: String { get }
    var vaultPassphraseChoiceOwn: String { get }
    var vaultResetIntro: String { get }
    var vaultResetEffects: [String] { get }
    var vaultResetTwoFactorHint: String { get }
    var vaultResetConfirm: String { get }
    var vaultResetReason: String { get }
    var vaultResetNeedsPasscode: String { get }
    var vaultResetAuthFailed: String { get }
    var vaultResetDoneTitle: String { get }
    func vaultResetDoneBody(_ revokedDevices: Int) -> String
    var vaultResetFinish: String { get }

    var voiceRetryLookup: String { get }
    var voiceStorageUnavailable: String { get }
    var voiceRecord: String { get }
    var voiceStop: String { get }
    var voiceRecording: String { get }
    var voiceMicExplainerTitle: String { get }
    var voiceMicExplainerBody: String { get }
    var voiceMicExplainerContinue: String { get }
    var voiceMicDeniedTitle: String { get }
    var voiceMicDeniedBody: String { get }
    var voiceMicFailed: String { get }
    var voiceSaveFailed: String { get }
    var voiceStatusPendingUpload: String { get }
    var voiceStatusQueued: String { get }
    var voiceStatusTranscribing: String { get }
    var voiceStatusExtracting: String { get }
    var voiceStatusFailed: String { get }
    var voiceStatusInProgress: String { get }
    var voicePendingOffline: String { get }
    var voiceSendNow: String { get }
    var voiceRetry: String { get }
    var voiceOpen: String { get }
    var voiceRefresh: String { get }
    var voiceDismiss: String { get }
    var dictationStart: String { get }
    func journalCaptureTitle(_ time: String) -> String
    var photoStart: String { get }
    var photoTake: String { get }
    var photoChoose: String { get }
    var photoSaveFailed: String { get }
    var photoCameraDeniedTitle: String { get }
    var photoCameraDeniedBody: String { get }
    var photoDescriptionTitle: String { get }
    var dictationAnalyzing: String { get }
    var dictationSlow: String { get }
    var dictationSavedOffline: String { get }
    var dictationFailed: String { get }
    var dictationNothing: String { get }
    var dictationReview: String { get }
    func dictationAdded(_ count: Int) -> String
    func dictationSkipped(added: Int, names: String) -> String
    var voiceApiKeyRefused: String { get }
    var voiceExpiredKept: String { get }
    var voiceGoneKept: String { get }
    var voiceFailedKept: String { get }
    var voiceUnrecoverable: String { get }
    var voiceReviewTitle: String { get }
    var voiceTranscriptTitle: String { get }
    var voiceSkipItem: String { get }
    var voiceNoCandidates: String { get }
    var voiceAddToMeal: String { get }
    var voiceImporting: String { get }
    var voiceSkippedTitle: String { get }
    var voiceNothingImported: String { get }
    var voiceContinue: String { get }
    var voiceReasonNoCandidate: String { get }
    var voiceReasonUnknown: String { get }
    var voiceReasonNotBuildable: String { get }
    var voiceReasonLookupFailed: String { get }
    func voiceElapsed(_ seconds: Int, of limit: Int) -> String
    func voiceReadyItems(_ count: Int) -> String
    func voiceSkippedItem(_ text: String, reason: String) -> String
}

/// Resolves `AppStrings` to whatever `LanguageSettings` says is active right now. Re-resolved on
/// every read — like `LanguageSettings.shared.effective` itself, this is never cached, so a call
/// site's very next read reflects a switch made a moment ago.
enum Strings {
    @MainActor
    static var active: any AppStrings {
        LanguageSettings.shared.effective == "en" ? EnStrings() : FrStrings()
    }
}

// MARK: - Daily targets
//
// Client-authored (spec 05 §7): no deck entries exist yet, so both languages are written here, candidates for
// the deck's `app` scope. The tone is information, not judgement: no "bad day", no streaks, nothing red.

protocol TargetsStrings {
    var targetsPreviewToggle: String { get }
    var targetsPreviewBody: String { get }
    var targetsTitle: String { get }
    var targetsSetMine: String { get }
    var targetsSetMineBody: String { get }
    var targetsEditAnswers: String { get }
    var targetsScreenTitle: String { get }
    var targetsExplanationTitle: String { get }
    var targetsNeedConnection: String { get }
    var targetsNotMedicalAdvice: String { get }
    func targetsUnsupported(_ reason: UnsupportedTargetReason) -> String
    var targetsNoProfile: String { get }

    // Questionnaire
    var qSkip: String { get }
    var qNext: String { get }
    var qBack: String { get }
    var qSave: String { get }
    func qStep(_ index: Int, of total: Int) -> String
    var qBirthYear: String { get }
    var qBody: String { get }
    var qHeight: String { get }
    var qWeight: String { get }
    var qHeightNote: String { get }
    var qBasis: String { get }
    var qBasisNote: String { get }
    func basisName(_ basis: CalculationBasis) -> String
    var qPostmenopausal: String { get }
    var qYes: String { get }
    var qNo: String { get }
    var qSituation: String { get }
    var qSituationFemaleOnly: String { get }
    func situationName(_ situation: TargetSituation) -> String
    var qTrimester: String { get }
    func trimesterName(_ trimester: Int) -> String
    var qLactation: String { get }
    func lactationName(_ period: LactationPeriod) -> String
    var qActivity: String { get }
    func activityName(_ level: ActivityLevel) -> String
    func activityExample(_ level: ActivityLevel) -> String
    var qPreview: String { get }
    var qPreviewNeedsTable: String { get }

    // Targets screen
    var presetTitle: String { get }
    func presetName(_ preset: String) -> String
    var presetMedicalBanner: String { get }
    var presetMedicalAction: String { get }
    var watchShown: String { get }
    var watchHidden: String { get }
    var targetKindGoal: String { get }
    var targetKindRange: String { get }
    var targetKindLimit: String { get }
    var targetKindNone: String { get }
    var targetEdit: String { get }
    var targetReset: String { get }
    var targetResetAll: String { get }
    var targetOverridden: String { get }
    var targetMin: String { get }
    var targetMax: String { get }
    var targetCancel: String { get }
    var targetEditHint: String { get }

    // Rings, day, week, trends
    var ringLimit: String { get }
    func ringUsual(_ value: String) -> String
    func coverage(_ known: Int, of total: Int) -> String
    var dayDetailTitle: String { get }
    var groupMacros: String { get }
    var groupFats: String { get }
    var groupMinerals: String { get }
    var groupVitamins: String { get }
    func statusName(_ status: ProgressStatus) -> String
    func aboveUpperLimit(_ value: String) -> String
    var topContributors: String { get }
    var readWeekly: String { get }
    var unknownValue: String { get }
    var targetLabel: String { get }
    var weekTitle: String { get }
    func weekDaysWithData(_ count: Int) -> String
    var trendsTitle: String { get }
    func trendRange(_ days: Int) -> String
    var trendTarget: String { get }
    var trendTotal: String { get }
    func nutrientName(_ key: String) -> String
    var saltName: String { get }

    // Explanation
    func valueKindName(_ kind: String) -> String
    var explanationSources: String { get }
    var explanationInputs: String { get }
    func explanationAge(_ age: Int, band: String) -> String
    func explanationPal(_ pal: String) -> String
    func explanationWeight(_ kg: String) -> String
    func explanationBasis(_ basis: CalculationBasis) -> String
    func explanationSituation(_ text: String) -> String
    var explanationChoicesTitle: String { get }
    var explanationChoices: [String] { get }
    func explanationProfileUpdated(_ date: String) -> String
    var explanationOverriddenNote: String { get }
    func ageBandLabel(from: Int, to: Int?) -> String

    // Weight
    var weightTitle: String { get }
    var weightLog: String { get }
    var weightKg: String { get }
    var weightDate: String { get }
    var weightSave: String { get }
    var weightEntries: String { get }
    var weightNone: String { get }
    var weightTrend: String { get }
    var weightMean: String { get }
}

/// The four activity levels of the questionnaire, with EFSA's PAL values (spec 05 §4, an allowed constant).
enum ActivityLevel: CaseIterable {
    case sedentary, moderate, active, veryActive

    var pal: Double {
        switch self {
        case .sedentary: 1.4
        case .moderate: 1.6
        case .active: 1.8
        case .veryActive: 2.0
        }
    }
}
