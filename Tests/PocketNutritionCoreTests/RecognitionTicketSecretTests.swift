// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

@testable import PocketNutritionCore

private func ticketJSON(secret: String?) -> Data {
    var fields = [#""id": "t1""#, #""status": "queued""#, #""created_at": 1.0"#, #""expires_at": 2.0"#]
    if let secret { fields.append(#""secret": "\#(secret)""#) }
    return Data("{\(fields.joined(separator: ","))}".utf8)
}

private func ticket(secret: String? = nil) throws -> RecognitionTicket {
    try JSONDecoder().decode(RecognitionTicket.self, from: ticketJSON(secret: secret))
}

@Suite("recognition ticket secret")
struct RecognitionTicketSecretTests {

    @Test("the secret in a creation answer is read, and absent on a later poll or an older server")
    func decodesSecret() throws {
        #expect(try ticket(secret: "s3cr3t").secret == "s3cr3t")
        #expect(try ticket().secret == nil)
    }

    @Test("an entry keeps the secret of the ticket it uploaded, and nothing is lost by polling")
    func entryKeepsSecret() throws {
        let uploaded = RecognitionEntry(localId: "a", createdAt: 0, audioFile: "a.m4a")
            .applying(.uploadSucceeded(try ticket(secret: "s3cr3t"), now: 1))
        #expect(uploaded.ticketSecret == "s3cr3t")
        // A poll answer never carries the secret, and must not erase it.
        let polled = uploaded.applying(.polled(try ticket(), now: 2))
        #expect(polled.ticketSecret == "s3cr3t")
    }

    @Test("a retry replaces the secret with the new ticket's, and a server without secrets leaves none")
    func retryReplacesSecret() throws {
        var entry = RecognitionEntry(localId: "a", createdAt: 0, audioFile: "a.m4a")
            .applying(.uploadSucceeded(try ticket(secret: "old"), now: 1))
            .applying(.ticketGone)
        entry = entry.applying(.uploadSucceeded(try ticket(secret: "new"), now: 2))
        #expect(entry.ticketSecret == "new")
        let legacy = RecognitionEntry(localId: "b", createdAt: 0, audioFile: "b.m4a")
            .applying(.uploadSucceeded(try ticket(), now: 1))
        #expect(legacy.ticketSecret == nil)
    }

    @Test("a result put on a ticket keeps its secret")
    func withResultKeepsSecret() throws {
        let merged = try ticket(secret: "s3cr3t").withResult(RecognitionResult(transcript: "x", language: nil, items: []))
        #expect(merged.secret == "s3cr3t")
    }

    @Test("entries saved before secrets and vault records existed still load")
    func oldEntriesStillDecode() throws {
        let json = Data(
            #"{"localId":"a","createdAt":1,"audioFile":"a.m4a","ticketId":"t1","state":"processing"}"#.utf8)
        let entry = try JSONDecoder().decode(RecognitionEntry.self, from: json)
        #expect(entry.ticketSecret == nil && entry.vaultRecordId == nil && entry.state == .processing)
    }

    @Test("an entry with a secret survives being saved and loaded")
    func roundTrip() throws {
        let entry = RecognitionEntry(localId: "a", createdAt: 0, audioFile: "a.m4a")
            .applying(.uploadSucceeded(try ticket(secret: "s3cr3t"), now: 1, vaultRecordId: "rec-1"))
        let back = try StoredEntries.decode(StoredEntries.encode([entry]))
        #expect(back == [entry] && back.first?.ticketSecret == "s3cr3t" && back.first?.vaultRecordId == "rec-1")
    }

    @Test("the ticket's own secret is the credential, then the shared key, then none")
    func credentialChoice() {
        #expect(recognitionCredential(ticketSecret: "s", apiKey: "k") == "s")
        #expect(recognitionCredential(ticketSecret: nil, apiKey: "k") == "k")
        #expect(recognitionCredential(ticketSecret: "", apiKey: "k") == "k")
        #expect(recognitionCredential(ticketSecret: nil, apiKey: nil) == nil)
        #expect(recognitionCredential(ticketSecret: nil, apiKey: "") == nil)
    }

    @Test("a 409 means the drop token was already used; it is retried, never blamed on the key")
    func conflictMeaning() {
        #expect(classifyRecognitionHTTP(409) == .conflict)
        #expect(classifyUploadFailure(.conflict) == .transient)
    }

    @Test("the official recognition server is a valid default")
    func defaultServer() {
        #expect(validatedRecognitionServerURL(defaultRecognitionServerURL) != nil)
        #expect(defaultRecognitionServerURL.hasPrefix("https://"))
    }
}
