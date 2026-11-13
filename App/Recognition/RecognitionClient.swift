// SPDX-License-Identifier: MPL-2.0

import Foundation
import PocketNutritionCore
import PocketNutritionVault

// Client for the voice-recognition server. The endpoint is NOT part of contracts 2.0.0 (see
// `PocketNutritionCore/RecognitionTicket.swift`), which is why it is hand-written and separate from
// `PocketNutritionApi`: different base URL, bearer auth, multipart upload and a long poll that outlives
// that client's 15 s timeout.

enum RecognitionError: Error, Sendable, Equatable {
    /// No connectivity, a timeout, or any transport failure: the request may simply be retried.
    case offline
    /// The server answered with a non-success status; `message` is its `detail` text when it sent one.
    case http(Int, message: String?)
    /// A poll/delete answer that could not be understood.
    case malformedResponse
    /// A 2xx upload answer with no usable ticket id. The ticket may well exist on the server.
    case malformedUpload
    /// The audio file is confirmed missing or empty: it cannot be sent, ever.
    case unreadableAudio
    /// The audio file exists but could not be read just now: retry later.
    case audioReadFailed

    /// The status code's meaning, or nil for a transport failure.
    var outcome: RecognitionHTTPOutcome? {
        if case .http(let code, _) = self { return classifyRecognitionHTTP(code) }
        return nil
    }
}

enum RecognitionFetch: Sendable, Equatable {
    case ticket(RecognitionTicket)
    /// 404: the ticket is unknown or purged.
    case gone
    /// 410: its TTL elapsed.
    case expired
}

/// Long-poll length in seconds. The server allows up to 25.
let recognitionLongPollSeconds = 20

/// Refuses every redirect. This API has no reason to redirect, and following one would carry the
/// Authorization header (and the voice upload) to wherever the response points.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

