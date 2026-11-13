// SPDX-License-Identifier: MPL-2.0

import Foundation
import PocketNutritionCore

/// Client for one vault server. Credentials (the device key) are passed per call by the caller, so the
/// client itself holds nothing secret and can be created for the "is this a vault?" check before anyone
/// has logged in.
///
/// Like `RecognitionClient`: ephemeral session (no cookies or cache), redirects refused (a redirect
/// would carry the login hash or the device key somewhere else), and a hard cap on response size.
public actor VaultClient: VaultServing, VaultSecurityServing {

    public static let maxResponseBytes = 2 * 1024 * 1024

    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
            return
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config, delegate: VaultNoRedirectDelegate(), delegateQueue: nil)
    }

    deinit { session.finishTasksAndInvalidate() }

    // MARK: - Public (no credentials)

    public func serverInfo() async throws -> VaultServerInfo {
        try decode(await call(segments: ["server-info"], method: "GET"))
    }

    /// The account's KDF settings. Unknown usernames get stable fake ones, so this never fails for them.
    public func prelogin(username: String) async throws -> VaultKdf {
        try decode(await call(segments: ["accounts", "prelogin"], method: "POST", body: ["username": username]))
    }

    public func register(_ request: VaultRegisterRequest) async throws -> VaultSession {
        try decode(await call(segments: ["accounts"], method: "POST", body: request))
    }

    public func login(_ request: VaultLoginRequest) async throws -> VaultSession {
        try decode(await call(segments: ["login"], method: "POST", body: request, isLogin: true))
    }

    // MARK: - With a device key

    /// Unlinks this device: the server revokes the key used for the call.
    public func logout(apiKey: String) async throws {
        _ = try await call(segments: ["logout"], method: "POST", key: apiKey)
    }

    /// Erases the account and everything stored for it. Needs the login hash as proof of the passphrase.
    public func deleteAccount(apiKey: String, authHash: String) async throws {
        _ = try await call(segments: ["account"], method: "DELETE", body: ["auth_hash": authHash], key: apiKey)
    }

    public func createDrop(apiKey: String, _ request: VaultDropRequest) async throws -> VaultDropToken {
        try decode(await call(segments: ["drops"], method: "POST", body: request, key: apiKey))
    }

    public func sync(apiKey: String, since: Int) async throws -> VaultSyncPage {
        try decode(
            await call(
                segments: ["sync"], method: "GET", key: apiKey,
                query: [URLQueryItem(name: "since", value: String(since))]))
    }

    public func putRecord(apiKey: String, id: String, _ write: VaultRecordWrite) async throws {
        _ = try await call(segments: ["records", id], method: "PUT", body: write, key: apiKey)
    }

    public func deleteRecord(apiKey: String, id: String, revision: Int) async throws {
        _ = try await call(
            segments: ["records", id], method: "DELETE", key: apiKey,
            query: [URLQueryItem(name: "revision", value: String(revision))])
    }

    // MARK: - Account security

    public func listDevices(apiKey: String) async throws -> [VaultDevice] {
        try decode(await call(segments: ["keys"], method: "GET", key: apiKey))
    }

    public func revokeDevice(apiKey: String, id: String) async throws {
        _ = try await call(segments: ["keys", id], method: "DELETE", key: apiKey)
    }

    public func keyring(apiKey: String) async throws -> VaultKeyring {
        try decode(await call(segments: ["keyring"], method: "GET", key: apiKey))
    }

    public func resetPassphrase(
        apiKey: String, _ request: VaultPassphraseResetRequest
    ) async throws -> VaultPassphraseChanged {
        try decode(
            await call(segments: ["account", "passphrase", "reset"], method: "POST", body: request, key: apiKey))
    }

    public func twoFactorStatus(apiKey: String) async throws -> VaultTwoFactorStatus {
        try decode(await call(segments: ["account", "two-factor"], method: "GET", key: apiKey))
    }

    public func setUpTwoFactor(apiKey: String, authHash: String) async throws -> VaultTwoFactorSetup {
        try decode(
            await call(
                segments: ["account", "two-factor", "setup"], method: "POST", body: ["auth_hash": authHash],
                key: apiKey))
    }

    public func enableTwoFactor(apiKey: String, code: String) async throws -> VaultRecoveryCodes {
        try decode(
            await call(segments: ["account", "two-factor", "enable"], method: "POST", body: ["code": code], key: apiKey))
    }

    public func disableTwoFactor(apiKey: String, authHash: String, code: String) async throws {
        _ = try await call(
            segments: ["account", "two-factor", "disable"], method: "POST",
            body: ["auth_hash": authHash, "code": code], key: apiKey)
    }

    // MARK: - Plumbing

    /// One request. Returns the body of a 2xx answer; any other answer is a `VaultError.outcome`.
    private func call<Body: Encodable>(
        segments: [String], method: String, body: Body? = nil as [String: String]?,
        key: String? = nil, isLogin: Bool = false, query: [URLQueryItem] = []
    ) async throws -> Data {
        guard let url = vaultURL(base: baseURL, segments: segments, query: query) else {
            throw VaultError.malformedResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? encoder.encode(body)
        }

        let (data, response) = try await perform(request)
        let outcome = classifyVaultHTTP(
            status: response.statusCode,
            errorCode: Self.errorCode(in: data),
            retryAfter: response.value(forHTTPHeaderField: "Retry-After"),
            isLogin: isLogin
        )
        guard outcome == .success else { throw VaultError.outcome(outcome) }
        return data
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        do { return try decoder.decode(Response.self, from: data) } catch { throw VaultError.malformedResponse }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw VaultError.malformedResponse }
            if response.expectedContentLength > Int64(Self.maxResponseBytes) { throw VaultError.malformedResponse }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > Self.maxResponseBytes { throw VaultError.malformedResponse }
            }
            return (data, http)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw VaultError.offline
        }
    }

    /// FastAPI nests it: `{"detail":{"error":"username_taken"}}`. A plain-string `detail` has none.
    private static func errorCode(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = object["detail"] as? [String: Any]
        else { return nil }
        return detail["error"] as? String
    }
}


/// Refuses every redirect. The vault has no reason to redirect, and following one would carry the login
/// hash or the device key to wherever the response points.
final class VaultNoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
