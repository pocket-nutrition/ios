// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

import PocketNutritionCore

// Hand-written against `pocket-nutrition-vault/docs/PROTOCOL.md`; the JSON samples are the shapes the
// deployed server returns.
@Suite("vault protocol")
struct VaultProtocolTests {

    // MARK: AAD

    @Test("the AAD is the documented pipe-separated layout")
    func aadLayout() {
        let aad = vaultRecordAAD(
            accountId: "acc-1", recordId: "rec-1", type: "capture", scopeId: nil, revision: 3, keyId: "user"
        )
        #expect(String(decoding: aad, as: UTF8.self) == "pnv1|acc-1|rec-1|capture||3|user")
    }

    @Test("a scope id is included, and every field changes the bytes")
    func aadBindsEveryField() {
        func aad(
            _ account: String = "a", _ record: String = "r", _ type: String = "t",
            _ scope: String? = nil, _ revision: Int = 1, _ key: String = "user"
        ) -> Data {
            vaultRecordAAD(accountId: account, recordId: record, type: type, scopeId: scope, revision: revision, keyId: key)
        }
        let base = aad()
        #expect(String(decoding: aad("a", "r", "t", "meals"), as: UTF8.self) == "pnv1|a|r|t|meals|1|user")
        #expect(aad("b") != base)
        #expect(aad("a", "x") != base)
        #expect(aad("a", "r", "u") != base)
        #expect(aad("a", "r", "t", "s") != base)
        #expect(aad("a", "r", "t", nil, 2) != base)
        #expect(aad("a", "r", "t", nil, 1, "inbox") != base)
    }

    // MARK: Username

    @Test("usernames are trimmed and lowercased", arguments: [("  Alice ", "alice"), ("BOB.smith", "bob.smith"), ("a-b_c.9", "a-b_c.9")])
    func normalisesUsernames(raw: String, expected: String) {
        #expect(normalizedVaultUsername(raw) == expected)
    }

    @Test("invalid usernames are rejected", arguments: ["ab", "", "has space", "-leading", ".dot", "a@b.c", "é-accent", String(repeating: "x", count: 65)])
    func rejectsUsernames(raw: String) {
        #expect(normalizedVaultUsername(raw) == nil)
    }

    @Test("the longest valid username is 64 characters")
    func usernameLimit() {
        #expect(normalizedVaultUsername(String(repeating: "x", count: 64)) != nil)
    }

    // MARK: Passphrase length

    @Test("twelve characters is the floor, counted as typed")
    func passphraseLength() {
        #expect(isAcceptableVaultPassphrase("123456789012"))
        #expect(!isAcceptableVaultPassphrase("12345678901"))
        #expect(!isAcceptableVaultPassphrase(""))
        // Twelve characters with accents, composed or decomposed, is still twelve characters.
        #expect(isAcceptableVaultPassphrase("\u{00E9}\u{00E8}\u{00E0}\u{00F9}\u{00E7}\u{00EA}\u{00EE}\u{00F4}\u{00FB}\u{00E2}\u{00EB}\u{00EF}"))
        #expect(isAcceptableVaultPassphrase("e\u{0301}e\u{0301}e\u{0301}e\u{0301}e\u{0301}e\u{0301}e\u{0301}e\u{0301}e\u{0301}e\u{0301}e\u{0301}e\u{0301}"))
        #expect(!isAcceptableVaultPassphrase("e\u{0301}e\u{0301}e\u{0301}e\u{0301}e\u{0301}e\u{0301}e\u{0301}e\u{0301}e\u{0301}e\u{0301}e\u{0301}"))
    }

    // MARK: Server URL

    @Test("only plain https host URLs are accepted", arguments: [
        "https://vault.pocketnutrition.org", "  https://vault.example.org/vault  ", "HTTPS://Example.org",
    ])
    func acceptsURLs(raw: String) {
        #expect(validatedVaultServerURL(raw) != nil)
    }

    @Test("http, credentials, queries and junk are refused", arguments: [
        "http://vault.example.org", "https://user:pw@example.org", "https://example.org?x=1",
        "https://example.org#frag", "ftp://example.org", "example.org", "", "   ", "https://",
    ])
    func rejectsURLs(raw: String) {
        #expect(validatedVaultServerURL(raw) == nil)
    }

