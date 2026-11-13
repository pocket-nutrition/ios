// SPDX-License-Identifier: MPL-2.0

import PocketNutritionCore

/// English copy, added in contract 2.0.0. See `AppStrings` for where every entry comes from — the
/// contract-sourced ones are hand-translated against the French value and its `context` note, not
/// machine-translated.
struct EnStrings: AppStrings {

    let brand = "Pocket Nutrition"

    let journalTitle = "My journal"
    let journalEmpty = "No meals logged yet"
    let journalAdd = "Add a meal"
    let journalDelete = "Delete"
    let journalPrivacy = "Your meals are stored on this device. With a vault account, an encrypted copy is kept there too."

    let aboutTitle = "About"
    func aboutVersion(_ version: String) -> String { "Version \(version)" }
    let aboutPrivacyTitle = "Privacy"
    let aboutPrivacySummary =
        "Your journal is stored on this device. A cloud vault account is optional (a username, no email): "
        + "it keeps an encrypted copy of your journal and is needed for voice capture. No ads, no trackers."
    let aboutPrivacyNetwork =
        "A search sends the text you typed. An analysis sends the foods, quantities and cooking "
        + "methods. No identifier accompanies these requests. A voice recording is sent for analysis and "
        + "kept only until it is processed, at most 48 hours; the result is delivered to your own vault, "
        + "encrypted so that only your devices can read it. The same goes for the encrypted copy of your journal, which the server cannot read. "
        + "Your passphrase never leaves this phone."
    let aboutPrivacyLink = "Read the privacy policy"
    let aboutSourcesTitle = "Data sources"
    let aboutSourcesBody =
        "Nutritional values: Ciqual 2025 (ANSES, Licence Ouverte), McCance & Widdowson's CoFID 2021 "
        + "(contains public sector information licensed under the Open Government Licence v3.0), "
        + "USDA FoodData Central and USDA cooking yields tables (public domain). "
        + "Products, brands and photos: Open Food Facts, under the ODbL licence."
    let aboutLicenceTitle = "Licence"
    let aboutLicenceBody =
        "This app is free software, released under the Mozilla Public License 2.0. "
        + "You may view, modify and redistribute its source code."
    let aboutSourceLink = "View the source code"
    let aboutThirdPartyTitle = "Third-party components"
    let aboutThirdPartyNone = "No external dependencies."
    let aboutClose = "Close"

    let settingsTitle = "Settings"

    let aboutLanguageTitle = "Language"
    let aboutLanguageAuto = "Automatic"
    let aboutLanguageFr = "Français"
    let aboutLanguageEn = "English"

    let aboutServerTitle = "Server"
    let aboutServerBody = "Server address the app uses. Leave empty for the official server."
    let aboutServerApply = "Use this address"
    let aboutServerReset = "Back to official server"
    let aboutServerInvalid =
        "Invalid address. Use a full URL, for example https://example.org"

    let searchPlaceholder = "Search for a food…"
    let searchNoResults = "No results"
    let multiTermHint = "Several foods at once: “rice chicken apple”"
    func confirmAdd(count: Int) -> String { "Add (\(count))" }
    let searchAlreadyAdded = "Already added"
    let searchProductBadge = "Product"
    let searchRecipePrefix = "Recipe: %@"
    let searchRecipeComponentCount = "%d ingredients"
    let searchSectionRecipes = "Recipes"
    let searchSectionIngredients = "Ingredients"
    let searchSectionProducts = "Branded products"
    let searchCancel = "Cancel"

    let mealHeading = "Build your meal"
    func mealSlotName(_ slot: MealSlot) -> String {
        switch slot {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        }
    }
    let mealChangeTime = "Change time…"
    let mealTimeTitle = "Meal time"
    func journalSameAsYesterday(_ items: String) -> String { "Same as yesterday: \(items)" }
    let dishesTitle = "My dishes"
    func recentsTitle(_ slot: MealSlot) -> String {
        switch slot {
        case .breakfast: "Often at breakfast"
        case .lunch: "Often at lunch"
        case .dinner: "Often at dinner"
        case .snack: "Often as a snack"
        }
    }
    func dishDetail(ingredients: Int, servings: Int) -> String {
        "\(ingredients) ingredient\(ingredients == 1 ? "" : "s")" + (servings > 1 ? " · makes \(servings)" : "")
    }
    func recentDetail(grams: Double, method: String) -> String { "\(roundHalfUp(grams)) g" + (method.isEmpty || method == "raw" ? "" : " · \(cookingMethod(method).lowercased())") }
    let saveAsDish = "Save as dish"
    let dishNameField = "Dish name"
    func dishServings(_ count: Int) -> String { "Makes \(count) portion\(count == 1 ? "" : "s")" }
    let dishSave = "Save"
    func dishUpdate(_ name: String) -> String { "Update “\(name)”" }
    let dishMenuA11y = "Dish options"
    func dishPartsUnit(servings: Int, parts: Double) -> String { servings > 1 ? "of \(servings) portions" : "×" }
    let pin = "Pin"
    let unpin = "Unpin"
    let deleteDish = "Delete dish"
    func quickAddRow(_ kcal: Int) -> String { "Add \(kcal) kcal" }
    let quickAddNote = "Entered manually"
    func shortcutAddA11y(_ name: String) -> String { "Add \(name)" }
    let logAgainNow = "Log again now"
    func journalRepeatYesterdayA11y(_ slot: String) -> String { "Repeat yesterday's \(slot.lowercased())" }
    let mealEmpty = "Search for a food above to get started"
    let mealAnalysing = "Analyzing…"
    func mealAnalyse(count: Int) -> String {
        "Analyze the meal (\(count) item\(count != 1 ? "s" : ""))"
    }
    let mealRemove = "Remove"
    let collapse = "Collapse"
    let done = "Done"
    let mealQuantity = "Quantity"
    let mealCooking = "Cooking"

