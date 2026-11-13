// SPDX-License-Identifier: MPL-2.0

import Foundation

// Pure, Foundation-only helpers for talking to the recognition server. The URLSession code itself is
// Apple-only and lives in the app target; everything that can be decided without a network is here so
// Linux CI covers it. Not part of contracts 2.0.0.

/// The official recognition server, used until the person chooses another one.
public let defaultRecognitionServerURL = "https://recognition.pocketnutrition.org"

/// What to put in `Authorization: Bearer` for a ticket call: the ticket's own secret, else the shared key
/// (older tickets and self-hosted servers), else nothing. An empty value counts as absent.
public func recognitionCredential(ticketSecret: String?, apiKey: String?) -> String? {
    for candidate in [ticketSecret, apiKey] {
        if let candidate, !candidate.isEmpty { return candidate }
    }
    return nil
}

/// The server URL the user typed, or nil if it is not usable.
///
/// `https` only, with a host and no embedded credentials. Plain `http` is refused on purpose: neither
/// App Transport Security nor the Android cleartext policy is being relaxed for this feature, and the
/// recording and the API key both travel to this address.
public func validatedRecognitionServerURL(_ raw: String) -> URL? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let components = URLComponents(string: trimmed),
          components.scheme?.lowercased() == "https",
          let host = components.host, !host.isEmpty,
          components.user == nil, components.password == nil,
          let url = components.url
    else { return nil }
    return url
}

/// `{base}/captures`.
public func recognitionCapturesURL(base: URL) -> URL? {
    recognitionURL(base: base, segments: ["captures"], query: [])
}

/// `{base}/captures/{id}`, with `wait` and `known_status` for a long poll.
public func recognitionCaptureURL(
    base: URL, id: String, wait: Int? = nil, knownStatus: String? = nil
) -> URL? {
    var query: [URLQueryItem] = []
    if let wait, wait > 0 {
        query.append(URLQueryItem(name: "wait", value: String(wait)))
        if let knownStatus { query.append(URLQueryItem(name: "known_status", value: knownStatus)) }
    }
    return recognitionURL(base: base, segments: ["captures", id], query: query)
}

private func recognitionURL(base: URL, segments: [String], query: [URLQueryItem]) -> URL? {
    guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
    // Built from the already-encoded path so an id containing "/" stays one segment (%2F) instead of
    // silently becoming two.
    var path = components.percentEncodedPath
    while path.hasSuffix("/") { path.removeLast() }
    let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
    for segment in segments {
        guard let encoded = segment.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        path += "/" + encoded
    }
    components.percentEncodedPath = path
    components.queryItems = query.isEmpty ? nil : query
    return components.url
}

/// What a recognition-server status code means to the client, independent of the endpoint.
public enum RecognitionHTTPOutcome: Equatable, Sendable {
    case success
    case unauthorized
    /// 404: unknown or purged ticket ("gone").
    case notFound
    /// 410: the ticket's TTL elapsed.
    case expired
    case tooLarge
    case unsupportedMedia
    /// 409: the drop token already started another dictation; mint a new one and send again.
    case conflict
    case other(Int)
}

public func classifyRecognitionHTTP(_ statusCode: Int) -> RecognitionHTTPOutcome {
    switch statusCode {
    case 200..<300: .success
    case 401: .unauthorized
    case 404: .notFound
    case 410: .expired
    case 413: .tooLarge
    case 415: .unsupportedMedia
    case 409: .conflict
    default: .other(statusCode)
    }
}

/// The `Content-Type` header value for a multipart body built with `recognitionMultipartBody`.
public func recognitionMultipartContentType(boundary: String) -> String {
    "multipart/form-data; boundary=\(boundary)"
}

/// How a capture file travels in the `audio` multipart part.
public struct RecognitionMediaPart: Equatable, Sendable {
    public let fileName: String
    public let contentType: String

    public static let voice = RecognitionMediaPart(fileName: "meal.m4a", contentType: "audio/mp4")
    public static let photo = RecognitionMediaPart(fileName: "meal.jpg", contentType: "image/jpeg")
}

/// Extension of the local file a meal photo is stored in, beside the voice clips.
public let recognitionPhotoExtension = "jpg"

/// Whether a stored capture file is a meal photo rather than a voice clip.
public func recognitionIsPhoto(fileName: String) -> Bool {
    URL(fileURLWithPath: fileName).pathExtension.lowercased() == recognitionPhotoExtension
}

/// The part to send for a stored capture file: a photo by its extension, a voice clip otherwise.
public func recognitionMediaPart(fileName: String) -> RecognitionMediaPart {
    recognitionIsPhoto(fileName: fileName) ? .photo : .voice
}

/// Longest side, in pixels, of the photo sent for analysis: enough to tell foods apart, ~200-400 KB.
public let recognitionPhotoMaxSide: Double = 1024

/// The size to scale a photo to so its longest side is at most `maxSide`, keeping the aspect ratio.
/// Never upscales; nil for a degenerate size.
public func recognitionPhotoTargetSize(
    width: Double, height: Double, maxSide: Double = recognitionPhotoMaxSide
) -> (width: Double, height: Double)? {
    guard width > 0, height > 0, maxSide > 0 else { return nil }
    let scale = min(1, maxSide / max(width, height))
    return ((width * scale).rounded(), (height * scale).rounded())
}

/// The `POST /captures` body: an `audio` part (a voice clip, or a meal photo: see `media`), a `mode`
/// text part and any extra text `fields` (the vault drop: `vault_url`, `vault_token`, `vault_record_id`,
/// `inbox_public_key`). The server keeps the field name `audio` for both.
///
/// Built in memory and uploaded with `URLSession.upload(for:from:)`. The clip is capped at 60 s of AAC
/// and the photo at `recognitionPhotoMaxSide`, far below the server's 10 MB limit, so holding it in
/// memory is fine.
public func recognitionMultipartBody(
    boundary: String, audio: Data, media: RecognitionMediaPart = .voice, mode: String = "async",
    fields: [(name: String, value: String)] = []
) -> Data {
    var body = Data()
    func append(_ string: String) { body.append(Data(string.utf8)) }
    append("--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(media.fileName)\"\r\n")
    append("Content-Type: \(media.contentType)\r\n\r\n")
    body.append(audio)
    append("\r\n--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"mode\"\r\n\r\n")
    append("\(mode)\r\n")
    for field in fields {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n")
        append("\(field.value)\r\n")
    }
    append("--\(boundary)--\r\n")
    return body
}

private let backoffBaseSeconds: Double = 3
private let backoffCapSeconds: Double = 30

/// How long to wait before the next attempt after `consecutiveFailures` network errors in a row:
/// 3 s, doubling, capped at 30 s. Zero failures means no delay.
public func recognitionBackoffSeconds(consecutiveFailures: Int) -> Double {
    guard consecutiveFailures > 0 else { return 0 }
    // Past this many doublings the cap has long been reached; clamping also keeps the shift in range.
    let doublings = min(consecutiveFailures - 1, 10)
    return min(backoffBaseSeconds * Double(1 << doublings), backoffCapSeconds)
}