    @Test("endpoint URLs append /v1 to the server path, keeping a self-hosted prefix")
    func buildsURLs() throws {
        let plain = try #require(URL(string: "https://vault.pocketnutrition.org"))
        #expect(vaultURL(base: plain, segments: ["login"])?.absoluteString == "https://vault.pocketnutrition.org/v1/login")

        let prefixed = try #require(URL(string: "https://example.org/vault/"))
        #expect(vaultURL(base: prefixed, segments: ["records", "r1"])?.absoluteString == "https://example.org/vault/v1/records/r1")

        let sync = vaultURL(base: plain, segments: ["sync"], query: [URLQueryItem(name: "since", value: "7")])
        #expect(sync?.absoluteString == "https://vault.pocketnutrition.org/v1/sync?since=7")
    }

    // MARK: KDF floor

    private func kdf(
        alg: String = "argon2id", salt: Data = Data(repeating: 1, count: 16),
        ops: Int = 3, mem: Int = 64 * 1024 * 1024
    ) -> VaultKdf {
        VaultKdf(alg: alg, salt: salt.base64EncodedString(), opslimit: ops, memlimit: mem)
    }

    @Test("settings at or above the floor are accepted")
    func acceptsKdf() {
        #expect(isAcceptableVaultKdf(kdf()))
        #expect(isAcceptableVaultKdf(kdf(ops: 3, mem: 64 * 1024 * 1024)))
        #expect(isAcceptableVaultKdf(kdf(ops: 10, mem: 1024 * 1024 * 1024)))
    }

    @Test("a server cannot downgrade the KDF")
    func rejectsWeakKdf() {
        #expect(!isAcceptableVaultKdf(kdf(ops: 2)))
        #expect(!isAcceptableVaultKdf(kdf(mem: 32 * 1024 * 1024)))
        #expect(!isAcceptableVaultKdf(kdf(ops: 1)))
        #expect(!isAcceptableVaultKdf(kdf(mem: 1024)))
        #expect(!isAcceptableVaultKdf(kdf(mem: 4 * 1024 * 1024 * 1024)))
        #expect(!isAcceptableVaultKdf(kdf(alg: "pbkdf2")))
        #expect(!isAcceptableVaultKdf(kdf(salt: Data(repeating: 1, count: 8))))
        #expect(!isAcceptableVaultKdf(VaultKdf(salt: "not base64!", opslimit: 3, memlimit: 64 * 1024 * 1024)))
    }

    // MARK: HTTP outcomes

    @Test("status codes map to meanings")
    func classifies() {
        #expect(classifyVaultHTTP(status: 200) == .success)
        #expect(classifyVaultHTTP(status: 201) == .success)
        #expect(classifyVaultHTTP(status: 401) == .unauthorized)
        #expect(classifyVaultHTTP(status: 401, isLogin: true) == .invalidCredentials)
        #expect(classifyVaultHTTP(status: 409, errorCode: "username_taken") == .usernameTaken)
        #expect(classifyVaultHTTP(status: 409, errorCode: "revision_conflict") == .revisionConflict)
        #expect(classifyVaultHTTP(status: 403, errorCode: "registration_closed") == .registrationClosed)
        #expect(classifyVaultHTTP(status: 413, errorCode: "quota_exceeded") == .quotaExceeded)
        #expect(classifyVaultHTTP(status: 429, retryAfter: "42") == .tooManyAttempts(retryAfter: 42))
        #expect(classifyVaultHTTP(status: 429) == .tooManyAttempts(retryAfter: nil))
        #expect(classifyVaultHTTP(status: 503) == .serverError)
        #expect(classifyVaultHTTP(status: 404) == .other(404))
        #expect(classifyVaultHTTP(status: 409, errorCode: "something_else") == .other(409))
    }

    // MARK: Wire types

    @Test("a register/login session decodes")
    func decodesSession() throws {
        let json = """
        {"account_id":"acc-1","api_key":"pnv_abc","key_id":"key-1","keyring":{"blob":"{\\"v\\":1}","version":1}}
        """
        let session = try JSONDecoder().decode(VaultSession.self, from: Data(json.utf8))
        #expect(session.accountId == "acc-1" && session.apiKey == "pnv_abc" && session.keyId == "key-1")
        #expect(session.keyring == VaultKeyring(blob: "{\"v\":1}", version: 1))
    }

