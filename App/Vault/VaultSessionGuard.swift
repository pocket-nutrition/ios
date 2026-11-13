// SPDX-License-Identifier: MPL-2.0

import Foundation
import LocalAuthentication
import Observation
import PocketNutritionCore
import PocketNutritionVault

/// Session expiry for the vault: after the chosen time in the background, either lock the vault screens
/// behind Face ID (opt-in, off by default) or log this phone out.
///
/// The lock is a screen lock only: the keys stay in the Keychain, so journal sync and dictation results
/// keep flowing while the vault screens are locked. Logging out is the real thing (`VaultAccountModel`).
/// Settings are plain preferences: none of them is a secret.
@MainActor
@Observable
final class VaultSessionGuard {

    private enum Key {
        static let timeout = "vaultSessionTimeout"
        static let action = "vaultTimeoutAction"
        static let biometric = "vaultBiometricLock"
        static let backgroundedAt = "vaultBackgroundedAt"
    }

    var timeout: VaultSessionTimeout {
        didSet { UserDefaults.standard.set(timeout.rawValue, forKey: Key.timeout) }
    }
    var action: VaultTimeoutAction {
        didSet { UserDefaults.standard.set(action.rawValue, forKey: Key.action) }
    }
    private(set) var isBiometricLockEnabled: Bool {
        didSet { UserDefaults.standard.set(isBiometricLockEnabled, forKey: Key.biometric) }
    }
    private(set) var isLocked = false
    /// Bumped whenever a timeout logged the phone out, so an open vault screen can re-read its state.
    private(set) var timeoutLogouts = 0

    @ObservationIgnored private let journalSync: JournalSyncCoordinator
    @ObservationIgnored private var isColdLaunch = true

    init(journalSync: JournalSyncCoordinator) {
        self.journalSync = journalSync
        let defaults = UserDefaults.standard
        timeout = defaults.string(forKey: Key.timeout).flatMap(VaultSessionTimeout.init(rawValue:)) ?? .never
        isBiometricLockEnabled = defaults.bool(forKey: Key.biometric)
        action = defaults.string(forKey: Key.action).flatMap(VaultTimeoutAction.init(rawValue:)) ?? .logOut
    }

    /// The actions this phone can offer: locking needs Face ID turned on.
    var availableActions: [VaultTimeoutAction] {
        isBiometricLockEnabled ? [.lock, .logOut] : [.logOut]
    }

    // MARK: - App lifecycle

    func appDidEnterBackground() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Key.backgroundedAt)
    }

    func appDidBecomeActive() async {
        let coldLaunch = isColdLaunch
        isColdLaunch = false
        guard isLinked else { return }
        let stored = UserDefaults.standard.double(forKey: Key.backgroundedAt)
        let backgroundedAt = stored > 0 ? Date(timeIntervalSince1970: stored) : nil
        guard isVaultSessionExpired(timeout: timeout, backgroundedAt: backgroundedAt, now: Date(), isColdLaunch: coldLaunch),
              let effective = effectiveVaultTimeoutAction(
                  timeout: timeout, action: action, isBiometricLockEnabled: isBiometricLockEnabled)
        else { return }
        switch effective {
        case .lock:
            isLocked = true
        case .logOut:
            await VaultAccountModel(deviceLabel: "").logout()
            journalSync.unlinked()
            timeoutLogouts += 1
        }
    }

    // MARK: - Face ID

    /// Asks for Face ID (or the device passcode) and unlocks the vault screens on success.
    func unlock() async {
        if await authenticate(reason: Strings.active.vaultLockReason) { isLocked = false }
    }

    /// Turning the lock on needs one successful check, so nobody switches it on without being able to
    /// get back in. Turning it off also drops a lock action, so it never becomes a surprise logout.
    func setBiometricLock(_ enabled: Bool) async {
        if enabled {
            guard await authenticate(reason: Strings.active.vaultLockEnableReason) else { return }
            isBiometricLockEnabled = true
            action = .lock
        } else {
            isBiometricLockEnabled = false
            isLocked = false
            if action == .lock {
                action = .logOut
                timeout = .never
            }
        }
    }

    /// Nil when the phone has neither biometrics nor a passcode, so there is nothing to lock with.
    var biometryName: String? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return nil }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return Strings.active.vaultLockPasscode
        }
    }

    /// Forgets the lock along with the session (logout or erase on the vault screen).
    func signedOut() { isLocked = false }

    private var isLinked: Bool {
        VaultSessionStore(secrets: KeychainSecretStore.vaultSession).load() != nil
    }

    /// What asking the device owner to confirm an action gave.
    enum OwnerCheck { case passed, failed, unavailable }

    /// Face ID, Touch ID or the device passcode, for one sensitive action (a passphrase reset). Unlike the
    /// screen lock it is not optional: `unavailable` means the phone has no passcode, and the caller refuses.
    func confirmOwner(reason: String) async -> OwnerCheck {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return .unavailable }
        return await authenticate(reason: reason, context: context) ? .passed : .failed
    }

    private func authenticate(reason: String, context: LAContext = LAContext()) async -> Bool {
        // Biometrics with the device passcode as fallback: a failed Face ID must not lock someone out.
        (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
