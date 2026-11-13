// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

import PocketNutritionCore

// The recognition endpoint is not part of contracts 2.0.0, so these are hand-written tests against the
// shared client spec rather than vector-corpus suites.
@Suite("recognition ticket decoding")
struct RecognitionTicketTests {

    private let doneJSON = """
    {
      "id": "7b2c0f2e-1d34-4a52-9f0e-0f2d3c4b5a69",
      "status": "done",
      "created_at": 1791716110.95,
      "updated_at": 1791716113.95,
      "expires_at": 1791719710.95,
      "result": {
        "transcript": "deux oeufs au plat, du riz",
        "language": "fr",
        "unknown_extra": true,
        "items": [
          {
            "raw_text": "deux oeufs au plat",
            "quantity": 2,
            "unit": "piece",
            "cooking_method": "fried",
            "candidates": [
              { "ingredient_id": "oeuf_poule_entier_cuit", "name": "Egg, whole, cooked", "score": 0.93 },
              { "ingredient_id": "oeuf_poule_entier_cru", "name": "Egg, whole, raw", "score": 0.5 }
            ]
          },
          { "raw_text": "du riz", "quantity": null, "unit": null, "cooking_method": null, "candidates": [] }
        ]
      },
      "error": null
    }
    """

    @Test("the spec's done ticket decodes with every field")
    func decodesDoneTicket() throws {
        let ticket = try JSONDecoder().decode(RecognitionTicket.self, from: Data(doneJSON.utf8))
        #expect(ticket.id == "7b2c0f2e-1d34-4a52-9f0e-0f2d3c4b5a69")
        #expect(ticket.status == .done)
        #expect(ticket.createdAt == 1791716110.95)
        #expect(ticket.expiresAt == 1791719710.95)
        #expect(ticket.error == nil)
        let result = try #require(ticket.result)
        #expect(result.transcript == "deux oeufs au plat, du riz")
        #expect(result.language == "fr")
        #expect(result.items.count == 2)
        let first = result.items[0]
        #expect(first.rawText == "deux oeufs au plat")
        #expect(first.quantity == 2)
        #expect(first.unit == "piece")
        #expect(first.cookingMethod == "fried")
        #expect(first.candidates.map(\.ingredientId) == ["oeuf_poule_entier_cuit", "oeuf_poule_entier_cru"])
        #expect(first.candidates[0].score == 0.93)
        #expect(result.items[1].quantity == nil)
        #expect(result.items[1].candidates.isEmpty)
    }

    @Test("a queued ticket with a null result decodes")
    func decodesNullResult() throws {
        let json = """
        {"id":"a","status":"queued","created_at":1.0,"updated_at":2.0,"expires_at":3.0,"result":null,"error":null}
        """
        let ticket = try JSONDecoder().decode(RecognitionTicket.self, from: Data(json.utf8))
        #expect(ticket.status == .queued)
        #expect(ticket.result == nil)
    }

    @Test("a failed ticket carries its error string")
    func decodesFailed() throws {
        let json = """
        {"id":"a","status":"failed","created_at":1.0,"updated_at":2.0,"expires_at":3.0,"result":null,"error":"audio unreadable"}
        """
        let ticket = try JSONDecoder().decode(RecognitionTicket.self, from: Data(json.utf8))
        #expect(ticket.status == .failed)
        #expect(ticket.error == "audio unreadable")
    }

    @Test("an unknown status decodes as in-progress rather than throwing")
    func unknownStatusIsNonTerminal() throws {
        let json = """
        {"id":"a","status":"reticulating","created_at":1.0,"updated_at":2.0,"expires_at":3.0,"result":null,"error":null}
        """
        let ticket = try JSONDecoder().decode(RecognitionTicket.self, from: Data(json.utf8))
        #expect(ticket.status == .unknown("reticulating"))
        #expect(ticket.status.isTerminal == false)
    }

    @Test("a missing updated_at does not break decoding")
    func missingUpdatedAt() throws {
        let json = """
        {"id":"a","status":"queued","created_at":1.0,"expires_at":3.0}
        """
        let ticket = try JSONDecoder().decode(RecognitionTicket.self, from: Data(json.utf8))
        #expect(ticket.updatedAt == nil)
    }

    @Test("only done and failed are terminal")
    func terminalClassification() {
        #expect(RecognitionStatus.done.isTerminal)
        #expect(RecognitionStatus.failed.isTerminal)
        #expect(!RecognitionStatus.queued.isTerminal)
        #expect(!RecognitionStatus.transcribing.isTerminal)
        #expect(!RecognitionStatus.extracting.isTerminal)
        #expect(!RecognitionStatus.unknown("done ").isTerminal)
    }

    @Test("status round-trips through its wire string")
    func statusRoundTrip() throws {
        for status in [RecognitionStatus.queued, .transcribing, .extracting, .done, .failed, .unknown("x")] {
            #expect(RecognitionStatus(rawValue: status.rawValue) == status)
        }
    }
}

