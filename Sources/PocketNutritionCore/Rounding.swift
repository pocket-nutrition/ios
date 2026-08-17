// SPDX-License-Identifier: MPL-2.0

/// Rounds half away from zero for the positive quantities this app deals in: a tie always goes to
/// the larger value.
///
/// This is the one rounding rule in Pocket Nutrition, shared with the web client and Android through
/// the `rounding` vector suite. Every weight and portion label goes through it.
///
/// **Do not replace this with `value.rounded()`.** Swift's default rounding rule happens to agree
/// here, but the trap is real on another platform: Kotlin's `kotlin.math.round` breaks ties towards
/// even, so `round(12.5)` is 12 rather than 13. The contract pins the behaviour as `floor(x + 0.5)`
/// precisely so that no platform's idea of "round" gets a vote.
///
/// A user reaches the divergent case by tapping "Demi": an 80 g item against a 64 g portion is 1.25
/// portions, which reads "≈ 1,3 portion" under this rule and "≈ 1,2 portion" under round-half-even.
/// Nothing errors; the clients simply disagree.
public func roundHalfUp(_ value: Double) -> Int {
    Int((value + 0.5).rounded(.down))
}
