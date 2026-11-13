// SPDX-License-Identifier: MPL-2.0

import Foundation
import Observation

/// The app's active display language: French or English, either following the device's own
/// language or pinned by an explicit choice in the "Langue"/"Language" section of `AboutView`.
///
/// WHY THIS IS A CLASS, NOT AN ENUM LIKE `ApiSettings`
/// `ApiSettings` is read imperatively, at request time, and nothing needs to know when it changes.
/// A language setting is read inside nearly every screen's `body`, so a plain static computed
/// property would leave already-rendered screens showing stale text after a switch — SwiftUI has no
/// way to know a bare `UserDefaults` read changed. `@Observable` fixes that, and needs no dependency
/// injection to do it: the Observation framework tracks a property the moment it is *read* during a
/// View's `body` evaluation, no matter how the reference was obtained — a plain `LanguageSettings.
/// shared.effective` read directly inside `body` re-renders that view automatically the moment
/// `setOverride` is called anywhere, the same as Apple's own sample code reads global model
/// singletons directly rather than through `.environment(...)`.
///
/// `PocketNutritionApi` is the one exception: it stays a plain `String` parameter, set by its caller
/// before the call, rather than reading `LanguageSettings.shared` from inside the actor — crossing
/// into a `@MainActor` type from a different actor would need an `await` for what should be an
/// instant, synchronous read, and actors have no `body` evaluation for Observation to hook into
/// anyway.
///
/// `@MainActor`: this holds mutable state shared across the app, and pinning it to the main actor —
/// where every reader and writer already runs, being UI-driven — is what makes it safe under strict
/// concurrency without an unchecked `Sendable` conformance.
@MainActor
@Observable
public final class LanguageSettings {

    public static let shared = LanguageSettings()

    private static let defaultsKey = "languageOverride"

    /// `nil` means "follow the device" — the `effective` computation below applies the fallback rule.
    /// An explicit `"fr"`/`"en"` overrides that rule until `setOverride(nil)` clears it.
    public private(set) var override: String?

    private init() {
        override = UserDefaults.standard.string(forKey: Self.defaultsKey)
    }

    /// What the app actually displays right now: the override when one is set, otherwise French only
    /// when the device's own language is French — English for every other device language, which is
    /// the "English unless the device is French" rule this type exists to implement.
    public var effective: String {
        if let override { return override }
        return Locale.current.language.languageCode?.identifier == "fr" ? "fr" : "en"
    }

    /// Sets an explicit override, or clears it back to "follow the device" when `lang` is `nil`.
    public func setOverride(_ lang: String?) {
        override = lang
        if let lang {
            UserDefaults.standard.set(lang, forKey: Self.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        }
    }
}