    func cookingMethod(_ id: String) -> String {
        switch id {
        case "raw": return "Raw"
        case "boiled": return "Boiled"
        case "steamed": return "Steamed"
        case "grilled": return "Grilled"
        case "roasted": return "Roasted"
        case "fried": return "Fried"
        default: return "cooked (generic)"
        }
    }

    let nutrientEnergy = "Energy"
    let nutrientProtein = "Protein"
    let nutrientCarbs = "Carbs"
    let nutrientFat = "Fat"
    let nutrientProteinAbbr = "P"
    let nutrientCarbsAbbr = "C"
    let nutrientFatAbbr = "F"

    let resultsTotal = "Meal total"
    let resultsEdit = "Edit the meal"
    let resultsSave = "Save this meal"
    let resultsUnavailable = "Data unavailable for this food."
    let resultsTotalUnknown = "— kcal"
    func resultsRowSummary(quantity: Double, unit: String, method: String, state: String) -> String {
        "\(formatNumber(quantity, lang: "en")) \(unit) · \(method) · weighed \(state)"
    }

    func measuredState(_ id: String) -> String {
        switch id {
        case "raw": return "raw"
        case "cooked": return "cooked"
        default: return id
        }
    }
    let measuredBeforeLong = "Before cooking"
    let measuredAfterLong = "After cooking"
    let weighedLabel = "Weighed:"
    let weighedGroupAria = "Weighed before or after cooking"
    func weighedInline(_ when: String) -> String { "(weighed \(when) cooking)" }
    func measuredWhen(_ state: String) -> String { state == "cooked" ? "after" : "before" }
    let changeCooking = "Change cooking method and weighed state"
    let ingredientReport = "Report"
    let ingredientReportAria = "Report an inaccuracy"

    let feedbackTitle = "Report an inaccuracy"
    let feedbackIntro = "Choose a category, then the specific error."
    let feedbackReferenceWeight = "Reference weight"
    let feedbackDisplayUnit = "Display unit"
    let feedbackUnits = "Units"
    let feedbackComment = "Comment (optional)"
    let feedbackAdd = "Add"
    let feedbackRemoveCorrection = "Remove this correction"
    let feedbackSubmit = "Submit the report"
    let feedbackSubmitting = "Sending…"
    let feedbackSuccess = "Thanks, your report has been sent to the team."
    let feedbackFailure = "Could not send right now. Try again later."
    let feedbackClose = "Close"
    let feedbackUnitAria = "unit"

    // Feedback form: current data and per-field help (client-authored)
    let feedbackPendingTitle = "Corrections to send"
    let feedbackCurrentDataTitle = "Current data"
    let feedbackCurrentDataLoading = "Loading the full data…"
    let feedbackCorrectValue = "Correct value"
    func feedbackCurrent(_ value: String) -> String { "current: \(value)" }
    func feedbackHelp(_ code: String) -> String? {
        switch code {
        case "energy", "protein", "fat", "carbs", "fiber": "Value per 100 g of the raw food."
        case "other_nutrient": "Name the nutrient and its value per 100 g."
        case "name_fr", "name_en": "The name this food should be shown and found under."
        case "food_group": "The family this food belongs to."
        case "aliases": "Other names people search this food by."
        case "wrong_ingredient": "The search matched another food than the one you meant."
        case "reference_weight": "Weight of one typical portion or piece."
        case "serving_unit": "A unit you would like to count this food in."
        case "display_unit": "The unit quantities are shown in."
        case "serving_mode": "Whether this food is counted by piece, by weight or by volume."
        case "density": "Grams per millilitre, to convert a volume to a weight."
        case "yield": "Cooked weight as a percentage of the raw weight: 100 g raw that weighs 75 g cooked is 75 %."
        case "cooking_method": "A way of cooking this food that the app does not offer."
        case "raw_cooked": "How this food is eaten: raw, cooked, or both. Choose the right answer if the current one is wrong."
        case "free": "Anything else, or information we do not have yet."
        default: nil
        }
    }
    let feedbackTechIngredient = "Ingredient"
    let feedbackTechCooking = "Cooking chosen"
    let feedbackTechMeasured = "Weight entered"
    let feedbackTechEatability = "Eaten"
    let feedbackTechYields = "Yield after cooking"
    let feedbackTechYieldNone = "none recorded (weight unchanged)"
    let feedbackTechReferenceWeight = "Reference weight"
    let feedbackTechUnits = "Units"
    let feedbackTechFoodGroup = "Food group"
    let feedbackTechPer100 = "Per 100 g (raw)"
    func feedbackEatability(raw: Bool?, cooked: Bool?) -> String? {
        switch (raw, cooked) {
        case (true, true): "raw or cooked"
        case (true, _): "raw"
        case (false, _), (_, true): "cooked only"
        default: nil
        }
    }
    func feedbackMeasuredState(_ state: String) -> String { state == "cooked" ? "cooked weight" : "raw weight" }

