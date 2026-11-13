// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

import PocketNutritionCore
@testable import PocketNutritionVault

/// Known answers generated from libsodium by `pocket-nutrition-vault/scripts/gen_vectors.py`. Passing
/// these is what makes this client and every other one speak the same protocol.
private struct Vectors: Decodable {
    struct Kdf: Decodable {
        let passphraseUtf8: String, saltHex: String, opslimit: Int, memlimit: Int
        let masterKeyHex: String, authHashHex: String, authHashB64: String, wrapKeyHex: String
    }
    struct Aead: Decodable {
        let keyHex: String, nonceHex: String, aadUtf8: String, plaintextUtf8: String, ciphertextB64: String
    }
    struct Sealed: Decodable {
        let inboxPrivateKeyHex: String, inboxPublicKeyHex: String, plaintextUtf8: String, sealedB64: String
    }
    let kdf: Kdf
    let recordAead: Aead
    let sealedBox: Sealed

    static func load() throws -> Vectors {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("test-vectors.json")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Vectors.self, from: Data(contentsOf: url))
    }
}

private func data(hex: String) -> Data {
    var bytes: [UInt8] = []
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        bytes.append(UInt8(hex[index..<next], radix: 16)!)
        index = next
    }
    return Data(bytes)
}

@Suite("vault crypto")
struct VaultCryptoTests {

    private let crypto = VaultCrypto()

    // MARK: Cross-language vectors

    @Test("the passphrase derives the auth hash and wrap key libsodium produced")
    func kdfMatchesVectors() throws {
        let v = try Vectors.load().kdf
        let kdf = VaultKdf(salt: data(hex: v.saltHex).base64EncodedString(), opslimit: v.opslimit, memlimit: v.memlimit)
        let credentials = try crypto.credentials(passphrase: v.passphraseUtf8, kdf: kdf)
        #expect(credentials.authHash == data(hex: v.authHashHex))
        #expect(credentials.authHash.base64EncodedString() == v.authHashB64)
        #expect(credentials.wrapKey == data(hex: v.wrapKeyHex))
    }

    @Test("a record encrypted by another client decrypts here")
    func decryptsForeignRecord() throws {
        let v = try Vectors.load().recordAead
        let plaintext = try crypto.decrypt(v.ciphertextB64, key: data(hex: v.keyHex), aad: Data(v.aadUtf8.utf8))
        #expect(String(decoding: plaintext, as: UTF8.self) == v.plaintextUtf8)
    }

    @Test("a sealed box made by another client opens here")
    func opensForeignSealedBox() throws {
        let v = try Vectors.load().sealedBox
        let inbox = VaultCrypto.InboxKeyPair(publicKey: data(hex: v.inboxPublicKeyHex), secretKey: data(hex: v.inboxPrivateKeyHex))
        let plaintext = try crypto.openSealed(v.sealedB64, inbox: inbox)
        #expect(String(decoding: plaintext, as: UTF8.self) == v.plaintextUtf8)
        // And it is a payload the app accepts as a delivery for that record.
        #expect(throws: Never.self) { try decodeVaultDropPayload(plaintext, expectedRecordId: "cap-1") }
    }

    // MARK: Passphrase handling

    @Test("an accented passphrase derives without crashing, and composition does not matter")
    func accentedPassphrase() throws {
        let kdf = try crypto.newKdf()
        let composed = try crypto.credentials(passphrase: "caf\u{00E9} cr\u{00E8}me br\u{00FB}l\u{00E9}e", kdf: kdf)
        let decomposed = try crypto.credentials(passphrase: "cafe\u{0301} cre\u{0300}me bru\u{0302}le\u{0301}e", kdf: kdf)
        #expect(composed.authHash == decomposed.authHash)
        #expect(composed.wrapKey == decomposed.wrapKey)
    }

    @Test("different passphrases give different keys, and the two keys differ from each other")
    func derivationSeparation() throws {
        let kdf = try crypto.newKdf()
        let a = try crypto.credentials(passphrase: "alpha", kdf: kdf)
        let b = try crypto.credentials(passphrase: "bravo", kdf: kdf)
        #expect(a.authHash != b.authHash && a.wrapKey != b.wrapKey)
        #expect(a.authHash != a.wrapKey)
    }

    @Test("an empty passphrase is refused")
    func emptyPassphrase() throws {
        let kdf = try crypto.newKdf()
        #expect(throws: VaultCryptoError.derivationFailed) { try crypto.credentials(passphrase: "", kdf: kdf) }
    }

    @Test("KDF settings below the floor are never used")
    func weakKdfRefused() {
        let weak = VaultKdf(salt: Data(count: 16).base64EncodedString(), opslimit: 1, memlimit: 1024)
        #expect(throws: VaultCryptoError.unacceptableKdf) { try crypto.credentials(passphrase: "x", kdf: weak) }
    }

    // MARK: Records

