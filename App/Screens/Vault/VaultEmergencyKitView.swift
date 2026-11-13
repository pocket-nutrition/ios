// SPDX-License-Identifier: MPL-2.0

import PocketNutritionVault
import SwiftUI
import UIKit

/// The emergency kit, with a gate: the finish button stays disabled until the kit was copied or shared AND
/// one word of the passphrase, picked at random, was typed back correctly. Used at account creation and
/// after a passphrase reset. The passphrase is never shown again after this screen, and the server can
/// regenerate none of it.
struct VaultEmergencyKitView: View {

    let title: String
    let intro: String
    let host: String
    let username: String
    /// The passphrase as it goes in the kit, or nil when the person chose their own (not repeated back).
    let shownPassphrase: String?
    /// The passphrase checked by the retype step. Always known here, never displayed by this view itself.
    let passphrase: String
    let recoveryKey: String
    let finishTitle: String
    let finish: () -> Void
    var cancel: (() -> Void)?

    @State private var copied = false
    @State private var shared = false
    @State private var showShare = false
    @State private var typed = ""
    /// Zero-based; nil when the passphrase has no separate words and must be typed whole.
    @State private var wordIndex: Int?

    init(
        title: String, intro: String, host: String, username: String, shownPassphrase: String?,
        passphrase: String, recoveryKey: String, finishTitle: String,
        finish: @escaping () -> Void, cancel: (() -> Void)? = nil
    ) {
        self.title = title
        self.intro = intro
        self.host = host
        self.username = username
        self.shownPassphrase = shownPassphrase
        self.passphrase = passphrase
        self.recoveryKey = recoveryKey
        self.finishTitle = finishTitle
        self.finish = finish
        self.cancel = cancel
        let count = vaultPassphraseWords(passphrase).count
        _wordIndex = State(initialValue: count >= 2 ? Int.random(in: 0..<count) : nil)
    }

    private var isSaved: Bool { copied || shared }

    private var isRetypeCorrect: Bool {
        isVaultKitRetypeCorrect(typed: typed, passphrase: passphrase, wordIndex: wordIndex)
    }

    private var kitText: String {
        Strings.active.vaultKitText(
            host: host, username: username, passphrase: shownPassphrase, recoveryKey: recoveryKey)
    }

    var body: some View {
        let t = Strings.active
        VaultCard(title: title) {
            VaultParagraph(intro)

            VStack(alignment: .leading, spacing: 10) {
                row(t.vaultServerLabel, host)
                row(t.vaultUsernameLabel, username)
                if let shownPassphrase { row(t.vaultPassphraseLabel, shownPassphrase) }
                row(t.vaultRecoveryKeyLabel, recoveryKey)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(PnColor.surfaceCream)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .privacySensitive()

            Text(t.vaultKitCannotShowAgain)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PnColor.inkDefault)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                Button {
                    copyVaultSecret(kitText)
                    copied = true
                } label: {
                    Label(copied ? t.vaultRecoveryCopied : t.vaultRecoveryCopy, systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                Button { showShare = true } label: {
                    Label(shared ? t.vaultKitShared : t.vaultKitShareOrSave, systemImage: shared ? "checkmark" : "square.and.arrow.up")
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(PnColor.brandLeafDeep)

            if !isSaved { VaultParagraph(t.vaultKitSaveFirst) }

            Text(wordIndex.map { t.vaultKitWordPrompt($0 + 1) } ?? t.vaultKitWholePrompt)
                .font(.footnote.weight(.medium))
                .foregroundStyle(PnColor.inkDefault)
            TextField("", text: $typed)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.oneTimeCode)
                .font(.system(.footnote, design: .monospaced))
                .privacySensitive()
                .accessibilityLabel(wordIndex.map { t.vaultKitWordPrompt($0 + 1) } ?? t.vaultKitWholePrompt)
            if !typed.isEmpty && !isRetypeCorrect {
                Text(t.vaultKitWordWrong).font(.caption).foregroundStyle(PnColor.statusBad)
            }

            Button(finishTitle) {
                typed = ""
                finish()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!isSaved || !isRetypeCorrect)

            if let cancel {
                Button(t.vaultCancel, action: cancel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PnColor.inkSoft)
            }
        }
        .sheet(isPresented: $showShare) {
            VaultActivitySheet(text: kitText) { completed in
                if completed { shared = true }
            }
        }
        .onDisappear { typed = "" }
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(PnColor.inkSoft)
            Text(value)
                .font(.system(.footnote, design: .monospaced).weight(.medium))
                .textSelection(.enabled)
        }
    }
}

/// The passphrase's words: split on hyphens and whitespace, as generated passphrases are written.
func vaultPassphraseWords(_ passphrase: String) -> [String] {
    passphrase.split(whereSeparator: { $0 == "-" || $0.isWhitespace }).map(String.init)
}

/// Whether the retype step passes: the asked word (case and surrounding spaces ignored), or the whole
/// passphrase exactly (after the same normalisation the KDF applies) when it has no separate words.
func isVaultKitRetypeCorrect(typed: String, passphrase: String, wordIndex: Int?) -> Bool {
    guard let wordIndex else {
        return !typed.isEmpty
            && typed.precomposedStringWithCompatibilityMapping == passphrase.precomposedStringWithCompatibilityMapping
    }
    let words = vaultPassphraseWords(passphrase)
    guard words.indices.contains(wordIndex) else { return false }
    let answer = typed.trimmingCharacters(in: .whitespaces).precomposedStringWithCompatibilityMapping.lowercased()
    return answer == words[wordIndex].precomposedStringWithCompatibilityMapping.lowercased()
}

/// The system share sheet, reporting whether the person actually sent or saved the kit (cancelling the
/// sheet does not count as saving it).
private struct VaultActivitySheet: UIViewControllerRepresentable {
    let text: String
    let completion: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in completion(completed) }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