    let scanBarcodeButton = "Scan a barcode"
    let scanExplainerTitle = "Scan a product"
    let scanExplainerBody =
        "Pocket Nutrition needs camera access to scan a product's barcode and look up its "
        + "nutritional values. No photo is saved."
    let scanExplainerContinue = "Continue"
    let scanExplainerNotNow = "Not now"
    let scanSettingsTitle = "Allow camera access"
    let scanSettingsBody =
        "Camera access was denied. Open Settings to allow it."
    let scanSettingsOpenSettings = "Open Settings"
    let scanLookingUp = "Looking up product…"
    let scanNotFoundTitle = "Product not found"
    let scanNotFound = "This barcode is not in our database yet. Search for its ingredients by name; you can then save the meal as a dish to reuse it."
    let scanReport = "Report this product"
    let scanReportSent = "Thanks, reported"
    let scanErrorTitle = "Scan failed"
    let scanUnavailableTitle = "Scan unavailable"
    let scanUnavailable = "Barcode scanning is not available on this device."

    func yieldHint(display: String, heavier: Bool) -> String {
        "This food weighs \(display)x \(heavier ? "heavier" : "lighter") once cooked"
    }

    func error(_ message: String) -> String { "Error: \(message)" }
    let retry = "Retry"

    // MARK: - Voice capture (client-authored; the recognition endpoint is not in contracts 2.0.0)

    let recognitionSettingsTitle = "Voice recognition server"
    let recognitionSettingsBody = "Voice capture sends the recording of your voice to the server set here, to turn it into a list of foods. The recording stays on the phone until the result has been received (7 days at most), then it is deleted. Only use a server you trust."
    let recognitionServerLabel = "Server address"
    let recognitionKeyLabel = "API key"
    let recognitionKeySavedPlaceholder = "Key saved — leave empty to keep it"
    let recognitionSave = "Save"
    let recognitionClear = "Remove"
    let recognitionInvalidURL = "Invalid address. Use a full https:// URL, for example https://example.org"
    let recognitionMissingKey = "Enter the server's API key."
    let recognitionSaveFailed = "Could not store the key in the device Keychain."
    let recognitionSaved = "Saved."
    let recognitionKeyRequiredForNewHost = "The server changed: enter the API key again for this server."
    let recognitionClearFailed = "Could not remove the key from the device Keychain."


    // MARK: - Cloud vault (client-authored)