    @Test("a record round-trips and each encryption uses a fresh nonce")
    func recordRoundTrip() throws {
        let key = try crypto.newKey()
        let aad = Data("pnv1|a|r|t||1|user".utf8)
        let plaintext = Data("{\"kcal\":420}".utf8)
        let first = try crypto.encrypt(plaintext, key: key, aad: aad)
        let second = try crypto.encrypt(plaintext, key: key, aad: aad)
        #expect(first != second)
        #expect(try crypto.decrypt(first, key: key, aad: aad) == plaintext)
    }

    @Test("a wrong key, wrong AAD or tampered ciphertext fails to decrypt")
    func recordTamper() throws {
        let key = try crypto.newKey()
        let aad = Data("pnv1|a|r|t||1|user".utf8)
        let sealed = try crypto.encrypt(Data("secret".utf8), key: key, aad: aad)

        #expect(throws: VaultCryptoError.decryptionFailed) { try crypto.decrypt(sealed, key: try crypto.newKey(), aad: aad) }
        #expect(throws: VaultCryptoError.decryptionFailed) { try crypto.decrypt(sealed, key: key, aad: Data("pnv1|a|r|t||2|user".utf8)) }

        var raw = try #require(Data(base64Encoded: sealed))
        raw[raw.count - 1] ^= 0x01
        #expect(throws: VaultCryptoError.decryptionFailed) { try crypto.decrypt(raw.base64EncodedString(), key: key, aad: aad) }
    }

    @Test("garbage input is rejected without crashing")
    func recordMalformed() throws {
        let key = try crypto.newKey()
        #expect(throws: VaultCryptoError.malformedInput) { try crypto.decrypt("not base64!", key: key, aad: Data()) }
        #expect(throws: VaultCryptoError.decryptionFailed) { try crypto.decrypt("AAAA", key: key, aad: Data()) }
        #expect(throws: VaultCryptoError.malformedInput) { try crypto.encrypt(Data(), key: Data(count: 5), aad: Data()) }
    }

    // MARK: Sealed boxes

    @Test("a sealed box opens only with the matching inbox key")
    func sealedRoundTrip() throws {
        let inbox = try crypto.newInboxKeyPair()
        let sealed = try crypto.seal(Data("hello".utf8), to: inbox.publicKey)
        #expect(try crypto.openSealed(sealed, inbox: inbox) == Data("hello".utf8))
        let stranger = try crypto.newInboxKeyPair()
        #expect(throws: VaultCryptoError.decryptionFailed) { try crypto.openSealed(sealed, inbox: stranger) }
    }

    // MARK: Accounts

    @Test("a new account unlocks with its passphrase and with its recovery key, to the same keys")
    func accountLifecycle() throws {
        let account = try crypto.createAccount(passphrase: "correct horse battery staple")
        let blob = try #require(VaultKeyringBlob.decode(account.keyringBlob))

        let credentials = try crypto.credentials(passphrase: "correct horse battery staple", kdf: blob.kdf)
        #expect(credentials.authHash.base64EncodedString() == account.authHash)

        let byPassphrase = try crypto.unlock(keyring: blob, credentials: credentials)
        let byRecovery = try crypto.unlock(keyring: blob, recoveryKey: account.recoveryKey)
        #expect(byPassphrase == account.keys)
        #expect(byRecovery == account.keys)
    }

    @Test("the wrong passphrase cannot open the keyring")
    func wrongPassphrase() throws {
        let account = try crypto.createAccount(passphrase: "right passphrase")
        let blob = try #require(VaultKeyringBlob.decode(account.keyringBlob))
        let wrong = try crypto.credentials(passphrase: "wrong passphrase", kdf: blob.kdf)
        #expect(throws: VaultCryptoError.decryptionFailed) { try crypto.unlock(keyring: blob, credentials: wrong) }
    }

    @Test("a wrong or malformed recovery key is refused")
    func wrongRecoveryKey() throws {
        let account = try crypto.createAccount(passphrase: "right passphrase")
        let blob = try #require(VaultKeyringBlob.decode(account.keyringBlob))
        let other = VaultRecoveryKeyFormat.encode(try crypto.newKey())
        #expect(throws: VaultCryptoError.decryptionFailed) { try crypto.unlock(keyring: blob, recoveryKey: other) }
        #expect(throws: VaultCryptoError.malformedInput) { try crypto.unlock(keyring: blob, recoveryKey: "nonsense") }
    }

