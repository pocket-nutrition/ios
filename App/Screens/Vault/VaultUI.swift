// SPDX-License-Identifier: MPL-2.0

import PocketNutritionVault
import SwiftUI
import UIKit

/// The card every vault screen is made of: a green title over its content.
struct VaultCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PnColor.brandLeafDeep)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .pnCard()
    }
}

struct VaultParagraph: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(PnColor.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct VaultErrorText: View {
    let error: VaultAccountError?

    var body: some View {
        if let message = error?.message {
            Text(message)
                .font(.footnote)
                .foregroundStyle(PnColor.statusBad)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A row that opens another screen, like a settings row.
struct VaultRow: View {
    let title: String
    var systemImage: String = "chevron.right"

    var body: some View {
        HStack {
            Text(title).font(.footnote.weight(.medium)).foregroundStyle(PnColor.inkDefault)
            Spacer()
            Image(systemName: systemImage).font(.footnote).foregroundStyle(PnColor.inkSoft)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
    }
}

/// A secret on the clipboard is readable by anything that reads it: keep it on this device and let it expire.
func copyVaultSecret(_ text: String) {
    UIPasteboard.general.setItems(
        [[UIPasteboard.typeAutomatic: text]],
        options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
}

extension VaultAccountError {
    /// What every vault screen says about a failure.
    @MainActor var message: String {
        let t = Strings.active
        switch self {
        case .invalidServerURL: return t.vaultErrInvalidServer
        case .notAVault: return t.vaultErrNotAVault
        case .offline: return t.vaultErrOffline
        case .invalidUsername: return t.vaultErrInvalidUsername
        case .passphraseTooShort: return t.vaultErrPassphraseShort
        case .passphraseMismatch: return t.vaultErrPassphraseMismatch
        case .usernameTaken: return t.vaultErrUsernameTaken
        case .registrationClosed: return t.vaultErrRegistrationClosed
        case .invalidCredentials: return t.vaultErrInvalidCredentials
        case .tooManyAttempts(let seconds): return t.vaultErrTooManyAttempts(seconds)
        case .unsafeKdf: return t.vaultErrUnsafeKdf
        case .keyringUnreadable: return t.vaultErrKeyring
        case .invalidTwoFactor: return t.vaultErrInvalidTwoFactor
        case .twoFactorRequired: return t.vaultErrTwoFactorRequired
        case .keyringConflict: return t.vaultErrKeyringConflict
        case .noPassphrase: return t.vaultErrNoPassphrase
        case .twoFactorStateChanged: return t.vaultErrTwoFactorChanged
        case .deviceRevoked: return t.vaultErrDeviceRevoked
        case .serverError: return t.vaultErrServer
        case .keychain: return t.vaultErrKeychain
        case .crypto: return t.vaultErrCrypto
        }
    }
}
