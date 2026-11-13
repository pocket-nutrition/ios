// SPDX-License-Identifier: MPL-2.0

import PocketNutritionCore
import PocketNutritionVault
import SwiftUI

/// "Change passphrase", from a phone that is linked and so holds the user key: the current passphrase is
/// never asked, so the same screen serves a forgotten one. Explains what happens, lets the person pick a
/// generated passphrase (recommended) or their own, asks the device owner (Face ID, Touch ID or the
/// passcode) and, when two-factor is on, a code. It always goes through the reset endpoint, so a new
/// recovery key comes with it, and the new emergency kit is shown behind the same save gate as at account
/// creation. The screen cannot be left while the kit is up, short of the finish button.
struct VaultChangePassphraseView: View {
    let security: VaultSecurityModel

    @Environment(\.dismiss) private var dismiss
    @Environment(VaultSessionGuard.self) private var sessionGuard

    private enum Choice: Hashable { case generated, own }

    @State private var choice: Choice = .generated
    @State private var newPassphrase = ""
    @State private var confirmation = ""
    @State private var code = ""
    @State private var askForCode = false
    @State private var notice: String?
    @State private var reset: VaultPassphraseReset?

    private var needsCode: Bool { askForCode || security.twoFactor?.enabled == true }

    private var canSubmit: Bool {
        (choice == .generated || (!newPassphrase.isEmpty && !confirmation.isEmpty)) && (!needsCode || !code.isEmpty)
    }

    var body: some View {
        let t = Strings.active
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let reset {
                    VaultEmergencyKitView(
                        title: t.vaultResetDoneTitle, intro: t.vaultResetDoneBody(reset.revokedDevices),
                        host: reset.serverURL.host() ?? reset.serverURL.absoluteString, username: reset.username,
                        shownPassphrase: reset.isGenerated ? reset.passphrase : nil, passphrase: reset.passphrase,
                        recoveryKey: reset.recoveryKey, finishTitle: t.vaultResetFinish,
                        finish: {
                            self.reset = nil
                            dismiss()
                        })
                } else {
                    explanationCard
                    passphraseCard
                }
                VaultErrorText(error: security.error)
                if let notice {
                    Text(notice).font(.footnote).foregroundStyle(PnColor.statusBad)
                }
            }
            .padding(20)
        }
        .background(PnColor.surfacePaper)
        .navigationTitle(t.vaultChangePassphraseTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(reset != nil)
        .disabled(security.isWorking)
        .overlay { if security.isWorking { ProgressView().controlSize(.large) } }
        .task { await security.loadTwoFactor() }
        .onChange(of: security.error) { _, error in if error == .twoFactorRequired { askForCode = true } }
        .onDisappear(perform: clear)
    }

    private var explanationCard: some View {
        let t = Strings.active
        return VaultCard(title: t.vaultChangePassphraseTitle) {
            VaultParagraph(t.vaultResetIntro)
            ForEach(t.vaultResetEffects, id: \.self) { effect in
                Label {
                    Text(effect).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "circle.fill").font(.system(size: 5))
                }
                .font(.footnote)
                .foregroundStyle(PnColor.inkSoft)
            }
        }
    }

    private var passphraseCard: some View {
        let t = Strings.active
        return VaultCard(title: t.vaultNewPassphrase) {
            choiceRow(t.vaultPassphraseChoiceGenerated, .generated)
            choiceRow(t.vaultPassphraseChoiceOwn, .own)
                .onChange(of: choice) { _, _ in
                newPassphrase = ""
                confirmation = ""
                security.clearError()
            }

            if choice == .generated {
                VaultParagraph(t.vaultGeneratedHint)
            } else {
                SecureField(t.vaultNewPassphrase, text: $newPassphrase)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)
                    .font(.footnote)
                SecureField(t.vaultPassphraseConfirmLabel, text: $confirmation)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)
                    .font(.footnote)
                VaultParagraph(t.vaultPassphraseHint)
            }

            if needsCode {
                VaultParagraph(t.vaultResetTwoFactorHint)
                TextField(t.vaultTwoFactorCodeOrRecovery, text: $code)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.oneTimeCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
            }

            Button(t.vaultResetConfirm) { Task { await start() } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSubmit)
        }
    }

    private func choiceRow(_ title: String, _ value: Choice) -> some View {
        Button { choice = value } label: {
            HStack(spacing: 10) {
                Image(systemName: choice == value ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(PnColor.brandLeafDeep)
                Text(title).font(.footnote.weight(.medium)).foregroundStyle(PnColor.inkDefault)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(choice == value ? .isSelected : [])
    }

    private func start() async {
        let t = Strings.active
        notice = nil
        security.clearError()
        // The registration rules, checked before asking for Face ID, so a typo does not cost a prompt.
        if choice == .own {
            guard isAcceptableVaultPassphrase(newPassphrase) else {
                notice = VaultAccountError.passphraseTooShort.message
                return
            }
            guard newPassphrase == confirmation else {
                notice = VaultAccountError.passphraseMismatch.message
                return
            }
        }
        switch await sessionGuard.confirmOwner(reason: t.vaultResetReason) {
        case .unavailable:
            notice = t.vaultResetNeedsPasscode
            return
        case .failed:
            notice = t.vaultResetAuthFailed
            return
        case .passed:
            break
        }
        let newChoice: VaultNewPassphrase =
            choice == .generated ? .generated : .own(newPassphrase, confirmation: confirmation)
        let typedCode = needsCode ? code : nil
        code = ""
        if let done = await security.changePassphrase(newChoice, twoFactorCode: typedCode) {
            newPassphrase = ""
            confirmation = ""
            reset = done
        }
    }

    /// Passphrases must not outlive the screen that took them.
    private func clear() {
        newPassphrase = ""
        confirmation = ""
        code = ""
        reset = nil
    }
}
