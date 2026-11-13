// SPDX-License-Identifier: MPL-2.0

import Foundation
import PocketNutritionCore
import Sodium
import _Clibsodium

public enum VaultCryptoError: Error, Equatable, Sendable {
    /// The KDF settings are below the floor, or malformed. Never derive keys with them.
    case unacceptableKdf
    case derivationFailed
    /// Wrong key, a tampered ciphertext, or AAD that does not match: indistinguishable on purpose.
    case decryptionFailed
    case malformedInput
    case randomnessUnavailable
    /// The keyring's inbox public key is not the one its secret key produces: a swapped key.
    case inboxKeyMismatch
}

/// The two values a passphrase yields. `authHash` goes to the server; `wrapKey` never leaves the device.
public struct VaultCredentials: Sendable {
    public let authHash: Data
    public let wrapKey: Data
}

/// libsodium primitives, exactly as `docs/PROTOCOL.md` specifies them. Stateless and `Sendable`.
///
///     master_key = Argon2id(passphrase, kdf.salt, opslimit, memlimit)            32 bytes
///     auth_hash  = crypto_kdf(master_key, id 1, ctx "pnvauth1")
///     wrap_key   = crypto_kdf(master_key, id 2, ctx "pnvwrap1")
///     records    = XChaCha20-Poly1305, base64(nonce[24] || ciphertext), AAD bound per record
///     drops      = crypto_box_seal to the inbox public key
public struct VaultCrypto: Sendable {

    static let authContext = "pnvauth1"
    static let wrapContext = "pnvwrap1"

    /// `Sodium` is not `Sendable`, and it is a cheap value, so each call makes its own.
    private var sodium: Sodium { Sodium() }

    public init() {}

    // MARK: Randomness

    public func randomBytes(_ count: Int) throws(VaultCryptoError) -> Data {
        guard let bytes = sodium.randomBytes.buf(length: count) else { throw .randomnessUnavailable }
        return Data(bytes)
    }

    /// Fresh KDF settings for a new account: a random salt and the app's default cost.
    public func newKdf() throws(VaultCryptoError) -> VaultKdf {
        VaultKdf(
            salt: try randomBytes(VaultProtocol.kdfSaltBytes).base64EncodedString(),
            opslimit: VaultProtocol.defaultKdfOpsLimit,
            memlimit: VaultProtocol.defaultKdfMemLimit
        )
    }

    // MARK: Passphrase

    /// Derives the login hash and the wrap key. Refuses KDF settings below the floor, so a hostile server
    /// cannot weaken the derivation. Slow and memory-hungry by design: call it off the main thread.
    public func credentials(passphrase: String, kdf: VaultKdf) throws(VaultCryptoError) -> VaultCredentials {
        guard isAcceptableVaultKdf(kdf), let salt = Data(base64Encoded: kdf.salt) else { throw .unacceptableKdf }
        guard let master = Self.argon2id(
            sodium: sodium, passphrase: normalizedVaultPassphrase(passphrase), salt: salt,
            opsLimit: kdf.opslimit, memLimit: kdf.memlimit
        ) else { throw .derivationFailed }
        guard let auth = sodium.keyDerivation.derive(
                  secretKey: master, index: 1, length: VaultProtocol.authHashBytes, context: Self.authContext),
              let wrap = sodium.keyDerivation.derive(
                  secretKey: master, index: 2, length: VaultProtocol.keyBytes, context: Self.wrapContext)
        else { throw .derivationFailed }
        return VaultCredentials(authHash: Data(auth), wrapKey: Data(wrap))
    }

