// SPDX-License-Identifier: MPL-2.0

import Foundation

/// A random passphrase for a new vault account: five words drawn from the 7776-word EFF list, about
/// 64 bits of entropy. Always English, whatever the app language, so the same list serves every
/// language and the words stay easy to read out or write down.
///
/// The passphrase is the only thing between an attacker with a copy of the vault and the person's
/// journal, and that attacker can guess offline. A person-chosen phrase is typically far weaker.
public enum VaultPassphraseSuggestion {

    public static let wordCount = 5

    /// Words joined by hyphens: no space to be trimmed or mistyped, and still readable.
    public static func make() -> String {
        var generator = SystemRandomNumberGenerator()
        return make(using: &generator)
    }

    /// `Int.random(in:using:)` is uniform (no modulo bias), so every word is equally likely.
    static func make(using generator: inout some RandomNumberGenerator) -> String {
        let words = EffLongWordlist.words
        return (0..<wordCount)
            .map { _ in words[Int.random(in: 0..<words.count, using: &generator)] }
            .joined(separator: "-")
    }
}