    let vaultTitle = "Cloud vault"
    let vaultIntro = "Keep your data in the cloud and across your devices. It is encrypted before it leaves your phone: the server can never read it."
    let vaultServerLabel = "Server address"
    let vaultCheckServer = "Check server"
    let vaultRegistrationClosed = "This server is not accepting new accounts. You can only log in to it."
    let vaultUsernameLabel = "Username"
    let vaultPassphraseLabel = "Passphrase"
    let vaultPassphraseConfirmLabel = "Confirm passphrase"
    let vaultPassphraseHint = "At least 12 characters. It never leaves your phone and nobody can recover it for you."
    let vaultCreateAccount = "Create account"
    let vaultLogin = "Log in"
    let vaultRecoveryTitle = "Your emergency kit"
    let vaultRecoveryBody = "This is how you get back into your vault on a new phone or if you forget your passphrase. We cannot recover any of it. Send it to yourself or save it in your password manager, not only on this phone."
    let vaultRecoveryCopy = "Copy kit"
    let vaultRecoveryCopied = "Kit copied"
    let vaultRecoveryContinue = "Finish creating the account"
    let vaultLogout = "Log out of this device"
    let vaultLogoutUnreached = "This device is logged out, but the server could not be told. Revoke it from another logged-in device."
    let vaultDeleteAccount = "Delete my account and data"
    let vaultDeleteBody = "Permanently erases the account and everything stored on the server. Enter your passphrase to confirm."
    let vaultDeleteConfirm = "Delete permanently"
    let vaultCancel = "Cancel"
    let vaultErrInvalidServer = "Invalid address. Use a full https:// URL, for example https://example.org"
    let vaultErrNotAVault = "This address does not answer like a vault server."
    let vaultErrOffline = "Could not reach the server. Check your connection and try again."
    let vaultErrInvalidUsername = "Invalid username: 3 to 64 characters from a-z, 0-9, \"_\", \".\" and \"-\"."
    let vaultErrPassphraseShort = "The passphrase must be at least 12 characters."
    let vaultErrPassphraseMismatch = "The two passphrases do not match."
    let vaultErrUsernameTaken = "That username is already taken."
    let vaultErrRegistrationClosed = "This server is not accepting new accounts."
    let vaultErrInvalidCredentials = "Wrong username or passphrase."
    let vaultErrUnsafeKdf = "The server asked for security settings that are too weak. Login refused as a precaution."
    let vaultErrKeyring = "The server answered, but your keys could not be opened by this version of the app."
    let vaultErrServer = "The server had a problem. Try again later."
    let vaultErrKeychain = "Could not save the session in the device Keychain."
    let vaultErrCrypto = "Key derivation failed on this device."
    func vaultServerFound(_ name: String) -> String { "Server found: \(name)" }
    func vaultSignedInAs(_ username: String, host: String) -> String { "Logged in as \(username) on \(host)" }
    func vaultErrTooManyAttempts(_ seconds: Int?) -> String { seconds.map { "Too many attempts. Try again in \(max(1, ($0 + 59) / 60)) min." } ?? "Too many attempts. Try again later." }
    let vaultHeroTitle = "Your private vault"
    let vaultBenefitSync = "Your whole journal is saved there and stays in step on all your devices."
    func vaultTransferHint(_ meals: Int) -> String { "Your \(meals) meal\(meals == 1 ? "" : "s") will be saved to the vault right away." }
    let vaultSyncing = "Syncing your journal…"
    func vaultSynced(_ meals: Int) -> String { "Journal synced: \(meals) meal\(meals == 1 ? "" : "s")" }
    let vaultSyncOffline = "Offline. Your meals will sync as soon as the vault can be reached."
    let vaultSyncFull = "Your vault is full. Free some space to keep syncing."
    let vaultSyncFailed = "The sync ran into a problem. It will try again."
    let vaultSyncNow = "Sync now"
    let vaultBenefitVoice = "Dictate your meals out loud instead of typing them."
    let vaultBenefitPrivate = "Your data is encrypted before it leaves your phone and stays encrypted in the cloud. Nobody else can read it, not even us."
    func vaultOfficialServer(_ host: String) -> String { "Official vault: \(host)" }
    let vaultAdvanced = "Advanced"
    let vaultAdvancedHint = "Most people never need this. Use your own vault server instead of the official one."
    let vaultCreateVault = "Create my vault"
    let vaultGeneratedHint = "We generate a strong passphrase for you. You will keep it in an emergency kit on the next screen."
    let vaultOwnPassphrase = "Choose my own passphrase"
    let vaultGeneratePassphrase = "Generate one for me instead"
    let vaultRecoveryKeyLabel = "Recovery key"
    let vaultKitShare = "Send to myself"
    func vaultKitText(host: String, username: String, passphrase: String?, recoveryKey: String) -> String {
        var lines = ["Pocket Nutrition vault: emergency kit", "Server: \(host)", "Username: \(username)"]
        if let passphrase { lines.append("Passphrase: \(passphrase)") }
        lines.append("Recovery key: \(recoveryKey)")
        lines.append("")
        lines.append("Keep this somewhere safe and private. Nobody, including us, can recover it for you.")
        return lines.joined(separator: "\n")
    }
    let vaultConnecting = "Connecting to the vault…"
    let vaultRetry = "Try again"
    let journalVaultCardTitle = "Activate your vault"
    let journalVaultCardBody = "Save your journal in an encrypted vault that only you can open, and dictate your meals."
    let journalVaultCardAction = "Activate"
    let journalVaultCardLater = "Not now"

