// SPDX-License-Identifier: MPL-2.0

import CoreImage.CIFilterBuiltins
import PocketNutritionCore
import PocketNutritionVault
import SwiftUI

/// Two-factor login with an authenticator app (TOTP). It guards linking a NEW device: phones already
/// linked keep working, and it does nothing against someone guessing the passphrase offline.
struct VaultTwoFactorView: View {
    let security: VaultSecurityModel
    @Environment(\.openURL) private var openURL

    @State private var passphrase = ""
    @State private var code = ""
    @State private var codesCopied = false

    var body: some View {
        let t = Strings.active
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch security.twoFactorStep {
                case .confirming(let setup): confirmCard(setup)
                case .showingRecoveryCodes(let codes): recoveryCard(codes)
                case .idle:
                    if let status = security.twoFactor {
                        if status.enabled { disableCard(status) } else { enableCard }
                    }
                }
                VaultErrorText(error: security.error)
            }
            .padding(20)
        }
        .background(PnColor.surfacePaper)
        .navigationTitle(t.vaultTwoFactorTitle)
        .navigationBarTitleDisplayMode(.inline)
        .disabled(security.isWorking)
        .overlay { if security.isWorking { ProgressView().controlSize(.large) } }
        .task { await security.loadTwoFactor() }
        .onDisappear {
            passphrase = ""
            code = ""
            // Recovery codes are shown once; a setup left halfway simply stays pending on the server.
            security.finishTwoFactorStep()
        }
    }

    private var enableCard: some View {
        let t = Strings.active
        return VaultCard(title: t.vaultTwoFactorOff) {
            VaultParagraph(t.vaultTwoFactorIntro)
            passphraseField
            Button(t.vaultTwoFactorStart) {
                Task {
                    await security.startTwoFactorSetup(passphrase: passphrase)
                    if case .confirming = security.twoFactorStep { passphrase = "" }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(passphrase.isEmpty)
        }
    }

    private func confirmCard(_ setup: VaultTwoFactorSetup) -> some View {
        let t = Strings.active
        return VaultCard(title: t.vaultTwoFactorSetupTitle) {
            VaultParagraph(t.vaultTwoFactorSetupBody)
            if let url = URL(string: setup.otpauthURI) {
                Button { openURL(url) } label: {
                    Label(t.vaultTwoFactorOpenApp, systemImage: "key.viewfinder")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PnColor.brandLeafDeep)
            }
            if let qr = qrImage(setup.otpauthURI) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(t.vaultTwoFactorQR)
            }
            VaultParagraph(t.vaultTwoFactorManual)
            HStack {
                Text(setup.groupedSecret)
                    .font(.system(.footnote, design: .monospaced).weight(.medium))
                    .textSelection(.enabled)
                Spacer()
                Button(t.vaultCopy) { copyVaultSecret(setup.secret) }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PnColor.brandLeafDeep)
            }
            codeField(t.vaultTwoFactorCodeLabel)
            Button(t.vaultTwoFactorConfirm) {
                Task {
                    await security.confirmTwoFactor(code: code)
                    if case .showingRecoveryCodes = security.twoFactorStep { code = "" }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(code.isEmpty)
            Button(t.vaultCancel) { security.finishTwoFactorStep() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PnColor.inkSoft)
        }
    }

    private func recoveryCard(_ codes: [String]) -> some View {
        let t = Strings.active
        let text = t.vaultRecoveryCodesText(codes)
        return VaultCard(title: t.vaultRecoveryCodesTitle) {
            VaultParagraph(t.vaultRecoveryCodesBody)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(codes, id: \.self) { Text($0).font(.system(.footnote, design: .monospaced)) }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(PnColor.surfaceCream)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack(spacing: 16) {
                ShareLink(item: text) { Label(t.vaultKitShare, systemImage: "square.and.arrow.up") }
                Button(codesCopied ? t.vaultCopied : t.vaultCopy) {
                    copyVaultSecret(text)
                    codesCopied = true
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(PnColor.brandLeafDeep)
            Button(t.vaultRecoveryCodesDone) { security.finishTwoFactorStep() }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func disableCard(_ status: VaultTwoFactorStatus) -> some View {
        let t = Strings.active
        return VaultCard(title: t.vaultTwoFactorOn) {
            VaultParagraph(t.vaultTwoFactorOnBody(status.recoveryCodesLeft))
            passphraseField
            codeField(t.vaultTwoFactorCodeOrRecovery)
            Button(t.vaultTwoFactorDisable) {
                Task {
                    await security.disableTwoFactor(passphrase: passphrase, code: code)
                    if security.error == nil {
                        passphrase = ""
                        code = ""
                    }
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(PnColor.statusBad)
            .disabled(passphrase.isEmpty || code.isEmpty)
        }
    }

    private var passphraseField: some View {
        SecureField(Strings.active.vaultPassphraseLabel, text: $passphrase)
            .textFieldStyle(.roundedBorder)
            .textContentType(.password)
            .font(.footnote)
    }

    private func codeField(_ label: String) -> some View {
        TextField(label, text: $code)
            .textFieldStyle(.roundedBorder)
            .textContentType(.oneTimeCode)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(.footnote, design: .monospaced))
    }

    /// The otpauth URI as a QR code, for an authenticator on another device.
    private func qrImage(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