    @Test("the passphrase copy of the user key cannot be opened as the recovery copy")
    func purposesAreBound() throws {
        let account = try crypto.createAccount(passphrase: "right passphrase")
        let blob = try #require(VaultKeyringBlob.decode(account.keyringBlob))
        let credentials = try crypto.credentials(passphrase: "right passphrase", kdf: blob.kdf)
        #expect(throws: VaultCryptoError.decryptionFailed) {
            try crypto.decrypt(blob.passphraseWrappedUserKey, key: credentials.wrapKey, aad: vaultKeyringAAD(.recovery))
        }
    }

    @Test("the registered auth hash and recovery key are fresh per account")
    func accountsDiffer() throws {
        let a = try crypto.createAccount(passphrase: "same passphrase")
        let b = try crypto.createAccount(passphrase: "same passphrase")
        #expect(a.authHash != b.authHash)  // different random salt
        #expect(a.recoveryKey != b.recoveryKey)
    }

    // MARK: Inbox public key authenticity

    @Test("the inbox public key is derived from the secret key")
    func derivesInboxPublicKey() throws {
        let pair = try crypto.newInboxKeyPair()
        #expect(try crypto.inboxPublicKey(for: pair.secretKey) == pair.publicKey)
        let v = try Vectors.load().sealedBox
        #expect(try crypto.inboxPublicKey(for: data(hex: v.inboxPrivateKeyHex)) == data(hex: v.inboxPublicKeyHex))
    }

    @Test("a keyring whose inbox public key was swapped is refused")
    func swappedInboxKeyIsRefused() throws {
        let account = try crypto.createAccount(passphrase: "right passphrase")
        let honest = try #require(VaultKeyringBlob.decode(account.keyringBlob))
        let attacker = try crypto.newInboxKeyPair()
        let forged = VaultKeyringBlob(
            kdf: honest.kdf, passphraseWrappedUserKey: honest.passphraseWrappedUserKey,
            recoveryWrappedUserKey: honest.recoveryWrappedUserKey,
            inboxPublicKey: attacker.publicKey.base64EncodedString(),
            inboxWrappedSecretKey: honest.inboxWrappedSecretKey)

        let credentials = try crypto.credentials(passphrase: "right passphrase", kdf: honest.kdf)
        #expect(throws: VaultCryptoError.inboxKeyMismatch) { try crypto.unlock(keyring: forged, credentials: credentials) }
        #expect(throws: VaultCryptoError.inboxKeyMismatch) {
            try crypto.unlock(keyring: forged, recoveryKey: account.recoveryKey)
        }
    }

    @Test("an unlocked account always hands out the derived public key")
    func unlockedPublicKeyIsDerived() throws {
        let account = try crypto.createAccount(passphrase: "right passphrase")
        let blob = try #require(VaultKeyringBlob.decode(account.keyringBlob))
        let keys = try crypto.unlock(
            keyring: blob, credentials: try crypto.credentials(passphrase: "right passphrase", kdf: blob.kdf))
        #expect(keys.inbox.publicKey == (try crypto.inboxPublicKey(for: keys.inbox.secretKey)))
    }

    @Test("a reset keyring: same user key under a new passphrase and recovery key, inbox untouched")
    func resetKeyring() throws {
        let crypto = VaultCrypto()
        let account = try crypto.createAccount(passphrase: "correct horse battery staple")
        let old = try #require(VaultKeyringBlob.decode(account.keyringBlob))
        let newPassphrase = "maple-orbit-fjord-lantern-cobalt"

        let reset = try crypto.resetKeyring(keyring: old, userKey: account.keys.userKey, newPassphrase: newPassphrase)
        let blob = try #require(VaultKeyringBlob.decode(reset.keyringBlob))

        #expect(blob.kdf == reset.kdf)
        #expect(blob.kdf.salt != old.kdf.salt)
        #expect(blob.inboxPublicKey == old.inboxPublicKey)
        #expect(blob.inboxWrappedSecretKey == old.inboxWrappedSecretKey)
        // Same shape as registration writes: sorted keys, re-encoding is byte-identical.
        #expect(try blob.encoded() == reset.keyringBlob)
        let keys = try JSONSerialization.jsonObject(with: Data(reset.keyringBlob.utf8)) as? [String: Any]
        let registered = try JSONSerialization.jsonObject(with: Data(account.keyringBlob.utf8)) as? [String: Any]
        #expect(keys.map { Set($0.keys) } == registered.map { Set($0.keys) })

        let credentials = try crypto.credentials(passphrase: newPassphrase, kdf: reset.kdf)
        #expect(credentials.authHash.base64EncodedString() == reset.authHash)
        #expect(try crypto.unlock(keyring: blob, credentials: credentials) == account.keys)
        #expect(try crypto.unlock(keyring: blob, recoveryKey: reset.recoveryKey) == account.keys)
        #expect(throws: VaultCryptoError.decryptionFailed) {
            try crypto.unlock(keyring: blob, recoveryKey: account.recoveryKey)
        }
        #expect(throws: VaultCryptoError.decryptionFailed) {
            try crypto.unlock(
                keyring: blob,
                credentials: crypto.credentials(passphrase: "correct horse battery staple", kdf: blob.kdf))
        }
    }

    @Test("a reset refuses a user key that does not open the keyring's inbox")
    func resetKeyringWrongUserKey() throws {
        let crypto = VaultCrypto()
        let account = try crypto.createAccount(passphrase: "correct horse battery staple")
        let old = try #require(VaultKeyringBlob.decode(account.keyringBlob))
        #expect(throws: VaultCryptoError.decryptionFailed) {
            try crypto.resetKeyring(keyring: old, userKey: try crypto.newKey(), newPassphrase: "maple-orbit-fjord-lantern")
        }
    }
}