    // Vault account security
    let vaultLockReason = "Unlock your vault settings"
    let vaultLockEnableReason = "Confirm it is you to turn on the vault lock"
    let vaultLockPasscode = "the device passcode"
    let vaultLockedTitle = "Vault locked"
    let vaultLockedBody = "Your journal keeps syncing. Unlock to manage your account."
    let vaultUnlock = "Unlock"
    let vaultSessionTitle = "Session expiration"
    func vaultLockToggle(_ biometry: String) -> String { "Lock with \(biometry)" }
    let vaultTimeoutLabel = "Expire after"
    func vaultTimeoutOption(_ timeout: VaultSessionTimeout) -> String {
        switch timeout {
        case .immediately: "Immediately"
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        case .fourHours: "4 hours"
        case .onRestart: "When the app restarts"
        case .never: "Never"
        }
    }
    let vaultTimeoutActionLabel = "When it expires"
    func vaultTimeoutAction(_ action: VaultTimeoutAction) -> String {
        switch action {
        case .lock: "Lock"
        case .logOut: "Log out"
        }
    }
    let vaultSessionHint = "Time spent with the app in the background. Logging out keeps your meals on this phone; you log in again with your passphrase. Turn on the lock to be able to lock instead."
    let vaultSessionHintLock = "Time spent with the app in the background. Locking only hides these settings: your journal keeps syncing."
    let vaultDevicesTitle = "Manage devices"
    let vaultDevices = "Devices"
    let vaultDevicesHint = "Every device logged in to your vault. Revoke one you lost or no longer use: it stops syncing at once."
    let vaultDevicesEmpty = "No device found."
    let vaultDeviceUnnamed = "Unnamed device"
    func vaultDeviceLinked(_ date: String) -> String { "Logged in \(date)" }
    let vaultThisDevice = "This device"
    let vaultRevoke = "Revoke"
    func vaultRevokeTitle(_ label: String) -> String { "Revoke \(label)?" }
    let vaultRevokeBody = "That device is logged out of the vault. What it already downloaded stays on it."
    let vaultOtherOptions = "Other options"
    let vaultFingerprintTitle = "Fingerprint phrase"
    let vaultFingerprintExplanation = "This phrase names your account's keys. It is the same on all your devices; if another device shows different words, it was not given your real keys."
    let vaultChangePassphraseTitle = "Change passphrase"
    let vaultNewPassphrase = "New passphrase"
    let vaultTwoFactorTitle = "Two-factor authentication"
    let vaultTwoFactorOff = "Two-factor is off"
    let vaultTwoFactorIntro = "Logging in on a new device will also ask for a code from an authenticator app (Passwords, 1Password, Google Authenticator…). Devices already logged in are not affected. Enter your passphrase to start."
    let vaultTwoFactorStart = "Set up two-factor"
    let vaultTwoFactorSetupTitle = "Add the vault to your authenticator"
    let vaultTwoFactorSetupBody = "Add this account to your authenticator app, then type the 6-digit code it shows."
    let vaultTwoFactorOpenApp = "Open in my authenticator app"
    let vaultTwoFactorQR = "QR code to scan with an authenticator on another device"
    let vaultTwoFactorManual = "Or type this key into the app:"
    let vaultTwoFactorCodeLabel = "6-digit code"
    let vaultTwoFactorConfirm = "Turn on two-factor"
    let vaultTwoFactorOn = "Two-factor is on"
    func vaultTwoFactorOnBody(_ recoveryCodesLeft: Int) -> String { "A code is asked for when logging in on a new device. \(recoveryCodesLeft) recovery code\(recoveryCodesLeft == 1 ? "" : "s") left. To turn it off, enter your passphrase and a code." }
    let vaultTwoFactorCodeOrRecovery = "Code or recovery code"
    let vaultTwoFactorDisable = "Turn off two-factor"
    let vaultTwoFactorLoginHint = "This account uses two-factor. Enter the code from your authenticator app, or a recovery code."
    let vaultRecoveryCodesTitle = "Your recovery codes"
    let vaultRecoveryCodesBody = "Each code logs you in once if you lose your authenticator. They are shown only now: save them with your emergency kit."
    let vaultRecoveryCodesDone = "I have saved them"
    func vaultRecoveryCodesText(_ codes: [String]) -> String {
        (["Pocket Nutrition vault: two-factor recovery codes"] + codes + ["", "Each code works once."]).joined(separator: "\n")
    }
    let vaultCopy = "Copy"
    let vaultCopied = "Copied"
    let vaultErrInvalidTwoFactor = "Wrong or already used code."
    let vaultErrKeyringConflict = "Your keys were changed from another device. Reopen this screen and try again."
    let vaultErrNoPassphrase = "This account has no passphrase to change."
    let vaultErrTwoFactorChanged = "Two-factor was changed from another device. Reopen this screen."
    let vaultErrDeviceRevoked = "This device is no longer logged in to the vault. Log out and log in again."
    let vaultErrTwoFactorRequired = "Two-factor login is on: enter a code from your authenticator app or a recovery code."

    let vaultFingerprintNotPassphrase = "This is not your passphrase: it only checks that another device has the same keys."

    let vaultKitShareOrSave = "Share or save…"
    let vaultKitShared = "Kit shared"
    let vaultKitCannotShowAgain = "Your passphrase cannot be shown again. Without it or the recovery key, a new device cannot be linked."
    let vaultKitSaveFirst = "Copy the kit or share it somewhere safe first."
    func vaultKitWordPrompt(_ position: Int) -> String { "Type word \(position) of your passphrase" }
    let vaultKitWholePrompt = "Type your passphrase"
    let vaultKitWordWrong = "That does not match. Check your saved kit."

