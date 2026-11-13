// SPDX-License-Identifier: MPL-2.0

import Foundation
import PocketNutritionCore

/// Where to send recordings: an https URL and, only for servers that still use a shared key, that key.
/// On the official server there is none: a dictation is authenticated by its vault drop token.
struct RecognitionConfiguration: Sendable, Equatable {
    let baseURL: URL
    let apiKey: String?
}

/// The voice-recognition server the user points the app at. Separate from `ApiSettings`, which
/// overrides the nutrition API and is deliberately left alone.
///
/// The URL is a plain preference (`UserDefaults`); the API key is a secret (Keychain).
enum RecognitionSettings {

    private static let urlKey = "recognitionServerURL"

    /// The raw URL text last saved, used to prefill the field even if it no longer validates.
    static var rawURL: String? { UserDefaults.standard.string(forKey: urlKey) }

    static func hasApiKey(secrets: any SecretStoring = KeychainSecretStore.recognitionApiKey) -> Bool {
        ((try? secrets.read()) ?? nil)?.isEmpty == false
    }

    /// The saved server, or the official one. The key is attached only when it was saved for THIS host: a
    /// key kept from another server (or with no host on record) is never sent to the one in use.
    static func configuration(
        secrets: any SecretStoring = KeychainSecretStore.recognitionApiKey
    ) -> RecognitionConfiguration {
        let url = rawURL.flatMap(validatedRecognitionServerURL)
            ?? validatedRecognitionServerURL(defaultRecognitionServerURL)!
        let stored = ((try? secrets.read()) ?? nil).flatMap { $0.isEmpty ? nil : $0 }
        let trusted = stored != nil
            && !recognitionHostChanged(from: rawURL, to: url.absoluteString, hasStoredKey: true)
        return RecognitionConfiguration(baseURL: url, apiKey: trusted ? stored : nil)
    }

    enum SaveError: Error, Equatable {
        case invalidURL
        case keychain
        /// The server host changed: the saved key belongs to the old host and must not be sent there.
        case keyRequiredForNewHost
    }

    /// Validates and stores both values. Nothing is written if either is invalid, so a rejected save
    /// never leaves a half-configured state behind.
    static func save(
        urlText: String, apiKey: String,
        secrets: any SecretStoring = KeychainSecretStore.recognitionApiKey
    ) throws(SaveError) {
        guard let url = validatedRecognitionServerURL(urlText) else { throw .invalidURL }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            // No key is fine (the official server needs none). Changing only the path or port keeps a
            // stored key, and a new HOST never inherits the old host's key.
            if hasApiKey(secrets: secrets),
               recognitionHostChanged(from: rawURL, to: url.absoluteString, hasStoredKey: true) {
                throw .keyRequiredForNewHost
            }
        } else {
            do { try secrets.write(key) } catch { throw .keychain }
        }
        UserDefaults.standard.set(url.absoluteString, forKey: urlKey)
    }

    /// Removes the key and then the URL. Returns false if the Keychain delete failed; the URL is then
    /// kept so the host-change protection in `save` still guards the key that is still stored.
    @discardableResult
    static func clear(secrets: any SecretStoring = KeychainSecretStore.recognitionApiKey) -> Bool {
        do { try secrets.delete() } catch { return false }
        UserDefaults.standard.removeObject(forKey: urlKey)
        return true
    }
}
