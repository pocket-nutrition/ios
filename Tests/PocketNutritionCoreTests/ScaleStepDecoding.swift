// SPDX-License-Identifier: MPL-2.0

import PocketNutritionCore

/// Decodes the `ServingUnit` and `ScaleStep` shapes out of the untyped corpus.
///
/// Shared by the build-anchors and step-label suites, and by the three still to come that speak the
/// same shapes — step-raw-weight, shortcut-profile and describe-quantity. It lives beside the tests
/// rather than in `VectorCorpus` because the reader is deliberately suite-agnostic: it knows the
/// corpus structure and nothing about any individual suite's payload.
///
/// Returns nil on anything unexpected rather than trapping, so a malformed case is reported as one
/// named mismatch instead of taking the whole run down.
enum ScaleStepDecoding {

    static func servingUnit(_ raw: [String: Any]) -> ServingUnit? {
        guard let unit = raw["unit"] as? String,
              let labelFr = raw["labelFr"] as? String,
              let volumeMl = VectorCorpus.double(raw["volumeMl"]),
              let grams = VectorCorpus.double(raw["grams"])
        else { return nil }
        return ServingUnit(unit: unit, labelFr: labelFr, volumeMl: volumeMl, grams: grams)
    }

    /// `emoji` is ABSENT rather than null for an unrecognised unit, so a missing key decodes to nil
    /// and the two are not distinguishable here — which matches how the function models it.
    static func shortcut(_ raw: [String: Any]) -> Shortcut? {
        switch raw["kind"] as? String {
        case "multiplier":
            guard let label = raw["label"] as? String,
                  let factor = VectorCorpus.double(raw["factor"])
            else { return nil }
            return .multiplier(label: label, factor: factor)
        case "increment":
            guard let label = raw["label"] as? String,
                  let grams = VectorCorpus.int(raw["grams"])
            else { return nil }
            return .increment(label: label, emoji: raw["emoji"] as? String, grams: grams)
        default:
            return nil
        }
    }

    static func anchor(_ raw: [String: Any]) -> QuantityAnchor? {
        guard let label = raw["label"] as? String,
              let grams = VectorCorpus.double(raw["grams"])
        else { return nil }
        return QuantityAnchor(label: label, grams: grams)
    }

    static func quantityContext(_ raw: [String: Any]) -> QuantityContext? {
        guard let portionG = VectorCorpus.double(raw["portionG"]),
              let displayUnit = raw["displayUnit"] as? String
        else { return nil }
        return QuantityContext(
            servingMode: raw["servingMode"] as? String,
            itemUnitG: VectorCorpus.double(raw["itemUnitG"]),
            itemLabel: raw["itemLabel"] as? String,
            portionG: portionG,
            displayUnit: displayUnit
        )
    }

    static func step(_ raw: [String: Any]) -> ScaleStep? {
        switch raw["kind"] as? String {
        case "factor":
            guard let factor = VectorCorpus.double(raw["factor"]),
                  let label = raw["label"] as? String
            else { return nil }
            return .factor(factor: factor, label: label)
        case "unit":
            guard let rawUnit = raw["unit"] as? [String: Any],
                  let unit = servingUnit(rawUnit),
                  let count = VectorCorpus.double(raw["count"])
            else { return nil }
            return .unit(unit: unit, count: count)
        default:
            return nil
        }
    }
}