    @Test("server-info decodes and reports whether signup is open")
    func decodesServerInfo() throws {
        let json = """
        {"name":"Pocket Nutrition Vault","version":"0.1.0","registration":"open","quota_bytes":52428800,
         "kdf_defaults":{"alg":"argon2id","opslimit":3,"memlimit":67108864}}
        """
        let info = try JSONDecoder().decode(VaultServerInfo.self, from: Data(json.utf8))
        #expect(info.isRegistrationOpen && info.quotaBytes == 52_428_800)
        let closed = try JSONDecoder().decode(
            VaultServerInfo.self,
            from: Data(#"{"name":"x","version":"1","registration":"closed","quota_bytes":1}"#.utf8)
        )
        #expect(!closed.isRegistrationOpen)
    }

    @Test("requests encode with the server's snake_case keys")
    func encodesRequests() throws {
        let register = VaultRegisterRequest(
            username: "alice", kdf: VaultKdf(salt: "AAAA", opslimit: 3, memlimit: 67_108_864),
            authHash: "hash", keyring: "{}", deviceLabel: "iPhone"
        )
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(register)) as? [String: Any])
        #expect(Set(object.keys) == ["username", "kdf", "auth_hash", "keyring", "device_label"])

        let drop = VaultDropRequest(recordId: "cap-1", type: "capture", keyId: "inbox", ttlSeconds: 3600, maxWrites: 1)
        let dropObject = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(drop)) as? [String: Any])
        #expect(Set(dropObject.keys) == ["record_id", "type", "key_id", "ttl_s", "max_writes"])
    }

    @Test("a sync page decodes, including a tombstone and an inbox drop")
    func decodesSyncPage() throws {
        let json = """
        {"records":[
          {"id":"r1","type":"meal","scope_id":null,"revision":2,"key_id":"user","ciphertext":"AAAA","deleted":false,"seq":5,"updated_at":"2026-10-21T10:00:00Z"},
          {"id":"cap-1","type":"capture","scope_id":null,"revision":1,"key_id":"inbox","ciphertext":"BBBB","deleted":false,"seq":6,"updated_at":"2026-10-21T10:01:00Z"},
          {"id":"r2","type":"meal","scope_id":null,"revision":3,"key_id":"user","ciphertext":"","deleted":true,"seq":7,"updated_at":"2026-10-21T10:02:00Z"}
        ],"cursor":7,"has_more":false}
        """
        let page = try JSONDecoder().decode(VaultSyncPage.self, from: Data(json.utf8))
        #expect(page.cursor == 7 && !page.hasMore && page.records.count == 3)
        #expect(!page.records[0].isInboxDrop && page.records[1].isInboxDrop)
        #expect(page.records[2].deleted && page.records[2].ciphertext.isEmpty)
    }

    // MARK: Drop payloads

    private func payload(
        record: String = "cap-1", status: String = "done", version: Int = 1, withResult: Bool = true
    ) -> Data {
        let result = withResult
            ? #","result":{"transcript":"deux oeufs","language":"fr","items":[{"raw_text":"deux oeufs","quantity":2,"unit":"piece","cooking_method":"fried","candidates":[{"ingredient_id":"oeuf","name":"Egg","score":0.9}]}]}"#
            : #","result":null"#
        return Data(#"{"v":\#(version),"record_id":"\#(record)","ticket_id":"t-1","status":"\#(status)"\#(result),"error":null,"completed_at":1791716113.9}"#.utf8)
    }

    @Test("a drop addressed to the expected record decodes with its result")
    func decodesDrop() throws {
        let decoded = try decodeVaultDropPayload(payload(), expectedRecordId: "cap-1")
        #expect(decoded.status == .done && decoded.ticketId == "t-1")
        #expect(decoded.result?.items.first?.bestCandidate?.ingredientId == "oeuf")
    }

    @Test("a failed capture is a valid delivery")
    func decodesFailedDrop() throws {
        let decoded = try decodeVaultDropPayload(payload(status: "failed", withResult: false), expectedRecordId: "cap-1")
        #expect(decoded.status == .failed && decoded.result == nil)
    }

    @Test("a drop for another record is refused")
    func refusesSwappedDrop() {
        #expect(throws: VaultDropPayloadError.recordMismatch) {
            try decodeVaultDropPayload(payload(record: "cap-2"), expectedRecordId: "cap-1")
        }
    }

    @Test("an unknown version, a non-final status and garbage are refused")
    func refusesBadDrops() {
        #expect(throws: VaultDropPayloadError.unsupportedVersion(2)) {
            try decodeVaultDropPayload(payload(version: 2), expectedRecordId: "cap-1")
        }
        #expect(throws: VaultDropPayloadError.notTerminal) {
            try decodeVaultDropPayload(payload(status: "extracting"), expectedRecordId: "cap-1")
        }
        #expect(throws: VaultDropPayloadError.malformed) {
            try decodeVaultDropPayload(Data("not json".utf8), expectedRecordId: "cap-1")
        }
    }
}