    let vaultPassphraseChoiceGenerated = "Generate a passphrase (recommended)"
    let vaultPassphraseChoiceOwn = "Choose my own"
    let vaultResetIntro = "You do not need your current passphrase: this phone is linked and holds your keys, so it can set a new one even if you forgot it. Here is what will happen:"
    let vaultResetEffects = [
        "A new recovery key is created and shown once, with your new passphrase, in a new emergency kit.",
        "Your other linked devices and the web viewer are logged out. They must log in again with the new passphrase.",
        "Your old recovery key stops working.",
        "This phone stays linked and your journal is kept as it is.",
    ]
    let vaultResetTwoFactorHint = "Two-factor login is on: enter a code from your authenticator app or a recovery code."
    let vaultResetConfirm = "Change passphrase"
    let vaultResetReason = "Confirm it is you to change your vault passphrase"
    let vaultResetNeedsPasscode = "Set a passcode on this device first: it is what protects this step."
    let vaultResetAuthFailed = "The device could not confirm it is you. Nothing was changed."
    let vaultResetDoneTitle = "Your new emergency kit"
    func vaultResetDoneBody(_ revokedDevices: Int) -> String {
        let devices = revokedDevices == 0 ? "No other device was logged in." : "\(revokedDevices) other device\(revokedDevices == 1 ? " was" : "s were") logged out."
        return "Your passphrase was replaced. \(devices) Save this kit before you leave this screen."
    }
    let vaultResetFinish = "Done, my kit is saved"

    let voiceRetryLookup = "Retry lookup"
    let voiceStorageUnavailable = "Storage unavailable — your recordings are kept on the phone. Try again."
    let voiceRecord = "Record a meal"
    let voiceStop = "Stop and send"
    let voiceRecording = "Recording…"
    let voiceMicExplainerTitle = "Microphone access"
    let voiceMicExplainerBody = "Pocket Nutrition records a few seconds of your voice to describe a meal. The recording is sent to your voice recognition server and stays on the phone until the result has been received (7 days at most), then it is deleted."
    let voiceMicExplainerContinue = "Continue"
    let voiceMicDeniedTitle = "Microphone is off"
    let voiceMicDeniedBody = "Microphone access is denied. Allow it in the iPhone Settings to record a meal."
    let voiceMicFailed = "Could not start recording."
    let voiceSaveFailed = "Could not save the recording on the phone."
    let voiceStatusPendingUpload = "Waiting to send"
    let voiceStatusQueued = "Will be processed soon"
    let voiceStatusTranscribing = "Transcribing…"
    let voiceStatusExtracting = "Finding foods…"
    let voiceStatusFailed = "Failed"
    let voiceStatusInProgress = "In progress…"
    let voicePendingOffline = "Waiting to send — offline"
    let voiceSendNow = "Send now"
    let voiceRetry = "Send again"
    let voiceOpen = "Open"
    let voiceRefresh = "Refresh"
    let voiceDismiss = "Dismiss"
    let dictationStart = "Dictate a meal"
    func journalCaptureTitle(_ time: String) -> String { "Meal in progress · \(time)" }
    let photoStart = "Photograph a meal"
    let photoTake = "Take a photo"
    let photoChoose = "Choose from library"
    let photoSaveFailed = "The photo could not be saved."
    let photoCameraDeniedTitle = "Camera access is off"
    let photoCameraDeniedBody = "Allow camera access for Pocket Nutrition in Settings to photograph a meal. You can still choose a photo from your library."
    let photoDescriptionTitle = "What was seen"
    let dictationAnalyzing = "Analysing your meal…"
    let dictationSlow = "This is taking a while. You can keep going or leave: the result will wait for you in your journal."
    let dictationSavedOffline = "Saved. It will be sent as soon as you are back online."
    let dictationFailed = "Your meal could not be analysed."
    let dictationNothing = "Nothing could be added."
    let dictationReview = "Review"
    func dictationAdded(_ count: Int) -> String { "Added \(count) ingredient\(count == 1 ? "" : "s")." }
    func dictationSkipped(added: Int, names: String) -> String { "Added \(added). Could not add: \(names)." }
    let voiceApiKeyRefused = "API key refused"
    let voiceExpiredKept = "Expired — the recording is still on your phone"
    let voiceGoneKept = "Result not found on the server — the recording is still on your phone"
    let voiceFailedKept = "Processing failed — the recording is still on your phone"
    let voiceUnrecoverable = "The recording is no longer available, so it cannot be sent again."
    let voiceReviewTitle = "Review"
    let voiceTranscriptTitle = "What was heard"
    let voiceSkipItem = "Skip this item"
    let voiceNoCandidates = "No food suggested"
    let voiceAddToMeal = "Add to meal"
    let voiceImporting = "Looking up foods…"
    let voiceSkippedTitle = "Skipped items"
    let voiceNothingImported = "Nothing could be added."
    let voiceContinue = "Continue"
    let voiceReasonNoCandidate = "no food suggested"
    let voiceReasonUnknown = "food not found in the catalogue"
    let voiceReasonNotBuildable = "not enough data (weight or cooking method unknown)"
    let voiceReasonLookupFailed = "lookup failed (network)"
    func voiceElapsed(_ seconds: Int, of limit: Int) -> String { "\(seconds) s / \(limit) s" }
    func voiceReadyItems(_ count: Int) -> String { "Ready — \(count) item\(count == 1 ? "" : "s")" }
    func voiceSkippedItem(_ text: String, reason: String) -> String { "“\(text)”: \(reason)" }
}

