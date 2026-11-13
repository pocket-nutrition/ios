// SPDX-License-Identifier: MPL-2.0

/// Resolves the cooked/raw weight ratio for a cooking method from what Knowledge provides, and only
/// from that.
///
/// Three branches, and their order is load-bearing:
///
/// 1. `raw` means no conversion, and it is answered before any lookup. A raw request must return 1
///    even when the ingredient carries a `cooked` yield, so a port that folds this in after the
///    dictionary lookup passes four of the five vectors and silently cooks raw food.
/// 2. A method-specific key wins, letting an ingredient override the generic ratio for one method.
/// 3. The generic `cooked` key is the fallback. This is the rice bug: Knowledge aggregates most yields
///    under `cooked`, so a request for `boiled` that does not fall back returns 1 and reports raw rice
///    weight for a cooked portion.
///
/// **Nothing is invented.** With no yield at all the answer is 1 — a missing ratio is a gap to report
/// through the feedback channel and fix in Knowledge, not something for the client to estimate. A
/// guessed factor would be indistinguishable from a real one in the response.
///
/// Mirrors the router in `pocket-nutrition/ml` and is pinned by the `yield-factor` suite of the
/// shared behavioural corpus.
public func resolveYieldFactor(_ yieldFactors: [String: Double], method: String) -> Double {
    if method == "raw" { return 1 }
    return yieldFactors[method] ?? yieldFactors["cooked"] ?? 1
}
