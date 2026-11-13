// SPDX-License-Identifier: MPL-2.0

import Foundation

// The voice-recognition endpoint is NOT part of contracts 2.0.0. These types are hand-written against
// the shared client spec, and decoding is deliberately lenient: unknown keys are ignored and an unknown
// status is "in progress", never a crash — the server may grow states this build has not heard of.

/// Where a capture is in the server's pipeline.
public enum RecognitionStatus: Equatable, Sendable, Codable {
    case queued
    case transcribing
    case extracting
    case done
    case failed
    /// A status string this build does not know. Treated as non-terminal so tracking continues.
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "queued": self = .queued
        case "transcribing": self = .transcribing
        case "extracting": self = .extracting
        case "done": self = .done
        case "failed": self = .failed
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .queued: "queued"
        case .transcribing: "transcribing"
        case .extracting: "extracting"
        case .done: "done"
        case .failed: "failed"
        case .unknown(let value): value
        }
    }

    /// Only `done` and `failed` end tracking. An unrecognised status keeps being polled.
    public var isTerminal: Bool { self == .done || self == .failed }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct RecognitionCandidate: Equatable, Sendable, Codable {
    public let ingredientId: String
    public let name: String?
    public let score: Double?

    public init(ingredientId: String, name: String?, score: Double?) {
        self.ingredientId = ingredientId
        self.name = name
        self.score = score
    }

    private enum CodingKeys: String, CodingKey {
        case ingredientId = "ingredient_id"
        case name, score
    }
}

public struct RecognitionItem: Equatable, Sendable, Codable {
    public let rawText: String
    public let quantity: Double?
    public let unit: String?
    public let cookingMethod: String?
    /// Ranked best-first by the server.
    public let candidates: [RecognitionCandidate]

    public init(
        rawText: String, quantity: Double?, unit: String?, cookingMethod: String?,
        candidates: [RecognitionCandidate]
    ) {
        self.rawText = rawText
        self.quantity = quantity
        self.unit = unit
        self.cookingMethod = cookingMethod
        self.candidates = candidates
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rawText = try c.decode(String.self, forKey: .rawText)
        quantity = try c.decodeIfPresent(Double.self, forKey: .quantity)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        cookingMethod = try c.decodeIfPresent(String.self, forKey: .cookingMethod)
        let all = try c.decodeIfPresent([RecognitionCandidate].self, forKey: .candidates) ?? []
        candidates = Array(all.prefix(recognitionMaxCandidates))
    }

    private enum CodingKeys: String, CodingKey {
        case rawText = "raw_text"
        case quantity, unit
        case cookingMethod = "cooking_method"
        case candidates
    }

    /// The preselected candidate: the server ranks best-first.
    public var bestCandidate: RecognitionCandidate? { candidates.first }
}

public struct RecognitionResult: Equatable, Sendable, Codable {
    public let transcript: String
    public let language: String?
    public let items: [RecognitionItem]

    public init(transcript: String, language: String?, items: [RecognitionItem]) {
        self.transcript = transcript
        self.language = language
        self.items = items
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        transcript = try c.decodeIfPresent(String.self, forKey: .transcript) ?? ""
        language = try c.decodeIfPresent(String.self, forKey: .language)
        let all = try c.decodeIfPresent([RecognitionItem].self, forKey: .items) ?? []
        items = Array(all.prefix(recognitionMaxItems))
    }

    private enum CodingKeys: String, CodingKey { case transcript, language, items }

    /// A result worth keeping: it says something. An empty object (a server fault, or `"result": {}`)
    /// is not a result, and must never cause the audio to be released.
    public var isUsable: Bool { !transcript.isEmpty || !items.isEmpty }
}