// MARK: - Daily targets (client-authored, see `TargetsStrings`)

extension EnStrings {
    var targetsPreviewToggle: String { "Daily targets (preview)" }
    var targetsPreviewBody: String {
        "Daily targets calculated from EFSA's reference values, on this phone. "
            + "Your profile and weight are never sent to the server."
    }
    var targetsTitle: String { "Daily targets" }
    var targetsSetMine: String { "Set my targets" }
    var targetsSetMineBody: String { "Optional: a few questions give targets from EFSA's reference values." }
    var targetsEditAnswers: String { "Edit my answers" }
    var targetsScreenTitle: String { "Nutrients and targets" }
    var targetsExplanationTitle: String { "How is this calculated" }
    var targetsNeedConnection: String { "Targets need a connection the first time." }
    var targetsNotMedicalAdvice: String { "Information, not medical advice." }
    func targetsUnsupported(_ reason: UnsupportedTargetReason) -> String {
        switch reason {
        case .infant: "A child under one year old needs a health professional's advice."
        case .pregnancyUnder18, .lactationUnder18:
            "EFSA's values for pregnancy and breastfeeding are for adults. "
                + "Ask a health professional for your targets; you can enter them yourself."
        }
    }
    var targetsNoProfile: String { "No profile: every target comes from a value you entered." }

    var qSkip: String { "Skip, I'll enter my own values" }
    var qNext: String { "Next" }
    var qBack: String { "Back" }
    var qSave: String { "Save" }
    func qStep(_ index: Int, of total: Int) -> String { "Step \(index) of \(total)" }
    var qBirthYear: String { "Birth year" }
    var qBody: String { "Height and weight" }
    var qHeight: String { "Height (cm)" }
    var qWeight: String { "Weight (kg)" }
    var qHeightNote: String { "Height is kept for later: EFSA's values use only weight." }
    var qBasis: String { "Calculation basis" }
    var qBasisNote: String {
        "EFSA publishes different values for women and men. We never ask for your gender: "
            + "choose the values to calculate with."
    }
    func basisName(_ basis: CalculationBasis) -> String {
        switch basis {
        case .female: "Female reference values"
        case .male: "Male reference values"
        case .average: "An average of both"
        }
    }
    var qPostmenopausal: String { "Postmenopausal?" }
    var qYes: String { "Yes" }
    var qNo: String { "No" }
    var qSituation: String { "Situation" }
    var qSituationFemaleOnly: String { "Offered with the female reference values." }
    func situationName(_ situation: TargetSituation) -> String {
        switch situation {
        case .none: "None of these"
        case .pregnant: "Pregnant"
        case .lactating: "Breastfeeding"
        }
    }
    var qTrimester: String { "Trimester" }
    func trimesterName(_ trimester: Int) -> String {
        switch trimester {
        case 1: "1st trimester"
        case 2: "2nd trimester"
        default: "3rd trimester"
        }
    }
    var qLactation: String { "Since the birth" }
    func lactationName(_ period: LactationPeriod) -> String {
        switch period {
        case .firstSixMonths: "0 to 6 months"
        case .afterSixMonths: "More than 6 months"
        }
    }
    var qActivity: String { "Activity level" }
    func activityName(_ level: ActivityLevel) -> String {
        switch level {
        case .sedentary: "Sedentary"
        case .moderate: "Moderately active"
        case .active: "Active"
        case .veryActive: "Very active"
        }
    }
    func activityExample(_ level: ActivityLevel) -> String {
        switch level {
        case .sedentary: "Desk job, little walking"
        case .moderate: "On your feet part of the day, or 3 sessions a week"
        case .active: "Physical job, or daily exercise"
        case .veryActive: "Hard physical job or intense daily training"
        }
    }
    var qPreview: String { "Your targets" }
    var qPreviewNeedsTable: String { "The preview needs a connection. Your answers are saved anyway." }

    var presetTitle: String { "Preset" }
    func presetName(_ preset: String) -> String {
        switch preset {
        case "standard": "Standard"
        case "sport": "Sport"
        case "kidney": "Kidney"
        case "hypertension": "Hypertension"
        case "diabetes": "Diabetes"
        case "everything": "Everything"
        default: "Custom"
        }
    }
    var presetMedicalBanner: String {
        "These are general-population values. Enter the targets your doctor or dietitian gave you."
    }
    var presetMedicalAction: String { "Enter my values" }
    var watchShown: String { "Watched" }
    var watchHidden: String { "Not watched" }
    var targetKindGoal: String { "goal" }
    var targetKindRange: String { "range" }
    var targetKindLimit: String { "limit" }
    var targetKindNone: String { "no target" }
    var targetEdit: String { "Edit" }
    var targetReset: String { "Reset to EFSA" }
    var targetResetAll: String { "Reset all to EFSA" }
    var targetOverridden: String { "set by you" }
    var targetMin: String { "Minimum" }
    var targetMax: String { "Maximum" }
    var targetCancel: String { "Cancel" }
    var targetEditHint: String { "Leave a field empty for a minimum only or a maximum only." }

