// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

@testable import PocketNutritionCore

@Suite("vault security rules")
struct VaultSecurityTests {

    @Test("new error slugs get their own meaning")
    func classify() {
        #expect(classifyVaultHTTP(status: 401, errorCode: "two_factor_required", isLogin: true) == .twoFactorRequired)
        #expect(classifyVaultHTTP(status: 401, errorCode: "invalid_two_factor", isLogin: true) == .invalidTwoFactor)
        #expect(classifyVaultHTTP(status: 401, errorCode: "invalid_credentials") == .invalidCredentials)
        #expect(classifyVaultHTTP(status: 401, errorCode: nil) == .unauthorized)
        #expect(classifyVaultHTTP(status: 400, errorCode: "invalid_code") == .invalidCode)
        #expect(classifyVaultHTTP(status: 409, errorCode: "keyring_conflict") == .keyringConflict)
        #expect(classifyVaultHTTP(status: 409, errorCode: "no_passphrase") == .noPassphrase)
        #expect(classifyVaultHTTP(status: 409, errorCode: "no_pending_setup") == .twoFactorStateChanged)
        #expect(classifyVaultHTTP(status: 409, errorCode: "something_else") == .other(409))
    }

    @Test("a code is six digits or a recovery code, nothing else")
    func twoFactorCode() {
        #expect(VaultTwoFactorCode("123 456") == .totp("123456"))
        #expect(VaultTwoFactorCode("ABCD-efgh-2345") == .recovery("abcdefgh2345"))
        #expect(VaultTwoFactorCode("12345") == nil)
        #expect(VaultTwoFactorCode("abcd-efgh-1234") == nil)  // 1 is not in the base32 alphabet
        #expect(VaultTwoFactorCode("") == nil)
    }

    @Test("the login request only carries a code when there is one")
    func loginRequestJSON() throws {
        let plain = try JSONEncoder().encode(VaultLoginRequest(username: "a", authHash: "h", deviceLabel: "d"))
        let plainObject = try #require(try JSONSerialization.jsonObject(with: plain) as? [String: Any])
        #expect(plainObject["totp_code"] == nil)
        #expect(plainObject["recovery_code"] == nil)

        let withCode = try JSONEncoder().encode(
            VaultLoginRequest(username: "a", authHash: "h", deviceLabel: "d", twoFactor: .recovery("abcdefgh2345")))
        let object = try #require(try JSONSerialization.jsonObject(with: withCode) as? [String: Any])
        #expect(object["recovery_code"] as? String == "abcdefgh2345")
        #expect(object["totp_code"] == nil)
    }

    @Test("fingerprint words come from the EFF list, one per 32-bit chunk")
    func fingerprintWords() throws {
        let words = try #require(vaultFingerprintWords(digest: Data(repeating: 0, count: 32)))
        #expect(words == Array(repeating: EffLongWordlist.words[0], count: 5))
        // 0x00001E60 = 7776 wraps to the first word; 0x00001E61 to the second.
        let digest = Data([0, 0, 0x1E, 0x60, 0, 0, 0x1E, 0x61] + Array(repeating: 0, count: 24))
        let mixed = try #require(vaultFingerprintWords(digest: digest))
        #expect(mixed[0] == EffLongWordlist.words[0])
        #expect(mixed[1] == EffLongWordlist.words[1])
        #expect(vaultFingerprintWords(digest: Data(count: 19)) == nil)
    }

    @Test("server timestamps parse with or without fractions and offset")
    func timestamps() {
        #expect(parseVaultTimestamp("2026-11-01T10:00:00.123456Z") != nil)
        #expect(parseVaultTimestamp("2026-11-01T10:00:00+00:00") != nil)
        #expect(parseVaultTimestamp("2026-11-01T10:00:00") != nil)
        #expect(parseVaultTimestamp("yesterday") == nil)
    }

    @Test("session expiry follows the chosen delay")
    func expiry() {
        let now = Date(timeIntervalSince1970: 10_000)
        let fourMinutesAgo = now.addingTimeInterval(-240)
        #expect(!isVaultSessionExpired(timeout: .never, backgroundedAt: .distantPast, now: now, isColdLaunch: true))
        #expect(isVaultSessionExpired(timeout: .onRestart, backgroundedAt: now, now: now, isColdLaunch: true))
        #expect(!isVaultSessionExpired(timeout: .onRestart, backgroundedAt: .distantPast, now: now, isColdLaunch: false))
        #expect(isVaultSessionExpired(timeout: .immediately, backgroundedAt: now, now: now, isColdLaunch: false))
        #expect(!isVaultSessionExpired(timeout: .fiveMinutes, backgroundedAt: fourMinutesAgo, now: now, isColdLaunch: false))
        #expect(isVaultSessionExpired(timeout: .oneMinute, backgroundedAt: fourMinutesAgo, now: now, isColdLaunch: false))
        #expect(isVaultSessionExpired(timeout: .fiveMinutes, backgroundedAt: nil, now: now, isColdLaunch: true))
        #expect(!isVaultSessionExpired(timeout: .fiveMinutes, backgroundedAt: nil, now: now, isColdLaunch: false))
    }

    @Test("a lock without Face ID does nothing instead of logging out")
    func effectiveAction() {
        #expect(effectiveVaultTimeoutAction(timeout: .oneHour, action: .lock, isBiometricLockEnabled: true) == .lock)
        #expect(effectiveVaultTimeoutAction(timeout: .oneHour, action: .lock, isBiometricLockEnabled: false) == nil)
        #expect(effectiveVaultTimeoutAction(timeout: .oneHour, action: .logOut, isBiometricLockEnabled: false) == .logOut)
        #expect(effectiveVaultTimeoutAction(timeout: .never, action: .logOut, isBiometricLockEnabled: true) == nil)
    }
}
