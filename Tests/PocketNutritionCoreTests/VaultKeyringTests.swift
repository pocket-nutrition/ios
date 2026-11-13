// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

import PocketNutritionCore

@Suite("vault keyring and recovery key")
struct VaultKeyringTests {

    // MARK: Passphrase

    @Test("composed and decomposed accents derive from the same bytes")
    func normalisesAccents() {
        let composed = "caf\u{00E9} cr\u{00E8}me"
        let decomposed = "cafe\u{0301} cre\u{0300}me"
        #expect(Array(composed.utf8) != Array(decomposed.utf8))  // String == would call them equal
        #expect(normalizedVaultPassphrase(composed) == normalizedVaultPassphrase(decomposed))
    }

    @Test("compatibility forms fold, whitespace is kept")
    func compatibilityAndWhitespace() {
        #expect(normalizedVaultPassphrase("\u{FB01}sh") == normalizedVaultPassphrase("fish"))  // ﬁ ligature
        #expect(normalizedVaultPassphrase(" a ") != normalizedVaultPassphrase("a"))
        #expect(normalizedVaultPassphrase("abc") == Data("abc".utf8))
    }

    // MARK: Recovery key

    private let key = Data((0..<32).map { UInt8($0 * 7 & 255) })

    @Test("a recovery key round-trips through its display form")
    func roundTrip() throws {
        let text = VaultRecoveryKeyFormat.encode(key)
        #expect(text.count == 52 + 12)  // 52 characters plus 12 dashes
        #expect(text.split(separator: "-").allSatisfy { $0.count == 4 })
        #expect(VaultRecoveryKeyFormat.decode(text) == key)
    }

    @Test("every possible byte value survives, including all zeros and all ones")
    func extremes() {
        for byte in [UInt8(0), 1, 127, 128, 255] {
            let value = Data(repeating: byte, count: 32)
            #expect(VaultRecoveryKeyFormat.decode(VaultRecoveryKeyFormat.encode(value)) == value)
        }
    }

    @Test("decoding ignores case, dashes and spaces")
    func tolerantDecoding() {
        let text = VaultRecoveryKeyFormat.encode(key)
        #expect(VaultRecoveryKeyFormat.decode(text.lowercased()) == key)
        #expect(VaultRecoveryKeyFormat.decode(text.replacingOccurrences(of: "-", with: " ")) == key)
        #expect(VaultRecoveryKeyFormat.decode(text.replacingOccurrences(of: "-", with: "")) == key)
        #expect(VaultRecoveryKeyFormat.decode("  " + text + "\n") == key)
    }

    @Test("wrong length, wrong alphabet and nonzero padding are refused")
    func refusesBadKeys() {
        let text = VaultRecoveryKeyFormat.encode(key)
        #expect(VaultRecoveryKeyFormat.decode("") == nil)
        #expect(VaultRecoveryKeyFormat.decode(String(text.dropLast(5))) == nil)
        #expect(VaultRecoveryKeyFormat.decode(text + "AAAA") == nil)
        #expect(VaultRecoveryKeyFormat.decode(text.replacingOccurrences(of: text.prefix(1), with: "1")) == nil)  // '1' is not Base32
        // Flip a bit in the 4 padding bits (the low bits of the last character).
        var characters = Array(text.replacingOccurrences(of: "-", with: ""))
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        let last = alphabet.firstIndex(of: characters[51])!
        characters[51] = alphabet[last | 1]
        #expect(VaultRecoveryKeyFormat.decode(String(characters)) == nil)
    }

    // MARK: Keyring blob

    private func blob() -> VaultKeyringBlob {
        VaultKeyringBlob(
            kdf: VaultKdf(salt: "AAAAAAAAAAAAAAAAAAAAAA==", opslimit: 3, memlimit: 67_108_864),
            passphraseWrappedUserKey: "cGFzcw==", recoveryWrappedUserKey: "cmVjb3Zlcnk=",
            inboxPublicKey: "cHVi", inboxWrappedSecretKey: "c2VjcmV0"
        )
    }

    @Test("the blob round-trips and uses the documented key names")
    func blobRoundTrip() throws {
        let text = try blob().encoded()
        #expect(VaultKeyringBlob.decode(text) == blob())
        let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(Set(object.keys) == [
            "v", "kdf", "passphrase_wrapped_user_key", "recovery_wrapped_user_key",
            "inbox_public_key", "inbox_wrapped_secret_key",
        ])
        #expect(object["v"] as? Int == 1)
    }

    @Test("encoding is stable, so two devices save the same bytes")
    func blobIsDeterministic() throws {
        #expect(try blob().encoded() == blob().encoded())
    }

    @Test("a future version or garbage does not decode")
    func blobRefusesUnknown() throws {
        let future = try blob().encoded().replacingOccurrences(of: "\"v\":1", with: "\"v\":2")
        #expect(VaultKeyringBlob.decode(future) == nil)
        #expect(VaultKeyringBlob.decode("not json") == nil)
        #expect(VaultKeyringBlob.decode("{}") == nil)
    }
}
