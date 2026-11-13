// SPDX-License-Identifier: MPL-2.0

import Foundation

// The account's wrapped keys and the formats a person sees or types. No cryptography here: the
// bytes are produced and opened by `PocketNutritionVault`.

/// The passphrase exactly as it must be fed to the KDF. NFKC makes "é" typed as one character and as
/// "e" + a combining accent derive the same key, which differs between keyboards and between iOS and
/// Android. Whitespace is NOT trimmed: it is part of what the person chose.
public func normalizedVaultPassphrase(_ raw: String) -> Data {
    Data(raw.precomposedStringWithCompatibilityMapping.utf8)
}

/// The stored `keyring` blob (the server keeps it verbatim and never parses it). Everything secret in
/// it is wrapped; `inboxPublicKey` is public by design, it is what drops are sealed to.
public struct VaultKeyringBlob: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let kdf: VaultKdf
    /// Base64 `nonce || AEAD`: the user key, wrapped by the passphrase-derived wrap key.
    public let passphraseWrappedUserKey: String
    /// The same user key, wrapped by the recovery key.
    public let recoveryWrappedUserKey: String
    /// Base64 X25519 public key.
    public let inboxPublicKey: String
    /// The inbox secret key, wrapped by the user key so every device can open drops.
    public let inboxWrappedSecretKey: String

    public init(
        kdf: VaultKdf, passphraseWrappedUserKey: String, recoveryWrappedUserKey: String,
        inboxPublicKey: String, inboxWrappedSecretKey: String
    ) {
        version = Self.currentVersion
        self.kdf = kdf
        self.passphraseWrappedUserKey = passphraseWrappedUserKey
        self.recoveryWrappedUserKey = recoveryWrappedUserKey
        self.inboxPublicKey = inboxPublicKey
        self.inboxWrappedSecretKey = inboxWrappedSecretKey
    }

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case kdf
        case passphraseWrappedUserKey = "passphrase_wrapped_user_key"
        case recoveryWrappedUserKey = "recovery_wrapped_user_key"
        case inboxPublicKey = "inbox_public_key"
        case inboxWrappedSecretKey = "inbox_wrapped_secret_key"
    }

    /// The compact JSON the server stores.
    public func encoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    /// Nil for anything that is not a version this build understands.
    public static func decode(_ blob: String) -> VaultKeyringBlob? {
        guard let parsed = try? JSONDecoder().decode(VaultKeyringBlob.self, from: Data(blob.utf8)),
              parsed.version == currentVersion
        else { return nil }
        return parsed
    }
}

/// How the 32-byte recovery key is shown and typed: RFC 4648 Base32 in groups of four,
/// `ABCD-EFGH-…` (52 characters, 13 groups). Decoding ignores case, dashes and spaces, so it survives
/// being copied through a note, a printout or a password manager.
public enum VaultRecoveryKeyFormat {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    public static func encode(_ key: Data) -> String {
        var output: [Character] = []
        var buffer = 0
        var bits = 0
        for byte in key {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                output.append(alphabet[(buffer >> (bits - 5)) & 31])
                bits -= 5
            }
            buffer &= (1 << bits) - 1
        }
        if bits > 0 { output.append(alphabet[(buffer << (5 - bits)) & 31]) }
        return stride(from: 0, to: output.count, by: 4)
            .map { String(output[$0..<min($0 + 4, output.count)]) }
            .joined(separator: "-")
    }

    /// The key bytes, or nil if the text is not a valid 32-byte recovery key.
    public static func decode(_ text: String) -> Data? {
        let cleaned = text.uppercased().filter { $0 != "-" && !$0.isWhitespace }
        guard cleaned.count == 52 else { return nil }
        var bytes: [UInt8] = []
        var buffer = 0
        var bits = 0
        for character in cleaned {
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            buffer = (buffer << 5) | value
            bits += 5
            if bits >= 8 {
                bytes.append(UInt8((buffer >> (bits - 8)) & 255))
                bits -= 8
                buffer &= (1 << bits) - 1
            }
        }
        // 52 characters carry 260 bits: 256 of key plus 4 bits of padding, which must be zero.
        guard bytes.count == VaultProtocol.keyBytes, buffer == 0 else { return nil }
        return Data(bytes)
    }
}