@Suite("recognition server URL validation")
struct RecognitionServerURLTests {

    @Test("accepts an https URL with a host and trims whitespace")
    func acceptsHttps() {
        #expect(validatedRecognitionServerURL("  https://recognition.pocketnutrition.org ")?.host
            == "recognition.pocketnutrition.org")
        #expect(validatedRecognitionServerURL("HTTPS://example.org:8443/base")?.port == 8443)
    }

    @Test("rejects http, other schemes, bare hosts, blanks and credentials")
    func rejects() {
        #expect(validatedRecognitionServerURL("http://example.org") == nil)
        #expect(validatedRecognitionServerURL("ftp://example.org") == nil)
        #expect(validatedRecognitionServerURL("example.org") == nil)
        #expect(validatedRecognitionServerURL("https://") == nil)
        #expect(validatedRecognitionServerURL("") == nil)
        #expect(validatedRecognitionServerURL("   ") == nil)
        #expect(validatedRecognitionServerURL("https://user:pw@example.org") == nil)
    }
}

@Suite("recognition endpoints")
struct RecognitionEndpointTests {

    private let base = URL(string: "https://r.example.org")!

    @Test("captures collection URL")
    func capturesURL() {
        #expect(recognitionCapturesURL(base: base)?.absoluteString == "https://r.example.org/captures")
    }

    @Test("a base with a path prefix and trailing slash is respected")
    func baseWithPrefix() {
        let prefixed = URL(string: "https://r.example.org/api/")!
        #expect(recognitionCapturesURL(base: prefixed)?.absoluteString == "https://r.example.org/api/captures")
    }

    @Test("plain read has no query")
    func plainRead() {
        #expect(recognitionCaptureURL(base: base, id: "abc")?.absoluteString
            == "https://r.example.org/captures/abc")
    }

    @Test("long poll carries wait and known_status")
    func longPoll() {
        let url = recognitionCaptureURL(base: base, id: "abc", wait: 20, knownStatus: "queued")
        #expect(url?.absoluteString == "https://r.example.org/captures/abc?wait=20&known_status=queued")
    }

    @Test("an id is percent-encoded as a single path segment")
    func idEncoded() {
        let url = recognitionCaptureURL(base: base, id: "a/b c")
        #expect(url?.absoluteString == "https://r.example.org/captures/a%2Fb%20c")
    }

    @Test("HTTP status classification")
    func classifyStatus() {
        #expect(classifyRecognitionHTTP(200) == .success)
        #expect(classifyRecognitionHTTP(202) == .success)
        #expect(classifyRecognitionHTTP(204) == .success)
        #expect(classifyRecognitionHTTP(401) == .unauthorized)
        #expect(classifyRecognitionHTTP(404) == .notFound)
        #expect(classifyRecognitionHTTP(410) == .expired)
        #expect(classifyRecognitionHTTP(413) == .tooLarge)
        #expect(classifyRecognitionHTTP(415) == .unsupportedMedia)
        #expect(classifyRecognitionHTTP(500) == .other(500))
    }
}

@Suite("recognition multipart body")
struct RecognitionMultipartTests {

    @Test("builds the audio part and the mode field, byte exact")
    func bodyLayout() throws {
        let audio = Data([0x00, 0xFF, 0x10, 0x0D, 0x0A, 0x2D])
        let body = recognitionMultipartBody(boundary: "BND", audio: audio, mode: "async")
        var expected = Data()
        expected.append(Data("--BND\r\n".utf8))
        expected.append(Data("Content-Disposition: form-data; name=\"audio\"; filename=\"meal.m4a\"\r\n".utf8))
        expected.append(Data("Content-Type: audio/mp4\r\n\r\n".utf8))
        expected.append(audio)
        expected.append(Data("\r\n--BND\r\n".utf8))
        expected.append(Data("Content-Disposition: form-data; name=\"mode\"\r\n\r\n".utf8))
        expected.append(Data("async\r\n".utf8))
        expected.append(Data("--BND--\r\n".utf8))
        #expect(body == expected)
    }

    @Test("content type names the boundary")
    func contentType() {
        #expect(recognitionMultipartContentType(boundary: "BND") == "multipart/form-data; boundary=BND")
    }
}

@Suite("recognition back-off")
struct RecognitionBackoffTests {

    @Test("3 s, doubling, capped at 30 s")
    func schedule() {
        let delays = (1...8).map { recognitionBackoffSeconds(consecutiveFailures: $0) }
        #expect(delays == [3, 6, 12, 24, 30, 30, 30, 30])
    }

    @Test("zero or negative failures give no delay; huge counts do not overflow")
    func edges() {
        #expect(recognitionBackoffSeconds(consecutiveFailures: 0) == 0)
        #expect(recognitionBackoffSeconds(consecutiveFailures: -3) == 0)
        #expect(recognitionBackoffSeconds(consecutiveFailures: Int.max) == 30)
    }
}
