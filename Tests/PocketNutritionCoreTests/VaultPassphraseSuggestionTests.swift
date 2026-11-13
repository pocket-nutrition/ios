// SPDX-License-Identifier: MPL-2.0

import Testing

@testable import PocketNutritionCore

@Suite("Vault passphrase suggestion")
struct VaultPassphraseSuggestionTests {

    @Test("The list is the EFF long list: 7776 distinct lowercase words")
    func wordlistIsIntact() {
        let words = EffLongWordlist.words
        #expect(words.count == 7776)
        #expect(Set(words).count == 7776)
        #expect(words.first == "abacus")
        #expect(words.last == "zoom")
        #expect(words.allSatisfy { $0 == $0.lowercased() && !$0.isEmpty })
    }

    @Test("A suggestion is five listed words joined by hyphens and is accepted as a passphrase")
    func shape() {
        let suggestion = VaultPassphraseSuggestion.make()
        let parts = suggestion.split(separator: "-").map(String.init)
        #expect(parts.count == VaultPassphraseSuggestion.wordCount)
        #expect(parts.allSatisfy { EffLongWordlist.words.contains($0) })
        #expect(isAcceptableVaultPassphrase(suggestion))
    }

    @Test("Two suggestions differ")
    func random() {
        #expect(VaultPassphraseSuggestion.make() != VaultPassphraseSuggestion.make())
    }

    @Test("The generator is the one given, so the draw is reproducible in tests")
    func injectedGenerator() {
        var first = SeededGenerator(seed: 7)
        var second = SeededGenerator(seed: 7)
        #expect(VaultPassphraseSuggestion.make(using: &first) == VaultPassphraseSuggestion.make(using: &second))
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
