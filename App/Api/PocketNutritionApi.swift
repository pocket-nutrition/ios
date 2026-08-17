// SPDX-License-Identifier: MPL-2.0

import Foundation
import PocketNutritionCore

// The two endpoints the app needs, and the shapes they exchange. Both are transcribed from the
// vendored `contract/data/openapi.patched.json` rather than from a live response, so a field the
// server stops sending fails to decode here instead of quietly becoming nil somewhere in a view.
//
// WHY HAND-WRITTEN RATHER THAN GENERATED
// The spec describes some thirty nutrients and five endpoints; this app uses four macros and two
// endpoints. A generator would produce the whole surface and the unused nine tenths would rot
// unnoticed. When the app grows into the rest of the spec, revisit — the emitter that already
// produces Tokens.swift in pocket-nutrition-contracts is the natural home for it.

// `IngredientSuggestion`, `RecipeComponent` and `AddItem` now live in PocketNutritionCore, because
// `build-meal-ingredient`, `apply-method-change` and `unpack-recipe` all take those shapes as input.
// The move cost nothing: `Decodable` is Swift standard library, so Core still imports nothing. The
// Foundation half — `JSONDecoder`, below — is what stays here.

/// One item of a `POST /nutrition` request body.
struct FoodItemRequest: Encodable, Sendable {
    let name: String?
    let quantity: Double
    let unit: String
    let cookingMethod: String
    let measuredState: String
    let ingredientId: String?
}

/// One item of a `POST /nutrition` response.
///
/// Only the fields the results screen renders are declared. Adding another nutrient is a one-line
/// change; carrying all thirty unused would obscure which ones the product actually shows.
struct NutritionalProfile: Decodable, Sendable {
    let name: String
    let quantity: Double
    let unit: String
    let cookingMethod: String
    let measuredState: String
    let energyKcal: Double
    let proteinG: Double
    let fatG: Double
    let carbohydratesG: Double
    let fiberG: Double?
    let sugarsG: Double?
}

/// One field of an ingredient a user believes is wrong, plus the corrected value if they typed one.
///
/// `category`/`code` are transcribed verbatim from `FeedbackCatalog` — see that type's own note on why
/// they must match the server's allowlist exactly.
struct FeedbackCorrection: Encodable, Sendable {
    let category: String
    let code: String
    let value: String?
    let unit: String?
}

/// `POST /feedback` request body: a report against an ingredient by name, not by id — the server
/// resolves the match itself, which is what lets a report about an ingredient the search never found
/// still be sent. `cookingMethod`/`measuredState`/`source` come from whatever context the report was
/// opened from and are omitted, not sent as an empty string, when that context does not have them —
/// same rule the sandbox's `FeedbackDialog` follows, because a server-minted enum value the client
/// invented is worse than an absent optional field.
struct FeedbackRequest: Encodable, Sendable {
    let name: String
    let corrections: [FeedbackCorrection]
    let comment: String?
    let cookingMethod: String?
    let measuredState: String?
    let source: String?
}

/// Reference macro-nutrient values per 100 g, from `GET /ingredients/{id}`'s `referenceNutrition`.
struct ReferenceNutrition: Decodable, Sendable {
    let energyKcal: Double?
    let proteinG: Double?
    let fatG: Double?
    let carbohydratesG: Double?
    let fiberG: Double?
}

/// `GET /ingredients/{id}` response — the knowledge-base detail behind one ingredient, fetched only to
/// enrich the feedback form's current-value hints for the categories `MealIngredient` cannot answer on
/// its own (nutrition, identity — see `FeedbackCurrentValueHint`). Declares only what the form reads;
/// `aliasesFr`/`aliasesEn`/`servingUnits`/`referenceWeightG`/etc. the server also sends decode away
/// harmlessly, same as every other type in this file that only names a subset of its response schema.
struct IngredientDetail: Decodable, Sendable {
    let nameFr: String?
    let nameEn: String?
    let foodGroup: String?
    let referenceNutrition: ReferenceNutrition?
}

/// Failures a caller can act on differently, rather than one opaque error.
///
/// Each message is French and user-facing, because the copy deck puts the raw message in front of the
/// user — `errors.prefix` is `Erreur : {message}`. A `URLError` description would surface as English
/// technical text inside French copy.
enum ApiError: Error, LocalizedError, Sendable {
    case offline
    case timedOut
    case badStatus(Int)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .offline: return "pas de connexion internet"
        case .timedOut: return "le serveur ne répond pas"
        case .badStatus(let code): return "le serveur a répondu \(code)"
        case .malformedResponse: return "réponse illisible du serveur"
        }
    }
}

