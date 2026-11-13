// SPDX-License-Identifier: MPL-2.0

import SwiftUI
import PocketNutritionCore

/// Review of a `ready` entry, from the result stored on the phone — no network needed to open it.
///
/// Each item shows its candidates as a single-choice list (best preselected) and a skip toggle.
/// "Add to meal" resolves the choices and hands the rows to the meal builder; items that cannot be
/// built are skipped and named, never guessed.
struct VoiceReviewView: View {

    let localId: String
    let onImport: ([MealIngredient]) -> Void

    @Environment(RecognitionEntryStore.self) private var store
    @Environment(RecognitionCoordinator.self) private var coordinator

    /// Chosen candidate index per item; absent means the best (first).
    @State private var chosen: [Int: Int] = [:]
    @State private var skipped: Set<Int> = []
    @State private var isImporting = false
    @State private var report: ImportReport?

    var body: some View {
        let s = Strings.active
        Group {
            if let entry = store.entry(localId), let result = entry.result {
                List {
                    Section(entry.isPhoto == true ? s.photoDescriptionTitle : s.voiceTranscriptTitle) {
                        Text(result.transcript).font(.subheadline).foregroundStyle(PnColor.inkDefault)
                    }
                    ForEach(Array(result.items.enumerated()), id: \.offset) { index, item in
                        itemSection(index: index, item: item)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .bottom) { addButton(result) }
            } else {
                ProgressView()
            }
        }
        .background(PnColor.surfacePaper)
        .navigationTitle(s.voiceReviewTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(alertTitle, isPresented: Binding(get: { report != nil }, set: { if !$0 { report = nil } })) {
            // A transient lookup failure may succeed next time: offer to retry, and when the user
            // continues anyway the entry stays (see `handOff`).
            if let report, report.skipped.contains(where: { $0.kind == .lookupFailed }),
               let result = store.entry(localId)?.result {
                Button(s.voiceRetryLookup) { Task { await addToMeal(result) } }
            }
            if let report, !report.rows.isEmpty {
                Button(s.voiceContinue) { handOff(report) }
            }
            Button(s.aboutClose, role: .cancel) {}
        } message: {
            Text(skippedMessage)
        }
    }

    private func itemSection(index: Int, item: RecognitionItem) -> some View {
        let s = Strings.active
        let isSkipped = skipped.contains(index) || item.candidates.isEmpty
        return Section {
            if item.candidates.isEmpty {
                Text(s.voiceNoCandidates).font(.footnote).foregroundStyle(PnColor.inkSoft)
            } else {
                Toggle(s.voiceSkipItem, isOn: Binding(
                    get: { skipped.contains(index) },
                    set: { if $0 { skipped.insert(index) } else { skipped.remove(index) } }
                ))
                ForEach(Array(item.candidates.enumerated()), id: \.offset) { position, candidate in
                    Button {
                        chosen[index] = position
                    } label: {
                        HStack {
                            Text(candidate.name ?? candidate.ingredientId).foregroundStyle(PnColor.inkDefault)
                            Spacer()
                            if (chosen[index] ?? 0) == position {
                                Image(systemName: "checkmark").foregroundStyle(PnColor.brandLeafDeep)
                            }
                        }
                    }
                    .disabled(isSkipped)
                }
            }
        } header: {
            Text(item.rawText)
        }
    }

    private func addButton(_ result: RecognitionResult) -> some View {
        let s = Strings.active
        return Button {
            Task { await addToMeal(result) }
        } label: {
            if isImporting { ProgressView() } else { Text(s.voiceAddToMeal) }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isImporting)
        .padding(16)
        .background(PnColor.surfacePaper)
    }

    private func addToMeal(_ result: RecognitionResult) async {
        isImporting = true
        let selections = result.items.enumerated().map { index, item -> ImportSelection in
            let isSkipped = skipped.contains(index) || item.candidates.isEmpty
            let candidate = isSkipped ? nil : item.candidates[min(chosen[index] ?? 0, item.candidates.count - 1)]
            return ImportSelection(item: item, candidate: candidate)
        }
        let outcome = await RecognitionImporter.resolve(selections, lang: LanguageSettings.shared.effective)
        isImporting = false
        if outcome.skipped.isEmpty, !outcome.rows.isEmpty {
            handOff(outcome)
        } else {
            report = outcome
        }
    }

    /// After a hand-off the entry (and any server copy) is deleted — but only if every skipped item was
    /// skipped for a definitive reason. If a lookup merely failed (network, 5xx), the entry stays so
    /// the user can come back and try those items again.
    private func handOff(_ report: ImportReport) {
        if canDiscardAfterImport(skips: report.skipped.map(\.kind)) {
            coordinator.delete(localId)
        }
        onImport(report.rows)
    }

    private var alertTitle: String {
        let s = Strings.active
        return (report?.rows.isEmpty ?? true) ? s.voiceNothingImported : s.voiceSkippedTitle
    }

    private var skippedMessage: String {
        let s = Strings.active
        return (report?.skipped ?? []).map { item in
            let reason = switch item.kind {
            case .noCandidate: s.voiceReasonNoCandidate
            case .unknownIngredient: s.voiceReasonUnknown
            case .notBuildable: s.voiceReasonNotBuildable
            case .lookupFailed: s.voiceReasonLookupFailed
            }
            return s.voiceSkippedItem(item.rawText, reason: reason)
        }.joined(separator: "\n")
    }
}