    /// Argon2id through libsodium's C function directly: swift-sodium's wrapper converts the password
    /// with `Int8.init`, which traps on any byte above 127, and a French passphrase is full of them.
    private static func argon2id(
        sodium: Sodium, passphrase: Data, salt: Data, opsLimit: Int, memLimit: Int
    ) -> [UInt8]? {
        // An empty passphrase would derive a valid-looking key from nothing: refuse it here as well as in the UI.
        guard salt.count == sodium.pwHash.SaltBytes, !passphrase.isEmpty else { return nil }
        var output = [UInt8](repeating: 0, count: VaultProtocol.keyBytes)
        let status = passphrase.withUnsafeBytes { raw -> Int32 in
            let password = raw.bindMemory(to: CChar.self)
            return crypto_pwhash(
                &output, UInt64(output.count), password.baseAddress!, UInt64(password.count),
                [UInt8](salt), UInt64(opsLimit), memLimit, crypto_pwhash_ALG_ARGON2ID13
            )
        }
        return status == 0 ? output : nil
    }

    // MARK: Symmetric encryption

    public func newKey() throws(VaultCryptoError) -> Data {
        try randomBytes(VaultProtocol.keyBytes)
    }

    /// `base64(nonce || ciphertext)`; a fresh random nonce every time.
    public func encrypt(_ plaintext: Data, key: Data, aad: Data) throws(VaultCryptoError) -> String {
        guard key.count == VaultProtocol.keyBytes else { throw .malformedInput }
        // Two overloads exist; this is the one returning `nonce || ciphertext` as a single array.
        let sealed: [UInt8]? = sodium.aead.xchacha20poly1305ietf.encrypt(
            message: [UInt8](plaintext), secretKey: [UInt8](key), additionalData: [UInt8](aad))
        guard let sealed else { throw .malformedInput }
        return Data(sealed).base64EncodedString()
    }

    public func decrypt(_ ciphertext: String, key: Data, aad: Data) throws(VaultCryptoError) -> Data {
        guard key.count == VaultProtocol.keyBytes, let raw = Data(base64Encoded: ciphertext) else {
            throw .malformedInput
        }
        guard let plaintext = sodium.aead.xchacha20poly1305ietf.decrypt(
            nonceAndAuthenticatedCipherText: [UInt8](raw), secretKey: [UInt8](key), additionalData: [UInt8](aad))
        else { throw .decryptionFailed }
        return Data(plaintext)
    }

    // MARK: Sealed boxes (drops)

    public struct InboxKeyPair: Sendable, Equatable {
        public let publicKey: Data
        public let secretKey: Data

        public init(publicKey: Data, secretKey: Data) {
            self.publicKey = publicKey
            self.secretKey = secretKey
        }
    }

    public func newInboxKeyPair() throws(VaultCryptoError) -> InboxKeyPair {
        guard let pair = sodium.box.keyPair() else { throw .randomnessUnavailable }
        return InboxKeyPair(publicKey: Data(pair.publicKey), secretKey: Data(pair.secretKey))
    }

    public func seal(_ plaintext: Data, to publicKey: Data) throws(VaultCryptoError) -> String {
        guard let sealed = sodium.box.seal(message: [UInt8](plaintext), recipientPublicKey: [UInt8](publicKey)) else {
            throw .malformedInput
        }
        return Data(sealed).base64EncodedString()
    }

    /// The public key an X25519 secret key belongs to.
    public func inboxPublicKey(for secretKey: Data) throws(VaultCryptoError) -> Data {
        guard secretKey.count == VaultProtocol.keyBytes else { throw .malformedInput }
        var publicKey = [UInt8](repeating: 0, count: VaultProtocol.keyBytes)
        guard crypto_scalarmult_base(&publicKey, [UInt8](secretKey)) == 0 else { throw .derivationFailed }
        return Data(publicKey)
    }

    public func openSealed(_ sealed: String, inbox: InboxKeyPair) throws(VaultCryptoError) -> Data {
        guard let raw = Data(base64Encoded: sealed) else { throw .malformedInput }
        guard let plaintext = sodium.box.open(
            anonymousCipherText: [UInt8](raw), recipientPublicKey: [UInt8](inbox.publicKey),
            recipientSecretKey: [UInt8](inbox.secretKey))
        else { throw .decryptionFailed }
        return Data(plaintext)
    }
}