/// Client for the public Pocket Nutrition API.
///
/// An actor because several views call it concurrently; that costs nothing here and removes the
/// question of who owns the session.
actor PocketNutritionApi {

    static let shared = PocketNutritionApi()

    /// The public API. No staging host and no build-time switch: there is one deployment, and a URL
    /// that can be pointed elsewhere invites shipping a build pointed at the wrong place.
    private let baseURL = URL(string: "https://api.pocketnutrition.org")!

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }
        let configuration = URLSessionConfiguration.default
        // A phone on a weak connection should surface a retryable error rather than hang behind the
        // 60-second default.
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    /// A search response, body and segment count together.
    ///
    /// The count cannot be derived from the rows, so it has to travel with them rather than being
    /// recomputed at the call site — see `segmentCount` below.
    struct SearchResponse {
        let rows: [IngredientSuggestion]

        /// How many ingredient phrases the server split the query into, from `X-Segment-Count`.
        ///
        /// **Not derivable on the client.** The server segments with greedy longest-match probes against
        /// the search index, so `pomme de terre` is one term and `riz poulet pomme` is three. Counting
        /// spaces here would offer a multi-select for a single potato.
        let segmentCount: Int
    }

    /// `GET /ingredients/search`. A blank query returns an empty result without calling the server: the
    /// field fires as the user types, and `q` is required by the spec.
    func search(_ query: String, limit: Int = 12) async throws -> SearchResponse {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SearchResponse(rows: [], segmentCount: 1) }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("ingredients/search"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "lang", value: "fr"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        let (rows, headers): ([IngredientSuggestion], HTTPURLResponse) =
            try await sendWithResponse(URLRequest(url: components.url!))
        return SearchResponse(rows: rows, segmentCount: Self.segmentCount(from: headers))
    }

    /// Reads `X-Segment-Count`, defaulting to 1.
    ///
    /// **The default is load-bearing, not defensive.** A server that does not send the header — an older
    /// deployment, a proxy that strips it — must degrade to today's single-add behaviour rather than to a
    /// multi-select that cannot be confirmed. Same tolerant-reader principle the contract already states
    /// for enum values, applied to a header. `Int(...)` on a malformed value gives nil and lands here too.
    private static func segmentCount(from response: HTTPURLResponse) -> Int {
        guard
            let raw = response.value(forHTTPHeaderField: "X-Segment-Count"),
            let parsed = Int(raw),
            parsed > 0
        else { return 1 }
        return parsed
    }

    /// `POST /nutrition`. The whole meal goes in one body, which is what the endpoint takes and what
    /// keeps a multi-item meal to a single round trip.
    func analyse(_ items: [FoodItemRequest]) async throws -> [NutritionalProfile] {
        var request = URLRequest(url: baseURL.appendingPathComponent("nutrition"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(items)
        return try await send(request)
    }

    /// `POST /feedback`. The 201 body is an untyped acknowledgement (`additionalProperties: string`)
    /// with nothing the app renders, so it is discarded rather than decoded — decoding a value only to
    /// never read it would just be one more way for a server-side field rename to break this silently.
    func submitFeedback(_ request: FeedbackRequest) async throws {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("feedback"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try encoder.encode(request)
        try await sendDiscardingBody(urlRequest)
    }

    /// `GET /ingredients/barcode/{ean13}`. `nil` means the barcode is not in the Open Food Facts
    /// catalogue — an expected, distinct outcome the spec documents on its own 404 response, not a
    /// server failure, which is why this does not throw `ApiError.badStatus` for it. Decodes straight
    /// into `IngredientSuggestion`: the response schema (`IngredientSuggestionWithNutrition`) is that
    /// same field set plus an unused `nutrition` field, which decodes away harmlessly like every other
    /// field this type does not declare.
    func lookupBarcode(_ ean13: String) async throws -> IngredientSuggestion? {
        let url = baseURL.appendingPathComponent("ingredients/barcode").appendingPathComponent(ean13)
        return try await sendAllowingNotFound(URLRequest(url: url))
    }

    /// `GET /ingredients/{id}`. `nil` means the id is not in the index — the same "expected outcome,
    /// not a server failure" reasoning as `lookupBarcode`'s 404. Callers treat a `nil`/thrown result as
    /// "no extra hints available" rather than surfacing an error, since this only enriches a form that
    /// works without it.
    func ingredientDetail(_ id: String) async throws -> IngredientDetail? {
        let url = baseURL.appendingPathComponent("ingredients").appendingPathComponent(id)
        return try await sendAllowingNotFound(URLRequest(url: url))
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (decoded, _): (T, HTTPURLResponse) = try await sendWithResponse(request)
        return decoded
    }

    /// The same transport as `send`, without decoding a response body — for the one endpoint whose
    /// response the app never reads. Every other endpoint's response is the entire point of calling it,
    /// so this stays private to `submitFeedback` rather than becoming a third general-purpose sibling.
    private func sendDiscardingBody(_ request: URLRequest) async throws {
        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost: throw ApiError.offline
            case .timedOut: throw ApiError.timedOut
            default: throw ApiError.malformedResponse
            }
        }

        guard let http = response as? HTTPURLResponse else { throw ApiError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else { throw ApiError.badStatus(http.statusCode) }
    }

    /// The same transport as `sendWithResponse`, except a 404 is a valid outcome (`nil`) rather than
    /// `ApiError.badStatus` — only `lookupBarcode` needs this distinction, since it is the only
    /// endpoint whose spec documents 404 as a meaningful, expected answer rather than a server error.
    private func sendAllowingNotFound<T: Decodable>(_ request: URLRequest) async throws -> T? {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost: throw ApiError.offline
            case .timedOut: throw ApiError.timedOut
            default: throw ApiError.malformedResponse
            }
        }

        guard let http = response as? HTTPURLResponse else { throw ApiError.malformedResponse }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else { throw ApiError.badStatus(http.statusCode) }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ApiError.malformedResponse
        }
    }

    /// The same transport as `send`, handing back the `HTTPURLResponse` so a caller can read a header.
    ///
    /// Split out rather than threading an out-parameter through every call site: only search needs the
    /// headers, and `send` stays the shape the other endpoints already use.
    private func sendWithResponse<T: Decodable>(
        _ request: URLRequest
    ) async throws -> (T, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            // Mapped rather than rethrown: these are the cases a user can act on, and they are the
            // ones that reach the error banner.
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost: throw ApiError.offline
            case .timedOut: throw ApiError.timedOut
            default: throw ApiError.malformedResponse
            }
        }

        guard let http = response as? HTTPURLResponse else { throw ApiError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else { throw ApiError.badStatus(http.statusCode) }

        do {
            return (try decoder.decode(T.self, from: data), http)
        } catch {
            throw ApiError.malformedResponse
        }
    }
}
