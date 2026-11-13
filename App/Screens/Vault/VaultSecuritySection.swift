// SPDX-License-Identifier: MPL-2.0

import PocketNutritionCore
import PocketNutritionVault
import SwiftUI

/// "Account security" on the signed-in vault screen: session expiry and the Face ID lock, linked
/// devices, and the fingerprint phrase, two-factor login and passphrase change.
struct VaultSecuritySection: View {

    @Environment(VaultSessionGuard.self) private var sessionGuard
    let security: VaultSecurityModel

    @State private var showFingerprint = false

    var body: some View {
        let t = Strings.active
        VStack(alignment: .leading, spacing: 16) {
            sessionCard
            VaultCard(title: t.vaultDevicesTitle) {
                NavigationLink { VaultDevicesView(security: security) } label: { VaultRow(title: t.vaultDevices) }
            }
            VaultCard(title: t.vaultOtherOptions) {
                Button { showFingerprint = true } label: { VaultRow(title: t.vaultFingerprintTitle, systemImage: "touchid") }
                    .buttonStyle(.plain)
                Divider()
                NavigationLink { VaultTwoFactorView(security: security) } label: { VaultRow(title: t.vaultTwoFactorTitle) }
                Divider()
                NavigationLink { VaultChangePassphraseView(security: security) } label: {
                    VaultRow(title: t.vaultChangePassphraseTitle)
                }
            }
        }
        .sheet(isPresented: $showFingerprint) {
            FingerprintPhraseSheet(phrase: security.fingerprintPhrase)
                .presentationDetents([.medium])
        }
    }

    private var sessionCard: some View {
        @Bindable var settings = sessionGuard
        let t = Strings.active
        return VaultCard(title: t.vaultSessionTitle) {
            if let biometry = sessionGuard.biometryName {
                Toggle(
                    t.vaultLockToggle(biometry),
                    isOn: Binding(
                        get: { sessionGuard.isBiometricLockEnabled },
                        set: { enabled in Task { await sessionGuard.setBiometricLock(enabled) } }))
                    .font(.footnote)
                    .tint(PnColor.brandLeafDeep)
            }

            Picker(t.vaultTimeoutLabel, selection: $settings.timeout) {
                ForEach(VaultSessionTimeout.allCases, id: \.self) { Text(t.vaultTimeoutOption($0)).tag($0) }
            }
            .pickerStyle(.menu)
            .font(.footnote)

            if settings.timeout != .never {
                Picker(t.vaultTimeoutActionLabel, selection: $settings.action) {
                    ForEach(sessionGuard.availableActions, id: \.self) { Text(t.vaultTimeoutAction($0)).tag($0) }
                }
                .pickerStyle(.menu)
                .font(.footnote)
            }
            VaultParagraph(sessionGuard.isBiometricLockEnabled ? t.vaultSessionHintLock : t.vaultSessionHint)
        }
    }
}

// MARK: - Devices

struct VaultDevicesView: View {
    let security: VaultSecurityModel
    @State private var pendingRevoke: VaultDevice?

    var body: some View {
        let t = Strings.active
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VaultCard(title: t.vaultDevicesTitle) {
                    VaultParagraph(t.vaultDevicesHint)
                    ForEach(security.devices) { device in
                        Divider()
                        row(device)
                    }
                    if security.devices.isEmpty && !security.isWorking { VaultParagraph(t.vaultDevicesEmpty) }
                }
                VaultErrorText(error: security.error)
            }
            .padding(20)
        }
        .background(PnColor.surfacePaper)
        .navigationTitle(t.vaultDevices)
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if security.isWorking { ProgressView() } }
        .task { await security.loadDevices() }
        .refreshable { await security.loadDevices() }
        .confirmationDialog(
            t.vaultRevokeTitle(pendingRevoke?.label ?? ""),
            isPresented: Binding(get: { pendingRevoke != nil }, set: { if !$0 { pendingRevoke = nil } }),
            titleVisibility: .visible, presenting: pendingRevoke
        ) { device in
            Button(t.vaultRevoke, role: .destructive) { Task { await security.revokeDevice(id: device.id) } }
            Button(t.vaultCancel, role: .cancel) {}
        } message: { _ in
            Text(t.vaultRevokeBody)
        }
    }

    private func row(_ device: VaultDevice) -> some View {
        let t = Strings.active
        let isThis = device.id == security.currentDeviceId
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.label.isEmpty ? t.vaultDeviceUnnamed : device.label)
                    .font(.footnote.weight(.medium))
                if let date = device.createdDate {
                    Text(t.vaultDeviceLinked(date.formatted(date: .abbreviated, time: .shortened)))
                        .font(.caption)
                        .foregroundStyle(PnColor.inkSoft)
                }
            }
            Spacer()
            if isThis {
                Text(t.vaultThisDevice).font(.caption.weight(.semibold)).foregroundStyle(PnColor.brandLeafDeep)
            } else {
                Button(t.vaultRevoke) { pendingRevoke = device }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PnColor.statusBad)
            }
        }
    }
}

/// The fingerprint phrase, read-only. It names the account's keys so two devices can be compared by eye;
/// it is not a passphrase, and offering to copy it made it look like one.
private struct FingerprintPhraseSheet: View {
    let phrase: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let t = Strings.active
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(phrase ?? "—")
                    .font(.body.monospaced())
                    .foregroundStyle(PnColor.inkDefault)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(PnColor.surfaceCream, in: RoundedRectangle(cornerRadius: 10))
                Text(t.vaultFingerprintNotPassphrase)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PnColor.inkDefault)
                    .fixedSize(horizontal: false, vertical: true)
                Text(t.vaultFingerprintExplanation)
                    .font(.footnote)
                    .foregroundStyle(PnColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding()
            .navigationTitle(t.vaultFingerprintTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(t.aboutClose) { dismiss() } }
            }
        }
    }
}