    var ringLimit: String { "limit" }
    func ringUsual(_ value: String) -> String { "usual \(value)" }
    func coverage(_ known: Int, of total: Int) -> String { "based on \(known) of \(total) meals" }
    var dayDetailTitle: String { "Day detail" }
    var groupMacros: String { "Energy & macros" }
    var groupFats: String { "Fats" }
    var groupMinerals: String { "Minerals" }
    var groupVitamins: String { "Vitamins" }
    func statusName(_ status: ProgressStatus) -> String {
        switch status {
        case .noTarget: "no target"
        case .under: "below target"
        case .ok: "within target"
        case .over: "above target"
        }
    }
    func aboveUpperLimit(_ value: String) -> String { "above EFSA's safe upper level (\(value))" }
    var topContributors: String { "Main contributors" }
    var readWeekly: String { "Reads better over a week: see the week" }
    var unknownValue: String { "unknown" }
    var targetLabel: String { "Target" }
    var weekTitle: String { "This week" }
    func weekDaysWithData(_ count: Int) -> String { count == 1 ? "1 day with data" : "\(count) days with data" }
    var trendsTitle: String { "Trends" }
    func trendRange(_ days: Int) -> String { "\(days) d" }
    var trendTarget: String { "Target" }
    var trendTotal: String { "Total" }
    func nutrientName(_ key: String) -> String {
        switch key {
        case "energyKcal": "Energy"
        case "proteinG": "Protein"
        case "fatG": "Fat"
        case "carbohydratesG": "Carbs"
        case "fiberG": "Fiber"
        case "waterG": "Water"
        case "sugarsG": "Sugars"
        case "calciumMg": "Calcium"
        case "ironMg": "Iron"
        case "magnesiumMg": "Magnesium"
        case "sodiumMg": "Sodium"
        case "vitaminCMg": "Vitamin C"
        case "saturatedFatG": "Saturated fat"
        case "monounsaturatedFatG": "Monounsaturated fat"
        case "polyunsaturatedFatG": "Polyunsaturated fat"
        case "cholesterolMg": "Cholesterol"
        case "potassiumMg": "Potassium"
        case "phosphorusMg": "Phosphorus"
        case "zincMg": "Zinc"
        case "vitaminAUg": "Vitamin A"
        case "vitaminDUg": "Vitamin D"
        case "vitaminB6Mg": "Vitamin B6"
        case "vitaminB12Ug": "Vitamin B12"
        case "niacinMg": "Niacin (B3)"
        default: key
        }
    }
    var saltName: String { "Salt" }

    func valueKindName(_ kind: String) -> String {
        switch kind {
        case "pri": "PRI, population reference intake"
        case "ai": "AI, adequate intake"
        case "ri": "RI, reference intake range"
        case "ul": "UL, tolerable upper intake level"
        case "ar_kcal", "ar": "AR, average requirement"
        default: kind
        }
    }
    var explanationSources: String { "Sources" }
    var explanationInputs: String { "Calculated with" }
    func explanationAge(_ age: Int, band: String) -> String { "Age \(age) (band \(band))" }
    func explanationPal(_ pal: String) -> String { "Physical activity level (PAL) \(pal)" }
    func explanationWeight(_ kg: String) -> String { "Weight \(kg) kg" }
    func explanationBasis(_ basis: CalculationBasis) -> String { "Basis: \(basisName(basis).lowercased())" }
    func explanationSituation(_ text: String) -> String { "Situation: \(text)" }
    var explanationChoicesTitle: String { "Our choices" }
    var explanationChoices: [String] {
        [
            "The PAL of each activity level: 1.4, 1.6, 1.8 and 2.0, EFSA's own grid.",
            "Zinc for a diet with 600 mg of phytate a day, EFSA's middle level.",
            "The \"average of both\" basis averages the female and male values.",
            "The weight used is the mean of your weigh-ins over the last 7 days.",
            "Salt is shown from sodium: salt (g) = sodium (mg) × 2.5 / 1000.",
        ]
    }
    func explanationProfileUpdated(_ date: String) -> String { "Profile last updated on \(date)" }
    var explanationOverriddenNote: String { "A value you entered; EFSA's value is still shown for information." }
    func ageBandLabel(from: Int, to: Int?) -> String { to.map { "\(from)–\($0) years" } ?? "\(from) years and over" }

    var weightTitle: String { "Weight" }
    var weightLog: String { "Log weight" }
    var weightKg: String { "Weight (kg)" }
    var weightDate: String { "Date" }
    var weightSave: String { "Save" }
    var weightEntries: String { "Entries" }
    var weightNone: String { "No entry yet." }
    var weightTrend: String { "Trend" }
    var weightMean: String { "7-day mean" }
}
