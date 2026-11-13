// SPDX-License-Identifier: MPL-2.0

import Foundation
import PocketNutritionCore
import Sodium

/// The keys a device holds while the vault is unlocked. Never persisted as-is: the Keychain stores them
/// under the device's own protection, and the server only ever sees them wrapped.
public struct VaultUnlockedKeys: Sendable, Equatable {
    public let userKey: Data
    public let inbox: VaultCrypto.InboxKeyPair

    public init(userKey: Data, inbox: VaultCrypto.InboxKeyPair) {
        self.userKey = userKey
        self.inbox = inbox
    }
}

/// Everything a brand-new account needs to register, plus what the person must be shown once.
public struct VaultNewAccount: Sendable {
    public let kdf: VaultKdf
    /// Base64, as the server expects it.
    public let authHash: String
    /// The `keyring` string to send.
    public let keyringBlob: String
    /// The recovery key in its display form. Shown exactly once; the server cannot recover it.
    public let recoveryKey: String
    public let keys: VaultUnlockedKeys
}

/// A keyring rebuilt for a forgotten passphrase, ready for `POST /v1/account/passphrase/reset`.
public struct VaultResetKeyring: Sendable {
    public let kdf: VaultKdf
    /// Base64, as the server expects it.
    public let authHash: String
    public let keyringBlob: String
    /// The new recovery key in its display form. Shown once, in the emergency kit.
    public let recoveryKey: String
}

extension VaultCrypto {

    /// Builds a new account's keys: a random user key and inbox keypair, wrapped by the passphrase and by
    /// a fresh recovery key. Slow (Argon2id): call it off the main thread.
    public func createAccount(passphrase: String) throws(VaultCryptoError) -> VaultNewAccount {
        let kdf = try newKdf()
        let credentials = try credentials(passphrase: passphrase, kdf: kdf)
        let userKey = try newKey()
        let recoveryKey = try newKey()
        let inbox = try newInboxKeyPair()

        let blob = VaultKeyringBlob(
            kdf: kdf,
            passphraseWrappedUserKey: try encrypt(userKey, key: credentials.wrapKey, aad: vaultKeyringAAD(.passphrase)),
            recoveryWrappedUserKey: try encrypt(userKey, key: recoveryKey, aad: vaultKeyringAAD(.recovery)),
            inboxPublicKey: inbox.publicKey.base64EncodedString(),
            inboxWrappedSecretKey: try encrypt(inbox.secretKey, key: userKey, aad: vaultKeyringAAD(.inbox))
        )
        guard let encoded = try? blob.encoded() else { throw .malformedInput }
        return VaultNewAccount(
            kdf: kdf,
            authHash: credentials.authHash.base64EncodedString(),
            keyringBlob: encoded,
            recoveryKey: VaultRecoveryKeyFormat.encode(recoveryKey),
            keys: VaultUnlockedKeys(userKey: userKey, inbox: inbox)
        )
    }

    /// Opens a stored keyring with the passphrase-derived wrap key (the normal login path).
    public func unlock(
        keyring blob: VaultKeyringBlob, credentials: VaultCredentials
    ) throws(VaultCryptoError) -> VaultUnlockedKeys {
        let userKey = try decrypt(
            blob.passphraseWrappedUserKey, key: credentials.wrapKey, aad: vaultKeyringAAD(.passphrase))
        return try openInbox(of: blob, userKey: userKey)
    }

    /// Opens a stored keyring with the printed recovery key (the forgot-passphrase path).
    public func unlock(
        keyring blob: VaultKeyringBlob, recoveryKey: String
    ) throws(VaultCryptoError) -> VaultUnlockedKeys {
        guard let key = VaultRecoveryKeyFormat.decode(recoveryKey) else { throw .malformedInput }
        let userKey = try decrypt(blob.recoveryWrappedUserKey, key: key, aad: vaultKeyringAAD(.recovery))
        return try openInbox(of: blob, userKey: userKey)
    }

    /// A keyring for a forgotten passphrase, built on a device that still holds the user key: the SAME user
    /// key wrapped under a new passphrase (fresh salt) and a NEW recovery key, with the inbox fields copied as
    /// they are. The old recovery key stops working once the server stores it.
    ///
    /// `userKey` must be the key the current keyring was built around: it has to open the inbox secret key
    /// and give back the stored inbox public key, or the reset is refused rather than strand every record.
    /// Slow (Argon2id): call it off the main thread.
    public func resetKeyring(
        keyring blob: VaultKeyringBlob, userKey: Data, newPassphrase: String
    ) throws(VaultCryptoError) -> VaultResetKeyring {
        _ = try openInbox(of: blob, userKey: userKey)
        let kdf = try newKdf()
        let credentials = try credentials(passphrase: newPassphrase, kdf: kdf)
        let recoveryKey = try newKey()
        let reset = VaultKeyringBlob(
            kdf: kdf,
            passphraseWrappedUserKey: try encrypt(userKey, key: credentials.wrapKey, aad: vaultKeyringAAD(.passphrase)),
            recoveryWrappedUserKey: try encrypt(userKey, key: recoveryKey, aad: vaultKeyringAAD(.recovery)),
            inboxPublicKey: blob.inboxPublicKey,
            inboxWrappedSecretKey: blob.inboxWrappedSecretKey
        )
        guard let encoded = try? reset.encoded() else { throw .malformedInput }
        return VaultResetKeyring(
            kdf: kdf, authHash: credentials.authHash.base64EncodedString(), keyringBlob: encoded,
            recoveryKey: VaultRecoveryKeyFormat.encode(recoveryKey))
    }

    /// The five-word fingerprint phrase of an account's keys (see `vaultFingerprintWords`).
    public func fingerprintPhrase(accountId: String, inboxPublicKey: Data) -> [String]? {
        let input = vaultFingerprintInput(accountId: accountId, inboxPublicKey: inboxPublicKey)
        guard let digest = Sodium().genericHash.hash(message: [UInt8](input), outputLength: 32) else { return nil }
        return vaultFingerprintWords(digest: Data(digest))
    }

    private func openInbox(of blob: VaultKeyringBlob, userKey: Data) throws(VaultCryptoError) -> VaultUnlockedKeys {
        let secret = try decrypt(blob.inboxWrappedSecretKey, key: userKey, aad: vaultKeyringAAD(.inbox))
        // The public key in the blob is NOT authenticated (only the secret key is wrapped). A malicious server
        // could swap it for its own, so the phone would seal every drop to the server. Derive it from the
        // secret instead, and refuse a keyring whose stored value disagrees.
        let derived = try inboxPublicKey(for: secret)
        guard let stored = Data(base64Encoded: blob.inboxPublicKey), stored == derived else {
            throw .inboxKeyMismatch
        }
        return VaultUnlockedKeys(userKey: userKey, inbox: InboxKeyPair(publicKey: derived, secretKey: secret))
    }
}
