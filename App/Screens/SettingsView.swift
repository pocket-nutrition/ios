// SPDX-License-Identifier: MPL-2.0

import SwiftUI
import PocketNutritionCore

/// Language and the backend server — the two every-day-adjustable knobs, split out of `AboutView`
/// so the journal's menu can offer About and Settings as two distinct entries instead of one screen
/// that mixed licence/attribution obligations with things a user actually comes back to change.
struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var showVault = false

    /// `nil` selects "Automatique"/"Automatic" — see `LanguageSettings.override`.
    @State private var languageSelection: String? = LanguageSettings.shared.override

    /// Prefilled with whatever was last saved, valid or not — see `ApiSettings.customRawValue`.
    @State private var serverURLInput: String = ApiSettings.customRawValue ?? ""
    @State private var serverURLInvalid = false

    // Voice recognition server: separate from the API-server override above, which is left alone.
    @State private var recognitionURLInput: String = RecognitionSettings.rawURL ?? ""
    @State private var recognitionKeyInput = ""
    @State private var hasRecognitionKey = RecognitionSettings.hasApiKey()
    @State private var recognitionMessage: String?
    @State private var recognitionMessageIsError = false

    @AppStorage(TargetsFeature.defaultsKey) private var isTargetsEnabled = TargetsFeature.defaultEnabled

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    languageSection
                    targetsSection
                    serverSection
                    recognitionSection
                    vaultSection
                }
                .padding(20)
            }
            .background(PnColor.surfacePaper)
            .navigationTitle(Strings.active.settingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.active.aboutClose) { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    /// Automatique/Français/English — an every-user setting, unlike `serverSection`'s contributor-only
    /// escape hatch, which is why this sits above it.
    private var languageSection: some View {
        section(Strings.active.aboutLanguageTitle) {
            Picker(Strings.active.aboutLanguageTitle, selection: $languageSelection) {
                Text(Strings.active.aboutLanguageAuto).tag(String?.none)
                Text(Strings.active.aboutLanguageFr).tag(Optional("fr"))
                Text(Strings.active.aboutLanguageEn).tag(Optional("en"))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: languageSelection) { _, newValue in
                LanguageSettings.shared.setOverride(newValue)
            }
        }
    }

    /// Daily targets, behind its preview switch. Off: nothing of the feature shows and nothing is fetched.
    private var targetsSection: some View {
        let t = Strings.active
        return section(t.targetsTitle) {
            Toggle(t.targetsPreviewToggle, isOn: $isTargetsEnabled)
                .font(.subheadline)
                .tint(PnColor.brandLeaf)
                .accessibilityIdentifier("targets-preview-toggle")
            paragraph(t.targetsPreviewBody)
            if isTargetsEnabled {
                NavigationLink {
                    TargetsSettingsView()
                } label: {
                    Text(t.targetsTitle)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("targets-open")
            }
        }
    }

    /// A contributor-facing escape hatch: point the app at a self-hosted server instead of the
    /// official one. Not something the average user needs, which is why it is the last section here.
    private var serverSection: some View {
        section(Strings.active.aboutServerTitle) {
            paragraph(Strings.active.aboutServerBody)

            HStack(spacing: 8) {
                // The current server doubles as the placeholder: greyed out and gone the moment an
                // override exists, rather than restated in a line of its own above the field.
                TextField(ApiSettings.baseURL.absoluteString, text: $serverURLInput)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.footnote)

                // An icon next to the field it acts on, not a second full-width text button below —
                // "reset" reads faster as a glyph beside the value it clears than as a sentence.
                Button {
                    resetServerURL()
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                .foregroundStyle(PnColor.inkSoft)
                .accessibilityLabel(Strings.active.aboutServerReset)
            }

            if serverURLInvalid {
                Text(Strings.active.aboutServerInvalid)
                    .font(.footnote)
                    .foregroundStyle(PnColor.statusBad)
            }

            Button(Strings.active.aboutServerApply) { applyServerURL() }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    /// The voice-recognition server: address plus API key (masked, stored in the Keychain). The body
    /// says plainly where the recording goes and how long it stays on the phone.
    private var recognitionSection: some View {
        let t = Strings.active
        return section(t.recognitionSettingsTitle) {
            paragraph(t.recognitionSettingsBody)

            TextField(t.recognitionServerLabel, text: $recognitionURLInput)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.footnote)

            SecureField(
                hasRecognitionKey ? t.recognitionKeySavedPlaceholder : t.recognitionKeyLabel,
                text: $recognitionKeyInput
            )
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.footnote)

            if let recognitionMessage {
                Text(recognitionMessage)
                    .font(.footnote)
                    .foregroundStyle(recognitionMessageIsError ? PnColor.statusBad : PnColor.inkSoft)
            }

            Button(t.recognitionSave) { saveRecognition() }
                .buttonStyle(PrimaryButtonStyle())
            Button(t.recognitionClear) { clearRecognition() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PnColor.inkSoft)
        }
    }

    /// Entry point to the cloud vault: its own screen, since it is an account flow and not a single field.
    private var vaultSection: some View {
        let t = Strings.active
        return section(t.vaultTitle) {
            paragraph(t.vaultIntro)
            Button(t.vaultTitle) { showVault = true }
                .buttonStyle(PrimaryButtonStyle())
        }
        .sheet(isPresented: $showVault) { VaultView() }
    }

    private func saveRecognition() {
        let t = Strings.active
        do {
            try RecognitionSettings.save(urlText: recognitionURLInput, apiKey: recognitionKeyInput)
            recognitionKeyInput = ""
            hasRecognitionKey = true
            recognitionMessage = t.recognitionSaved
            recognitionMessageIsError = false
        } catch {
            recognitionMessageIsError = true
            switch error {
            case .invalidURL: recognitionMessage = t.recognitionInvalidURL
            case .keychain: recognitionMessage = t.recognitionSaveFailed
            case .keyRequiredForNewHost: recognitionMessage = t.recognitionKeyRequiredForNewHost
            }
        }
    }

    private func clearRecognition() {
        recognitionKeyInput = ""
        guard RecognitionSettings.clear() else {
            recognitionMessage = Strings.active.recognitionClearFailed
            recognitionMessageIsError = true
            return
        }
        recognitionURLInput = ""
        hasRecognitionKey = false
        recognitionMessage = nil
    }

    // MARK: - Server override actions

    private func applyServerURL() {
        let accepted = ApiSettings.setCustomBaseURL(serverURLInput)
        serverURLInvalid = !accepted
        // A successful reset (empty input) clears the field back to its "no override" state, same
        // as tapping the explicit reset button below.
        if accepted && serverURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            serverURLInput = ""
        }
    }

    private func resetServerURL() {
        ApiSettings.reset()
        serverURLInput = ""
        serverURLInvalid = false
    }

    // MARK: - Building blocks

    private func section(
        _ title: String,
        @ViewBuilder _ content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PnColor.brandLeafDeep)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .pnCard()
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(PnColor.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
