// SPDX-License-Identifier: MPL-2.0

import Charts
import PocketNutritionCore
import SwiftUI

/// Every nutrient of one day against its target (spec 05 §6), grouped, with its coverage and the meals that
/// contributed most. Reached by tapping the day's rings; the week and the trends are one level further down.
struct DayDetailView: View {
    let day: String
    let reader: TargetsReader

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let s = Strings.active
        let lang = LanguageSettings.shared.effective
        let outcome = reader.outcome(on: day)
        let byKey = Dictionary(outcome.targets.map { ($0.nutrientKey, $0) }, uniquingKeysWith: { a, _ in a })
        let progress = Dictionary(
            reader.progress(on: day, keys: NutrientTotals.keys).map { ($0.nutrientKey, $0) },
            uniquingKeysWith: { a, _ in a })

        NavigationStack {
            List {
                Section {
                    NavigationLink(s.weekTitle) { WeekView(day: day, reader: reader) }
                    NavigationLink(s.trendsTitle) { TrendsView(day: day, reader: reader) }
                    NavigationLink(s.targetsExplanationTitle) { ExplanationView(day: day, reader: reader) }
                }
                ForEach(NutrientDisplay.groups(s), id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.keys, id: \.self) { key in
                            if let p = progress[key] {
                                row(p, target: byKey[key], s: s, lang: lang)
                            }
                        }
                    }
                }
                Section {
                    Text(s.targetsNotMedicalAdvice).font(.footnote).foregroundStyle(PnColor.inkSoft)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(PnColor.surfacePaper)
            .navigationTitle(s.dayDetailTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(s.aboutClose) { dismiss() } }
            }
        }
    }

    private func row(_ p: NutrientProgress, target: DayTarget?, s: any AppStrings, lang: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.nutrientName(p.nutrientKey)).font(.subheadline.weight(.medium)).foregroundStyle(PnColor.inkDefault)
                Spacer()
                Text(p.total.map { NutrientDisplay.format($0, unit: p.unit, lang: lang) } ?? s.unknownValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PnColor.inkDefault)
                    .monospacedDigit()
            }
            HStack(spacing: 6) {
                if let target, p.status != .noTarget {
                    Text("\(s.targetLabel) \(NutrientDisplay.targetText(target, lang: lang))")
                    if let percent = p.percent { Text("· \(percent) %") }
                    Text("· \(s.statusName(p.status))")
                } else {
                    Text(s.targetKindNone)
                }
            }
            .font(.caption)
            .foregroundStyle(PnColor.inkSoft)
            if NutrientDisplay.isSalt(p.nutrientKey), let total = p.total {
                Text("\(s.saltName) \(NutrientDisplay.formatForRing(total, key: p.nutrientKey, unit: p.unit, lang: lang))")
                    .font(.caption).foregroundStyle(PnColor.inkSoft)
            }
            if p.totalMeals > 0 && !p.isFullyCovered {
                Text(s.coverage(p.knownMeals, of: p.totalMeals)).font(.caption).foregroundStyle(PnColor.inkSoft)
            }
            if p.aboveUpperLimit, let ul = target?.upperLimit {
                Text(s.aboveUpperLimit(NutrientDisplay.format(ul, unit: p.unit, lang: lang)))
                    .font(.caption).foregroundStyle(PnColor.inkSoft)
            }
            let top = reader.topContributors(for: p.nutrientKey, on: day)
            if !top.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.topContributors).font(.caption2.weight(.semibold))
                    ForEach(Array(top.enumerated()), id: \.offset) { _, item in
                        Text("\(item.label) · \(NutrientDisplay.format(item.value, unit: p.unit, lang: lang))")
                            .font(.caption2).lineLimit(1)
                    }
                }
                .foregroundStyle(PnColor.inkSoft)
            }
            if NutrientDisplay.weeklyKeys.contains(p.nutrientKey) {
                NavigationLink(s.readWeekly) { WeekView(day: day, reader: reader) }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PnColor.brandLeafDeep)
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(PnColor.surfaceCard)
    }
}

/// The 7 days ending on a day: each nutrient's average, against the targets of each day.
struct WeekView: View {
    let day: String
    let reader: TargetsReader

    var body: some View {
        let s = Strings.active
        let lang = LanguageSettings.shared.effective
        let averages = Dictionary(reader.week(ending: day, keys: NutrientTotals.keys).map { ($0.nutrientKey, $0) }, uniquingKeysWith: { a, _ in a })
        List {
            ForEach(NutrientDisplay.groups(s), id: \.title) { group in
                Section(group.title) {
                    ForEach(group.keys, id: \.self) { key in
                        if let a = averages[key] {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.nutrientName(key)).font(.subheadline)
                                    Text(s.weekDaysWithData(a.daysWithData)).font(.caption2).foregroundStyle(PnColor.inkSoft)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(a.averageTotal.map { NutrientDisplay.format($0, unit: a.unit, lang: lang) } ?? "–")
                                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                                    if let percent = a.averagePercent {
                                        Text("\(percent) %").font(.caption).foregroundStyle(PnColor.inkSoft)
                                    }
                                }
                            }
                            .listRowBackground(PnColor.surfaceCard)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PnColor.surfacePaper)
        .navigationTitle(s.weekTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One nutrient over 7, 30 or 90 days, with the target line, which steps where the profile changed.
struct TrendsView: View {
    let day: String
    let reader: TargetsReader

    @State private var key = "energyKcal"
    @State private var range = 7

    var body: some View {
        let s = Strings.active
        let points = reader.trend(for: key, days: range, ending: day)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker(s.trendsTitle, selection: $key) {
                    ForEach(NutrientTotals.keys, id: \.self) { Text(s.nutrientName($0)).tag($0) }
                }
                .pickerStyle(.menu)
                Picker(s.trendsTitle, selection: $range) {
                    ForEach([7, 30, 90], id: \.self) { Text(s.trendRange($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                Chart {
                    ForEach(points) { point in
                        if let total = point.total {
                            BarMark(x: .value("day", point.date, unit: .day), y: .value(s.trendTotal, total))
                                .foregroundStyle(PnColor.brandLeaf.opacity(0.75))
                        }
                    }
                    ForEach(points) { point in
                        if let target = point.target {
                            LineMark(x: .value("day", point.date, unit: .day), y: .value(s.trendTarget, target))
                                .interpolationMethod(.stepCenter)
                                .foregroundStyle(PnColor.inkSoft)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        }
                    }
                }
                .frame(height: 240)
                .padding(12)
                .pnCard()
            }
            .padding(20)
        }
        .background(PnColor.surfacePaper)
        .navigationTitle(s.trendsTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