/// The server's ticket. Times are Unix epoch seconds as floating-point numbers.
public struct RecognitionTicket: Equatable, Sendable, Codable {
    public let id: String
    public let status: RecognitionStatus
    public let createdAt: Double
    public let updatedAt: Double?
    public let expiresAt: Double
    public let result: RecognitionResult?
    public let error: String?
    /// "delivered" when the worker sealed the result into the user's vault: the server no longer holds it
    /// and the phone must collect it there. "failed" keeps the result on the ticket as a fallback.
    public let delivery: String?
    /// Authenticates later reads and deletes of this ticket. Only the creation answer carries it.
    public let secret: String?

    public init(
        id: String, status: RecognitionStatus, createdAt: Double, updatedAt: Double?,
        expiresAt: Double, result: RecognitionResult?, error: String?, delivery: String? = nil,
        secret: String? = nil
    ) {
        self.id = id
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
        self.result = result
        self.error = error
        self.delivery = delivery
        self.secret = secret
    }

    /// The same ticket carrying a result collected elsewhere (the vault).
    public func withResult(_ result: RecognitionResult) -> RecognitionTicket {
        RecognitionTicket(
            id: id, status: status, createdAt: createdAt, updatedAt: updatedAt, expiresAt: expiresAt,
            result: result, error: error, delivery: delivery, secret: secret)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        guard isValidTicketId(id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "unsafe ticket id")
        }
        self.id = id
        status = try c.decode(RecognitionStatus.self, forKey: .status)
        createdAt = try c.decode(Double.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Double.self, forKey: .updatedAt)
        expiresAt = try c.decode(Double.self, forKey: .expiresAt)
        result = try c.decodeIfPresent(RecognitionResult.self, forKey: .result)
        error = try c.decodeIfPresent(String.self, forKey: .error).map(recognitionTruncated)
        delivery = try c.decodeIfPresent(String.self, forKey: .delivery)
        secret = try c.decodeIfPresent(String.self, forKey: .secret)
    }

    private enum CodingKeys: String, CodingKey {
        case id, status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case expiresAt = "expires_at"
        case result, error, delivery, secret
    }
}

/// A finished ticket whose result is not on it because the worker sealed it into the vault: the phone
/// has to fetch it there.
public func isDeliveredToVault(_ ticket: RecognitionTicket) -> Bool {
    ticket.status == .done && ticket.result == nil && ticket.delivery == "delivered"
}

// MARK: - Untrusted-data limits
//
// Everything here comes from a server the user pointed the app at. Caps keep a hostile or buggy one
// from filling the entries file or the UI.

/// Longest `error` / `detail` text kept.
public let recognitionMaxMessageLength = 200
/// Most items kept from one result.
public let recognitionMaxItems = 50
/// Most candidates kept per item.
public let recognitionMaxCandidates = 10
/// Largest response body accepted, in bytes.
public let recognitionMaxResponseBytes = 1_000_000

/// `s` cut to the message cap.
public func recognitionTruncated(_ s: String) -> String {
    s.count > recognitionMaxMessageLength ? String(s.prefix(recognitionMaxMessageLength)) : s
}

private func isSafeSegment(_ s: String, maxLength: Int, allowDot: Bool) -> Bool {
    guard !s.isEmpty, s.utf8.count <= maxLength, s != ".", s != ".." else { return false }
    return s.unicodeScalars.allSatisfy { c in
        (c.value >= 48 && c.value <= 57) || (c.value >= 65 && c.value <= 90) || (c.value >= 97 && c.value <= 122)
            || c == "_" || c == "-" || (allowDot && c == ".")
    }
}

/// A server ticket id, safe to use as a path segment: `^[A-Za-z0-9_-]{1,64}$`.
public func isValidTicketId(_ id: String) -> Bool { isSafeSegment(id, maxLength: 64, allowDot: false) }

/// An ingredient id safe to use as a path segment: `^[A-Za-z0-9_.-]{1,128}$`, never `.` or `..`.
public func isValidIngredientId(_ id: String) -> Bool { isSafeSegment(id, maxLength: 128, allowDot: true) }
