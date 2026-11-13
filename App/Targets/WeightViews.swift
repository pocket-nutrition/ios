// SPDX-License-Identifier: MPL-2.0

import Charts
import PocketNutritionCore
import SwiftUI

/// The weight log: entries, a small trend chart of the entries and their 7-day mean, quick entry and deletion.
/// Entered by hand only; it never leaves the phone except in the encrypted vault.
struct WeightView: View {
    @Environment(TargetsStore.self) private var targets
    @State private var isLogging = false

    var body: some View {
        let s = Strings.active
        let lang = LanguageSettings.shared.effective
        let entries = targets.weightEntries
        List {
            if !entries.isEmpty {
                Section(s.weightTrend) {
                    Chart {
                        ForEach(entries, id: \.date) { entry in
                            PointMark(x: .value(s.weightDate, TargetsReader.date(of: entry.date), unit: .day), y: .value("kg", entry.kg))
                                .foregroundStyle(PnColor.brandLeaf)
                        }
                        ForEach(entries, id: \.date) { entry in
                            if let mean = weightForDay(entries, day: entry.date) {
                                LineMark(x: .value(s.weightDate, TargetsReader.date(of: entry.date), unit: .day), y: .value(s.weightMean, mean))
                                    .foregroundStyle(PnColor.inkSoft)
                            }
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 180)
                    Text(s.weightMean).font(.caption).foregroundStyle(PnColor.inkSoft)
                }
                .listRowBackground(PnColor.surfaceCard)
            }
            Section(s.weightEntries) {
                if entries.isEmpty {
                    Text(s.weightNone).foregroundStyle(PnColor.inkSoft)
                }
                ForEach(entries.reversed(), id: \.date) { entry in
                    HStack {
                        Text(TargetsReader.date(of: entry.date), format: .dateTime.day().month().year())
                        Spacer()
                        Text("\(formatNumber(entry.kg, lang: lang)) kg").monospacedDigit()
                    }
                }
                .onDelete { offsets in
                    let reversed = Array(entries.reversed())
                    offsets.map { reversed[$0].date }.forEach(targets.deleteWeight)
                }
            }
            .listRowBackground(PnColor.surfaceCard)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PnColor.surfacePaper)
        .navigationTitle(s.weightTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isLogging = true } label: { Label(s.weightLog, systemImage: "plus") }
            }
        }
        .sheet(isPresented: $isLogging) { WeightEntrySheet() }
    }
}

/// Quick weight entry, today by default. A second entry for the same date replaces the first.
struct WeightEntrySheet: View {
    @Environment(TargetsStore.self) private var targets
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var kgText = ""
    @FocusState private var isFocused: Bool

    private var kg: Double? {
        Double(kgText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
            .flatMap { (20...400).contains($0) ? $0 : nil }
    }

    var body: some View {
        let s = Strings.active
        NavigationStack {
            Form {
                LabeledContent(s.weightKg) {
                    TextField("70", text: $kgText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isFocused)
                        .accessibilityIdentifier("weight-kg")
                }
                DatePicker(s.weightDate, selection: $date, in: ...Date(), displayedComponents: .date)
            }
            .navigationTitle(s.weightLog)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(s.targetCancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(s.weightSave) {
                        guard let kg else { return }
                        targets.logWeight(date: localDay(date), kg: kg)
                        dismiss()
                    }
                    .disabled(kg == nil)
                    .accessibilityIdentifier("weight-save")
                }
            }
            .onAppear {
                if let last = targets.weightEntries.last ?? targets.latestProfile.map({ WeightEntry(date: "", kg: $0.weightKg) }) {
                    kgText = formatNumber(last.kg, lang: LanguageSettings.shared.effective)
                }
                isFocused = true
            }
        }
        .presentationDetents([.medium])
    }
}
