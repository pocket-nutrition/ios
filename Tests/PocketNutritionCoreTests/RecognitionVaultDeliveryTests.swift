// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

@testable import PocketNutritionCore

private func ticketJSON(status: String, delivery: String? = nil, withResult: Bool = false) -> Data {
    var fields = [
        #""id": "t1""#, #""status": "\#(status)""#, #""created_at": 1.0"#, #""expires_at": 2.0"#,
    ]
    if let delivery { fields.append(#""delivery": "\#(delivery)""#) }
    if withResult { fields.append(#""result": {"transcript": "une pomme", "items": []}"#) }
    return Data("{\(fields.joined(separator: ","))}".utf8)
}

private func decodeTicket(_ data: Data) throws -> RecognitionTicket {
    try JSONDecoder().decode(RecognitionTicket.self, from: data)
}

@Suite("recognition vault delivery")
struct RecognitionVaultDeliveryTests {

    @Test("the ticket's delivery field is read, and absent on an older server")
    func ticketDecodesDelivery() throws {
        #expect(try decodeTicket(ticketJSON(status: "done", delivery: "delivered")).delivery == "delivered")
        #expect(try decodeTicket(ticketJSON(status: "done")).delivery == nil)
    }

    @Test("only a finished ticket with no result and delivery 'delivered' must be collected from the vault")
    func deliveredToVault() throws {
        #expect(isDeliveredToVault(try decodeTicket(ticketJSON(status: "done", delivery: "delivered"))))
        // The result is on the ticket: nothing to collect.
        #expect(!isDeliveredToVault(try decodeTicket(ticketJSON(status: "done", delivery: "delivered", withResult: true))))
        // Fallback after a refused deposit keeps the result on the ticket.
        #expect(!isDeliveredToVault(try decodeTicket(ticketJSON(status: "done", delivery: "failed", withResult: true))))
        #expect(!isDeliveredToVault(try decodeTicket(ticketJSON(status: "failed", delivery: "delivered"))))
        #expect(!isDeliveredToVault(try decodeTicket(ticketJSON(status: "extracting", delivery: "none"))))
        #expect(!isDeliveredToVault(try decodeTicket(ticketJSON(status: "done", delivery: "none"))))
    }

    @Test("a result collected elsewhere can be put on the ticket without touching anything else")
    func withResult() throws {
        let ticket = try decodeTicket(ticketJSON(status: "done", delivery: "delivered"))
        let result = RecognitionResult(transcript: "une pomme", language: "fr", items: [])
        let merged = ticket.withResult(result)
        #expect(merged.result == result)
        #expect(merged.id == ticket.id && merged.status == .done && merged.expiresAt == ticket.expiresAt)
    }

    @Test("an entry remembers the vault record its capture was uploaded with")
    func entryKeepsTheRecordId() throws {
        let ticket = try decodeTicket(ticketJSON(status: "queued"))
        let entry = RecognitionEntry(localId: "a", createdAt: 0, audioFile: "a.m4a")
        let withVault = entry.applying(.uploadSucceeded(ticket, now: 1, vaultRecordId: "rec-1"))
        #expect(withVault.vaultRecordId == "rec-1" && withVault.state == .processing)
        #expect(entry.applying(.uploadSucceeded(ticket, now: 1)).vaultRecordId == nil)
    }

    @Test("a retry replaces the record id with the new upload's")
    func retryReplacesTheRecordId() throws {
        let ticket = try decodeTicket(ticketJSON(status: "queued"))
        var entry = RecognitionEntry(localId: "a", createdAt: 0, audioFile: "a.m4a")
            .applying(.uploadSucceeded(ticket, now: 1, vaultRecordId: "old"))
        entry = entry.applying(.ticketGone)
        #expect(entry.state == .needsRetry)
        entry = entry.applying(.uploadSucceeded(ticket, now: 2, vaultRecordId: "new"))
        #expect(entry.vaultRecordId == "new")
    }

    @Test("the multipart body carries the vault fields after the audio and mode")
    func multipartFields() {
        let body = recognitionMultipartBody(
            boundary: "B", audio: Data("AUDIO".utf8),
            fields: [(name: "vault_url", value: "https://v.example"), (name: "vault_record_id", value: "rec-1")])
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains(#"name="vault_url"\#r\#n\#r\#nhttps://v.example"#))
        #expect(text.contains(#"name="vault_record_id"\#r\#n\#r\#nrec-1"#))
        #expect(text.hasSuffix("--B--\r\n"))
        let audio = text.range(of: "AUDIO")!.lowerBound
        #expect(audio < text.range(of: #"name="mode""#)!.lowerBound)
        #expect(text.range(of: #"name="mode""#)!.lowerBound < text.range(of: #"name="vault_url""#)!.lowerBound)
    }

    @Test("without vault fields the body is what it always was")
    func multipartUnchanged() {
        let plain = recognitionMultipartBody(boundary: "B", audio: Data("A".utf8))
        let withEmpty = recognitionMultipartBody(boundary: "B", audio: Data("A".utf8), fields: [])
        #expect(plain == withEmpty)
        #expect(!String(decoding: plain, as: UTF8.self).contains("vault"))
    }
}
