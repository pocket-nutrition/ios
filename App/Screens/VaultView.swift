// SPDX-License-Identifier: MPL-2.0

import PocketNutritionCore
import PocketNutritionVault
import SwiftUI
import UIKit

/// Onboarding and account screen for the cloud vault: create an account or log in (which links this
/// phone), see who is logged in, unlink, or erase the account.
///
/// The official vault is connected to as soon as the screen opens, so a new person only ever sees a
/// username and a passphrase. Their own server is an option under "Advanced", never a step.
struct VaultView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(JournalSyncCoordinator.self) private var journalSync
    @Environment(JournalStore.self) private var journal
    @Environment(VaultSessionGuard.self) private var sessionGuard

    @State private var model = VaultAccountModel(deviceLabel: UIDevice.current.model)
    @State private var security = VaultSecurityModel.live()
    @State private var twoFactorCode = ""

    @State private var serverURLInput = VaultSettings.rawServerURL
    @State private var mode: Mode = .create
    @State private var username = ""
    @State private var passphrase = ""
    @State private var confirmation = ""

    /// The passphrase the app generated for this account: shown in the emergency kit and nowhere after it.
    /// Nil when the person chose their own, which is then not repeated back to them or put in the kit.
    @State private var generatedPassphrase: String?
    @State private var useOwnPassphrase = false
    @State private var showAdvanced = false

    @State private var showDelete = false
    @State private var deletePassphrase = ""
    @State private var notice: String?

    private enum Mode { case login, create }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch model.phase {
                    case .signedIn(let summary):
                        if sessionGuard.isLocked {
                            lockedSection
                        } else {
                            signedInSection(summary)
                        }
                    case .signedOut:
                        if let key = model.pendingRecoveryKey {
                            kitSection(key)
                        } else {
                            heroSection
                            if let info = model.serverInfo {
                                accountSection(info)
                            } else {
                                connectionSection
                            }
                            advancedSection
                        }
                    }
                    if let message = errorMessage { errorCard(message) }
                    if let notice { Text(notice).font(.footnote).foregroundStyle(PnColor.inkSoft) }
                }
                .padding(20)
            }
            .background(PnColor.surfacePaper)
            .navigationTitle(Strings.active.vaultTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.active.aboutClose) { dismiss() }
                }
            }
            .disabled(model.isWorking)
            .overlay { if model.isWorking { ProgressView().controlSize(.large) } }
            .task { await connectToDefaultServer() }
            .task { if sessionGuard.isLocked { await sessionGuard.unlock() } }
            // A timeout logged this phone out, or a new passphrase changed the stored session.
            .onChange(of: sessionGuard.timeoutLogouts) { _, _ in model.reload() }
            .onChange(of: security.revokedByPassphraseChange) { _, _ in model.reload() }
        }
    }

    /// The vault screens behind Face ID (opt-in). Only these screens: sync keeps running underneath.
    private var lockedSection: some View {
        let t = Strings.active
        return section(t.vaultLockedTitle) {
            Label(t.vaultLockedBody, systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(PnColor.inkSoft)
            Button(t.vaultUnlock) { Task { await sessionGuard.unlock() } }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    /// Opening the screen is enough to reach the official vault; a person who changed the address under
    /// "Advanced" gets that one back the next time.
    private func connectToDefaultServer() async {
        guard case .signedOut = model.phase, model.serverInfo == nil else { return }
        await model.checkServer(serverURLInput)
    }

    // MARK: - Server and account

    private var heroSection: some View {
        let t = Strings.active
        return section(t.vaultHeroTitle) {
            Label(t.vaultBenefitSync, systemImage: "icloud")
                .font(.footnote)
                .foregroundStyle(PnColor.inkSoft)
            Label(t.vaultBenefitVoice, systemImage: "mic")
                .font(.footnote)
                .foregroundStyle(PnColor.inkSoft)
            Label(t.vaultBenefitPrivate, systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(PnColor.inkSoft)
        }
    }

    /// Shown while the official vault is being reached, and with a retry when it could not be.
    private var connectionSection: some View {
        let t = Strings.active
        return section(t.vaultTitle) {
            if model.error == nil {
                Label(t.vaultConnecting, systemImage: "network")
                    .font(.footnote)
                    .foregroundStyle(PnColor.inkSoft)
            } else {
                Button(t.vaultRetry) { Task { await model.checkServer(serverURLInput) } }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    /// The server address, out of the way: the official vault is the default and the line says so.
    private var advancedSection: some View {
        let t = Strings.active
        return DisclosureGroup(t.vaultAdvanced, isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 8) {
                paragraph(t.vaultAdvancedHint)
                TextField(t.vaultServerLabel, text: $serverURLInput)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.footnote)
                    .onChange(of: serverURLInput) { _, _ in model.clearError() }
                if let info = model.serverInfo {
                    Label(t.vaultServerFound(info.name), systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(PnColor.brandLeafDeep)
                }
                Button(t.vaultCheckServer) { Task { await model.checkServer(serverURLInput) } }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PnColor.inkSoft)
            }
            .padding(.top, 8)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(PnColor.inkSoft)
    }

    private func accountSection(_ info: VaultServerInfo) -> some View {
        let t = Strings.active
        let canCreate = info.isRegistrationOpen
        return section(mode == .create ? t.vaultCreateAccount : t.vaultLogin) {
            Picker("", selection: $mode) {
                Text(t.vaultLogin).tag(Mode.login)
                Text(t.vaultCreateAccount).tag(Mode.create)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: mode) { _, _ in
                model.cancelTwoFactor()
                twoFactorCode = ""
            }

            if !canCreate { paragraph(t.vaultRegistrationClosed) }

            TextField(t.vaultUsernameLabel, text: $username)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .font(.footnote)
            if mode == .login || useOwnPassphrase {
                SecureField(t.vaultPassphraseLabel, text: $passphrase)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(mode == .create ? .newPassword : .password)
                    .font(.footnote)
            }
            if mode == .login && model.needsTwoFactor {
                paragraph(t.vaultTwoFactorLoginHint)
                TextField(t.vaultTwoFactorCodeOrRecovery, text: $twoFactorCode)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.oneTimeCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
            }

            if mode == .create {
                if useOwnPassphrase {
                    SecureField(t.vaultPassphraseConfirmLabel, text: $confirmation)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.newPassword)
                        .font(.footnote)
                    paragraph(t.vaultPassphraseHint)
                } else {
                    paragraph(t.vaultGeneratedHint)
                }
                if !journal.meals.isEmpty { paragraph(t.vaultTransferHint(journal.meals.count)) }
                Button(useOwnPassphrase ? t.vaultGeneratePassphrase : t.vaultOwnPassphrase) {
                    useOwnPassphrase.toggle()
                    passphrase = ""
                    confirmation = ""
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(PnColor.inkSoft)
            }

            Button(mode == .create ? t.vaultCreateVault : t.vaultLogin) { submit() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(mode == .create && !canCreate)

            if serverURLInput == VaultSettings.defaultServerURL {
                Text(t.vaultOfficialServer(VaultSettings.defaultServerHost))
                    .font(.caption)
                    .foregroundStyle(PnColor.inkSoft)
            }
        }
    }

    private func submit() {
        switch mode {
        case .login:
            Task {
                await model.login(
                    username: username, passphrase: passphrase,
                    twoFactorCode: model.needsTwoFactor ? twoFactorCode : nil)
                if case .signedIn = model.phase {
                    resetForm()
                    journalSync.syncSoon(after: .zero)
                }
            }
        case .create:
            let phrase = useOwnPassphrase ? passphrase : VaultPassphraseSuggestion.make()
            let confirm = useOwnPassphrase ? confirmation : phrase
            // Set before the kit can appear: the kit quizzes the person on this passphrase.
            generatedPassphrase = useOwnPassphrase ? nil : phrase
            Task {
                await model.prepareAccount(username: username, passphrase: phrase, confirmation: confirm)
            }
        }
    }

    // MARK: - Emergency kit

    /// Everything needed to get back in, in one place. Registration waits until the kit was copied or shared
    /// and a word of the passphrase was typed back: the server can regenerate none of it.
    private func kitSection(_ key: String) -> some View {
        let t = Strings.active
        return VaultEmergencyKitView(
            title: t.vaultRecoveryTitle, intro: t.vaultRecoveryBody,
            host: VaultSettings.hostLabel(serverURLInput), username: username,
            shownPassphrase: generatedPassphrase, passphrase: generatedPassphrase ?? passphrase,
            recoveryKey: key, finishTitle: t.vaultRecoveryContinue,
            finish: {
                Task {
                    await model.registerPreparedAccount()
                    if case .signedIn = model.phase {
                        resetForm()
                        journalSync.syncSoon(after: .zero)
                    }
                }
            },
            cancel: { model.discardPendingAccount() }
        )
        .id(key)
    }

    // MARK: - Signed in

    private func signedInSection(_ summary: VaultAccountSummary) -> some View {
        let t = Strings.active
        return VStack(alignment: .leading, spacing: 16) {
            section(t.vaultTitle) {
                Label(
                    t.vaultSignedInAs(summary.username, host: summary.serverURL.host() ?? summary.serverURL.absoluteString),
                    systemImage: "lock.shield"
                )
                .font(.footnote)
                .foregroundStyle(PnColor.brandLeafDeep)

                syncStatus

                // Logging out sits well apart from "sync now": the two used to be adjacent, an easy mis-tap.
                Divider()
                    .padding(.vertical, 12)

                Button(t.vaultLogout) {
                    Task {
                        let reached = await model.logout()
                        journalSync.unlinked()
                        sessionGuard.signedOut()
                        notice = reached ? nil : t.vaultLogoutUnreached
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            VaultSecuritySection(security: security)

            section(t.vaultDeleteAccount) {
                if showDelete {
                    paragraph(t.vaultDeleteBody)
                    SecureField(t.vaultPassphraseLabel, text: $deletePassphrase)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .font(.footnote)
                    Button(t.vaultDeleteConfirm) {
                        Task {
                            await model.deleteAccount(passphrase: deletePassphrase)
                            if case .signedOut = model.phase {
                                journalSync.unlinked()
                                sessionGuard.signedOut()
                            }
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PnColor.statusBad)
                    .disabled(deletePassphrase.isEmpty)
                    Button(t.vaultCancel) {
                        showDelete = false
                        deletePassphrase = ""
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PnColor.inkSoft)
                } else {
                    Button(t.vaultDeleteAccount) { showDelete = true }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PnColor.statusBad)
                }
            }
        }
    }

    /// What the journal sync is doing, and a way to run it now.
    private var syncStatus: some View {
        let t = Strings.active
        let text: String
        switch journalSync.status {
        case .off, .syncing: text = t.vaultSyncing
        case .idle: text = t.vaultSynced(journal.meals.count)
        case .offline: text = t.vaultSyncOffline
        case .full: text = t.vaultSyncFull
        case .failed: text = t.vaultSyncFailed
        }
        return VStack(alignment: .leading, spacing: 8) {
            Label(text, systemImage: journalSync.status == .idle ? "checkmark.icloud" : "arrow.triangle.2.circlepath.icloud")
                .font(.footnote)
                .foregroundStyle(PnColor.inkSoft)
            Button(t.vaultSyncNow) { Task { await journalSync.syncNow() } }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PnColor.brandLeafDeep)
                .disabled(journalSync.status == .syncing)
        }
    }

    // MARK: - Messages and helpers

    private var errorMessage: String? { model.error?.message }

    private func errorCard(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(PnColor.statusBad)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Passphrases must not outlive the screen that took them.
    private func resetForm() {
        username = ""
        passphrase = ""
        confirmation = ""
        generatedPassphrase = nil
        useOwnPassphrase = false
        deletePassphrase = ""
        showDelete = false
        twoFactorCode = ""
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
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
