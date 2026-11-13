// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Lets a contributor point the app at their own backend instead of the official API.
///
/// Persisted in `UserDefaults` rather than Keychain: the override is a plain URL, not a secret, and
/// there is no reason it should survive past a reinstall. An absent or blank value means "use the
/// official server" — that is what lets `SettingsView`'s "back to official" action work by clearing the
/// key rather than by having to know `PocketNutritionApi.defaultBaseURL`'s literal value.
enum ApiSettings {

    private static let defaultsKey = "customApiBaseURL"

    /// The raw text the user saved, or `nil` if no override is set — regardless of whether that text
    /// still parses as a valid URL. `SettingsView` uses this, not `baseURL`, to prefill the text field:
    /// showing back exactly what was typed, even if it has since become invalid, is what lets a typo
    /// be corrected instead of silently discarded.
    static var customRawValue: String? {
        UserDefaults.standard.string(forKey: defaultsKey)
    }

    /// What `PocketNutritionApi` actually sends every request to: the saved override when one is set
    /// and still valid, otherwise `PocketNutritionApi.defaultBaseURL`. Computed rather than cached —
    /// a change made from `SettingsView` must take effect on the very next request, not after the app is
    /// relaunched.
    static var baseURL: URL {
        guard let raw = customRawValue, let url = validatedURL(raw) else {
            return PocketNutritionApi.defaultBaseURL
        }
        return url
    }

    /// Validates `raw` and, if it parses, saves it as the override. Returns `false` without touching
    /// storage otherwise — a bare host like `192.168.1.5` with no scheme would otherwise silently
    /// become a relative path with no server at all, which is worse than rejecting it up front.
    ///
    /// A blank string is treated as "reset", since that is what an emptied text field means.
    @discardableResult
    static func setCustomBaseURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            reset()
            return true
        }
        guard validatedURL(trimmed) != nil else { return false }
        UserDefaults.standard.set(trimmed, forKey: defaultsKey)
        return true
    }

    /// Restores the official server.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    /// A URL only counts as a usable override if it has both a scheme and a host — `URL(string:)`
    /// alone happily parses `"api.pocketnutrition.org"` into a relative path with neither, which would
    /// then resolve every request against nothing.
    private static func validatedURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme, url.host != nil else { return nil }
        guard ["http", "https"].contains(scheme.lowercased()) else { return nil }
        return url
    }
}