actor RecognitionClient {

    private let configuration: RecognitionConfiguration
    /// Whether this server still takes a shared key. If not, a 401 on upload means the vault drop token was
    /// refused, not that anything the person typed is wrong.
    nonisolated let usesSharedKey: Bool
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(configuration: RecognitionConfiguration, session: URLSession? = nil) {
        self.configuration = configuration
        usesSharedKey = configuration.apiKey != nil
        if let session {
            self.session = session
            return
        }
        // Ephemeral: no cookies or cache for a credentialed endpoint. The idle timeout must exceed the
        // long poll (wait + 10 s), unlike the 15 s the nutrition client uses.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = TimeInterval(recognitionLongPollSeconds + 10)
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    deinit {
        // The session retains its delegate until invalidated.
        session.finishTasksAndInvalidate()
    }

    /// `POST /captures` (async mode). The file is only read; deleting it is the store's job. With a vault
    /// `grant` the worker seals the result into the user's vault instead of returning it here.
    func upload(audioFileURL: URL, vault grant: VaultDropGrant? = nil) async throws -> RecognitionTicket {
        let audio: Data
        do {
            audio = try Data(contentsOf: audioFileURL)
        } catch {
            // Only a CONFIRMED missing file is a lost recording; any other read error is transient.
            throw FileManager.default.fileExists(atPath: audioFileURL.path)
                ? RecognitionError.audioReadFailed : RecognitionError.unreadableAudio
        }
        guard !audio.isEmpty else { throw RecognitionError.unreadableAudio }
        guard let url = recognitionCapturesURL(base: configuration.baseURL) else {
            throw RecognitionError.malformedResponse
        }
        let boundary = "pn-\(UUID().uuidString)"
        var request = authorized(URLRequest(url: url), credential: configuration.apiKey)
        request.httpMethod = "POST"
        request.setValue(recognitionMultipartContentType(boundary: boundary), forHTTPHeaderField: "Content-Type")
        let fields = grant.map {
            [
                (name: "vault_url", value: $0.vaultURL), (name: "vault_token", value: $0.token),
                (name: "vault_record_id", value: $0.recordId), (name: "inbox_public_key", value: $0.inboxPublicKey),
            ]
        } ?? []
        let media = recognitionMediaPart(fileName: audioFileURL.lastPathComponent)
        let body = recognitionMultipartBody(boundary: boundary, audio: audio, media: media, fields: fields)

        let (data, response) = try await perform { try await session.upload(for: request, from: body) }
        try Self.check(response, data)
        return try Self.uploadedTicket(data: data, response: response, decoder: decoder)
    }

    /// `GET /captures/{id}`. Plain read when `wait` is nil; long poll otherwise.
    func fetch(id: String, secret: String? = nil, wait: Int? = nil, knownStatus: String? = nil) async throws -> RecognitionFetch {
        guard isValidTicketId(id),
              let url = recognitionCaptureURL(base: configuration.baseURL, id: id, wait: wait, knownStatus: knownStatus)
        else { throw RecognitionError.malformedResponse }
        let (data, response) = try await perform { try await capped(authorized(URLRequest(url: url), credential: credential(secret))) }
        switch classifyRecognitionHTTP(response.statusCode) {
        case .notFound: return .gone
        case .expired: return .expired
        default:
            try Self.check(response, data)
            return .ticket(try decode(data))
        }
    }

    /// `DELETE /captures/{id}`. 404 and 410 mean there is nothing left to delete, which is success.
    func delete(id: String, secret: String? = nil) async throws {
        guard isValidTicketId(id), let url = recognitionCaptureURL(base: configuration.baseURL, id: id) else {
            throw RecognitionError.malformedResponse
        }
        var request = authorized(URLRequest(url: url), credential: credential(secret))
        request.httpMethod = "DELETE"
        let (data, response) = try await perform { try await capped(request) }
        switch classifyRecognitionHTTP(response.statusCode) {
        case .notFound, .expired: return
        default: try Self.check(response, data)
        }
    }

    // MARK: - Plumbing

    /// The ticket's own secret, else the shared key (older tickets, self-hosted servers), else nothing.
    private func credential(_ ticketSecret: String?) -> String? {
        recognitionCredential(ticketSecret: ticketSecret, apiKey: configuration.apiKey)
    }

    private func authorized(_ request: URLRequest, credential: String?) -> URLRequest {
        var copy = request
        if let credential { copy.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization") }
        copy.setValue("application/json", forHTTPHeaderField: "Accept")
        return copy
    }

    /// Reads at most `recognitionMaxResponseBytes`; a larger (or lying) response is rejected.
    private func capped(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        if response.expectedContentLength > Int64(recognitionMaxResponseBytes) {
            throw RecognitionError.malformedResponse
        }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > recognitionMaxResponseBytes { throw RecognitionError.malformedResponse }
        }
        return (data, response)
    }

    private func perform(
        _ call: () async throws -> (Data, URLResponse)
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await call()
            guard let http = response as? HTTPURLResponse else { throw RecognitionError.malformedResponse }
            guard data.count <= recognitionMaxResponseBytes else { throw RecognitionError.malformedResponse }
            return (data, http)
        } catch let error as URLError {
            // Cancellation is not a failure: the coordinator cancels loops when its screen is left.
            if error.code == .cancelled { throw CancellationError() }
            throw RecognitionError.offline
        }
    }

    /// Anything but 2xx is an error — a 3xx included, since redirects are refused rather than followed.
    private static func check(_ response: HTTPURLResponse, _ data: Data) throws {
        guard classifyRecognitionHTTP(response.statusCode) != .success else { return }
        throw RecognitionError.http(response.statusCode, message: serverMessage(data))
    }

    /// The server's explanation, shown as received but capped: a JSON `detail` string, else short plain
    /// text. A structured `detail` (FastAPI's 422 array) is not rendered as raw JSON — no message.
    private static func serverMessage(_ data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return (object["detail"] as? String).map(recognitionTruncated)
        }
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, !text.hasPrefix("<"), !text.hasPrefix("[") else { return nil }
        return recognitionTruncated(text)
    }

    /// A 2xx upload answer: the ticket if the body decodes, else just an id from the body or the
    /// `Location` header (`/captures/{id}`). With no id at all it is `malformedUpload`, never a
    /// transport error — the server may already hold the ticket, and retrying blindly would duplicate it.
    private static func uploadedTicket(
        data: Data, response: HTTPURLResponse, decoder: JSONDecoder
    ) throws -> RecognitionTicket {
        if let ticket = try? decoder.decode(RecognitionTicket.self, from: data) { return ticket }
        var id = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["id"] as? String
        if id == nil, let location = response.value(forHTTPHeaderField: "Location") {
            id = location.split(separator: "/").last.map(String.init)
        }
        guard let id, isValidTicketId(id) else { throw RecognitionError.malformedUpload }
        let now = Date().timeIntervalSince1970
        // Expiry unknown: the server's TTL is 48 h, and the first poll replaces this with the real value.
        return RecognitionTicket(
            id: id, status: .queued, createdAt: now, updatedAt: nil, expiresAt: now + 48 * 3600,
            result: nil, error: nil
        )
    }

    private func decode(_ data: Data) throws -> RecognitionTicket {
        do { return try decoder.decode(RecognitionTicket.self, from: data) } catch {
            throw RecognitionError.malformedResponse
        }
    }
}
