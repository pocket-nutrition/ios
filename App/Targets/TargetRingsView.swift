// SPDX-License-Identifier: MPL-2.0

import PocketNutritionCore
import SwiftUI

/// One compact watch-list ring (spec 05 §6). It fills toward 100 %, and past 100 % a second lap fills in a
/// muted tone: never red, and no warning for "over". A range is full anywhere between its bounds. Partial
/// coverage (a meal without a figure) draws a lighter fill.
struct TargetRing: View {
    let progress: NutrientProgress
    let target: DayTarget?
    var diameter: CGFloat = 46

    private var fraction: Double { Double(progress.percent ?? 0) / 100 }

    /// Between the bounds of a range the ring is simply full.
    private var isWithinRange: Bool {
        guard let lo = target?.min, let hi = target?.max, lo != hi else { return false }
        return progress.status == .ok
    }

    private var lineWidth: CGFloat { diameter * 0.13 }

    var body: some View {
        let first = isWithinRange ? 1 : min(fraction, 1)
        let lap = isWithinRange ? 0 : min(max(fraction - 1, 0), 1)
        ZStack {
            Circle().stroke(PnColor.surfaceCream, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: first)
                .stroke(PnColor.brandLeaf.opacity(progress.isFullyCovered ? 1 : 0.45),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if lap > 0 {
                Circle()
                    .trim(from: 0, to: lap)
                    .stroke(PnColor.inkSoft.opacity(0.4), style: StrokeStyle(lineWidth: lineWidth * 0.6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(progress.percent.map { "\($0)" } ?? "–")
                .font(.system(size: diameter * 0.26, weight: .semibold, design: .rounded))
                .foregroundStyle(PnColor.inkDefault)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeOut(duration: 0.3), value: progress.percent)
    }
}

/// The rings of one journal day, in watch-list order. Nutrients with no target get no ring: today's value
/// against the person's own usual instead ("Salt 6.2 g · usual 5.1 g").
struct DayRingsRow: View {
    let day: String
    let reader: TargetsReader
    let keys: [String]

    var body: some View {
        let s = Strings.active
        let lang = LanguageSettings.shared.effective
        let outcome = reader.outcome(on: day)
        let byKey = Dictionary(outcome.targets.map { ($0.nutrientKey, $0) }, uniquingKeysWith: { a, _ in a })
        let progress = reader.progress(on: day, keys: keys)
        let ringed = progress.filter { $0.status != .noTarget }
        let plain = progress.filter { $0.status == .noTarget }

        VStack(alignment: .leading, spacing: 10) {
            if case .unsupported(let reason, _) = outcome {
                Text(s.targetsUnsupported(reason)).font(.caption).foregroundStyle(PnColor.inkSoft)
            }
            if !ringed.isEmpty {
                // All rings at a glance when they fit, shared evenly across the width; a long watch list
                // (the "everything" preset) falls back to a horizontal scroll instead of clipping a ring.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(ringed, id: \.nutrientKey) { p in
                            ringCell(p, target: byKey[p.nutrientKey], s: s, lang: lang)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 2)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(ringed, id: \.nutrientKey) { p in
                                ringCell(p, target: byKey[p.nutrientKey], s: s, lang: lang)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            ForEach(plain, id: \.nutrientKey) { p in
                usualLine(p, s: s, lang: lang)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func ringCell(_ p: NutrientProgress, target: DayTarget?, s: any AppStrings, lang: String) -> some View {
        VStack(spacing: 3) {
            TargetRing(progress: p, target: target)
            Text(NutrientDisplay.ringName(p.nutrientKey, s))
                .font(.caption2.weight(.medium))
                .foregroundStyle(PnColor.inkDefault)
                .lineLimit(1)
            Text(p.total.map { NutrientDisplay.formatForRing($0, key: p.nutrientKey, unit: p.unit, lang: lang) } ?? "–")
                .font(.caption2)
                .foregroundStyle(PnColor.inkSoft)
                .monospacedDigit()
            if NutrientDisplay.isLimit(target) {
                Text(s.ringLimit.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.5)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .foregroundStyle(PnColor.inkSoft)
                    .overlay(Capsule().stroke(PnColor.inkLine))
            }
        }
        .frame(minWidth: 58)
        .accessibilityElement(children: .combine)
    }

    private func usualLine(_ p: NutrientProgress, s: any AppStrings, lang: String) -> some View {
        let comparison = reader.comparison(for: p.nutrientKey, on: day)
        var text = NutrientDisplay.ringName(p.nutrientKey, s) + " "
            + (p.total.map { NutrientDisplay.formatForRing($0, key: p.nutrientKey, unit: p.unit, lang: lang) } ?? s.unknownValue)
        if let average = comparison.average {
            text += " · " + s.ringUsual(NutrientDisplay.formatForRing(average, key: p.nutrientKey, unit: p.unit, lang: lang))
        }
        return Text(text).font(.caption).foregroundStyle(PnColor.inkSoft)
    }
}
