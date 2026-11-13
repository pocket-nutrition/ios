// SPDX-License-Identifier: MPL-2.0

import PocketNutritionCore
import SwiftUI

/// Settings → Daily targets: the questionnaire, the targets and watch list, the explanation and the weight.
struct TargetsSettingsView: View {
    @Environment(TargetsStore.self) private var targets
    @Environment(ReferenceIntakesStore.self) private var reference
    @Environment(JournalStore.self) private var journal
    @State private var isShowingQuestionnaire = false

    var body: some View {
        let s = Strings.active
        let reader = TargetsReader(journal: journal, targets: targets, reference: reference)
        List {
            if reference.rows == nil {
                Section { Text(s.targetsNeedConnection).font(.footnote).foregroundStyle(PnColor.inkSoft) }
            }
            Section {
                Button(targets.profiles.isEmpty ? s.targetsSetMine : s.targetsEditAnswers) { isShowingQuestionnaire = true }
                NavigationLink(s.targetsScreenTitle) { TargetsScreen() }
                NavigationLink(s.targetsExplanationTitle) { ExplanationView(day: targets.today, reader: reader) }
                NavigationLink(s.weightTitle) { WeightView() }
            }
            .listRowBackground(PnColor.surfaceCard)
            Section { Text(s.targetsNotMedicalAdvice).font(.footnote).foregroundStyle(PnColor.inkSoft) }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PnColor.surfacePaper)
        .navigationTitle(s.targetsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reference.refreshIfStale() }
        .sheet(isPresented: $isShowingQuestionnaire) { QuestionnaireView() }
    }
}

/// The preset picker, the watch list (show, hide, reorder) and, per nutrient, its target with "Edit" and
/// "Reset to EFSA" (spec 05 §5).
struct TargetsScreen: View {
    @Environment(TargetsStore.self) private var targets
    @Environment(ReferenceIntakesStore.self) private var reference
    @Environment(JournalStore.self) private var journal
    @State private var editing: String?

    var body: some View {
        let s = Strings.active
        let lang = LanguageSettings.shared.effective
        let reader = TargetsReader(journal: journal, targets: targets, reference: reference)
        let today = targets.today
        let dayTargets = Dictionary(reader.outcome(on: today).targets.map { ($0.nutrientKey, $0) }, uniquingKeysWith: { a, _ in a })
        let watched = targets.watchList.keys
        let hidden = NutrientTotals.keys.filter { !watched.contains($0) }
        let preset = WatchListPreset(rawValue: targets.watchList.preset)

        List {
            Section(s.presetTitle) {
                Picker(s.presetTitle, selection: Binding(
                    get: { targets.watchList.preset },
                    set: { name in WatchListPreset(rawValue: name).map(targets.choosePreset) }
                )) {
                    ForEach(WatchListPreset.allCases, id: \.rawValue) { Text(s.presetName($0.rawValue)).tag($0.rawValue) }
                    if preset == nil { Text(s.presetName(WatchListPreset.custom)).tag(WatchListPreset.custom) }
                }
                if preset?.isMedical == true {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.presetMedicalBanner).font(.footnote).foregroundStyle(PnColor.inkDefault)
                        Button(s.presetMedicalAction) { editing = watched.first }
                            .font(.footnote.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(PnColor.hueGoldSoft)
                }
                if reference.rows == nil {
                    Text(s.targetsNeedConnection).font(.footnote).foregroundStyle(PnColor.inkSoft)
                }
            }
            Section(s.watchShown) {
                ForEach(watched, id: \.self) { key in
                    row(key, target: dayTargets[key], s: s, lang: lang)
                }
                .onMove { from, to in
                    var keys = watched
                    keys.move(fromOffsets: from, toOffset: to)
                    targets.setWatchKeys(keys)
                }
                .onDelete { offsets in
                    targets.setWatchKeys(watched.enumerated().filter { !offsets.contains($0.offset) }.map(\.element))
                }
            }
            Section(s.watchHidden) {
                ForEach(hidden, id: \.self) { key in
                    HStack {
                        row(key, target: dayTargets[key], s: s, lang: lang)
                        Button {
                            targets.setWatchKeys(watched + [key])
                        } label: {
                            Image(systemName: "plus.circle.fill").foregroundStyle(PnColor.brandLeaf)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(s.watchShown)
                    }
                }
            }
            if !targets.currentOverrides.isEmpty {
                Section {
                    Button(s.targetResetAll) { targets.resetAllOverrides() }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PnColor.surfacePaper)
        .navigationTitle(s.targetsScreenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(item: Binding(get: { editing.map(EditingKey.init) }, set: { editing = $0?.key })) { item in
            OverrideEditor(key: item.key, current: targets.currentOverrides[item.key] ?? dayTargets[item.key].map {
                TargetOverride(min: $0.min, max: $0.max)
            }) { value in
                targets.setOverride(item.key, value)
            }
        }
    }

    private func row(_ key: String, target: DayTarget?, s: any AppStrings, lang: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(NutrientDisplay.ringName(key, s)).font(.subheadline.weight(.medium))
                if target?.overridden == true {
                    Text(s.targetOverridden).font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(PnColor.brandCarrotSoft, in: Capsule())
                }
            }
            Text(target.map { "\(NutrientDisplay.targetText($0, lang: lang)) · \(NutrientDisplay.kind($0, s))" } ?? s.targetKindNone)
                .font(.caption).foregroundStyle(PnColor.inkSoft)
            HStack(spacing: 16) {
                Button(s.targetEdit) { editing = key }
                if target?.overridden == true {
                    Button(s.targetReset) { targets.setOverride(key, nil) }
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)
            .foregroundStyle(PnColor.brandLeafDeep)
        }
        .padding(.vertical, 2)
        .listRowBackground(PnColor.surfaceCard)
    }

    private struct EditingKey: Identifiable {
        let key: String
        var id: String { key }
    }
}

/// Min and/or max for one nutrient. Salt is entered in grams of salt and stored as sodium.
struct OverrideEditor: View {
    let key: String
    let current: TargetOverride?
    let onSave: (TargetOverride) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var minText = ""
    @State private var maxText = ""

    private var isSalt: Bool { NutrientDisplay.isSalt(key) }
    private var unitLabel: String { isSalt ? "g" : TargetUnit(key: key).rawValue }

    var body: some View {
        let s = Strings.active
        NavigationStack {
            Form {
                Section {
                    LabeledContent("\(s.targetMin) (\(unitLabel))") {
                        TextField("—", text: $minText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("\(s.targetMax) (\(unitLabel))") {
                        TextField("—", text: $maxText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text(s.targetEditHint)
                }
            }
            .navigationTitle(NutrientDisplay.ringName(key, s))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(s.targetCancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(s.qSave) {
                        onSave(TargetOverride(min: stored(minText), max: stored(maxText)))
                        dismiss()
                    }
                    .disabled(stored(minText) == nil && stored(maxText) == nil)
                }
            }
            .onAppear {
                minText = shown(current?.min)
                maxText = shown(current?.max)
            }
        }
        .presentationDetents([.medium])
    }

    private func parse(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)).flatMap { $0 >= 0 ? $0 : nil }
    }

    /// Salt typed in grams is stored as sodium in mg.
    private func stored(_ text: String) -> Double? {
        guard let value = parse(text) else { return nil }
        return isSalt ? value * 1000 / saltPerSodium : value
    }

    private func shown(_ value: Double?) -> String {
        guard let value else { return "" }
        let display = isSalt ? saltGrams(sodiumMg: value) : value
        return formatNumber(Double(roundHalfUp(display * 10)) / 10, lang: LanguageSettings.shared.effective)
    }
}

/// "How is this calculated": one row per target with its value, EFSA value kind, sources and inputs; our own
/// choices labelled as ours; the profile's last update; not medical advice.
struct ExplanationView: View {
    let day: String
    let reader: TargetsReader

    @Environment(TargetsStore.self) private var targets

    var body: some View {
        let s = Strings.active
        let lang = LanguageSettings.shared.effective
        let outcome = reader.outcome(on: day)
        let order = Dictionary(NutrientTotals.keys.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let list = outcome.targets.sorted { (order[$0.nutrientKey] ?? 99) < (order[$1.nutrientKey] ?? 99) }
        let bases = reader.bases(on: day)
        let computed = reader.computedTargets(on: day)
        let profile = profileForDay(targets.profiles, weights: targets.weightEntries, day: day)

        List {
            if outcome == .needsTable {
                Section { Text(s.targetsNeedConnection).font(.footnote) }
            }
            if case .unsupported(let reason, _) = outcome {
                Section { Text(s.targetsUnsupported(reason)).font(.footnote) }
            }
            Section(s.explanationInputs) {
                if let profile {
                    // The narrowest band used is the one that says most about this person's age.
                    let band = bases.values.flatMap(\.ageBands).min { ($0.to - $0.from) < ($1.to - $1.from) }
                    Text(s.explanationAge(profile.ageYears, band: band.map {
                        s.ageBandLabel(from: Int($0.from), to: $0.to >= 999 ? nil : Int($0.to))
                    } ?? "–"))
                    Text(s.explanationPal(formatNumber(profile.pal, lang: lang)))
                    Text(s.explanationWeight(formatNumber(profile.weightKg, lang: lang)))
                    Text(s.explanationBasis(profile.basis))
                    Text(s.explanationSituation(situationText(profile, s)))
                    if let updated = targets.profiles.last(where: { $0.effectiveFrom <= day })?.effectiveFrom {
                        Text(s.explanationProfileUpdated(formatDay(updated, lang: lang))).foregroundStyle(PnColor.inkSoft)
                    }
                } else {
                    Text(s.targetsNoProfile).foregroundStyle(PnColor.inkSoft)
                }
            }
            .font(.footnote)
            ForEach(list, id: \.nutrientKey) { target in
                Section(s.nutrientName(target.nutrientKey)) {
                    targetRow(target, basis: bases[target.nutrientKey], efsa: computed[target.nutrientKey], s: s, lang: lang)
                }
            }
            Section(s.explanationChoicesTitle) {
                ForEach(s.explanationChoices, id: \.self) { Text($0).font(.footnote) }
            }
            Section { Text(s.targetsNotMedicalAdvice).font(.footnote).foregroundStyle(PnColor.inkSoft) }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PnColor.surfacePaper)
        .navigationTitle(s.targetsExplanationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func targetRow(_ target: DayTarget, basis: TargetBasis?, efsa: NutrientTarget?, s: any AppStrings, lang: String) -> some View {
        HStack {
            Text(NutrientDisplay.targetText(target, lang: lang)).font(.subheadline.weight(.semibold))
            Text(NutrientDisplay.kind(target, s)).font(.caption).foregroundStyle(PnColor.inkSoft)
            Spacer()
            if target.overridden {
                Text(s.targetOverridden).font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(PnColor.brandCarrotSoft, in: Capsule())
            }
        }
        if target.overridden {
            Text(s.explanationOverriddenNote).font(.caption).foregroundStyle(PnColor.inkSoft)
            if let efsa {
                Text("EFSA · \(NutrientDisplay.targetText(DayTarget(efsa, overridden: false), lang: lang))")
                    .font(.caption).foregroundStyle(PnColor.inkSoft)
            }
            if day == targets.today {
                Button(s.targetReset) { targets.setOverride(target.nutrientKey, nil) }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PnColor.brandLeafDeep)
            }
        }
        ForEach(basis?.kinds ?? [], id: \.self) { kind in
            Text(s.valueKindName(kind)).font(.caption).foregroundStyle(PnColor.inkSoft)
        }
        if let ul = target.upperLimit {
            Text("UL \(NutrientDisplay.format(ul, unit: target.unit, lang: lang))").font(.caption).foregroundStyle(PnColor.inkSoft)
        }
        ForEach(target.sources, id: \.self) { link in
            if let url = URL(string: link), url.scheme == "https" {
                Link(destination: url) {
                    Label(s.explanationSources, systemImage: "doc.text").font(.caption)
                }
            }
        }
    }

    private func situationText(_ profile: TargetProfile, _ s: any AppStrings) -> String {
        var text = s.situationName(profile.situation)
        if let trimester = profile.trimester, profile.situation == .pregnant { text += ", " + s.trimesterName(trimester) }
        if let lactation = profile.lactation, profile.situation == .lactating { text += ", " + s.lactationName(lactation) }
        if profile.postmenopausal == true { text += ", " + s.qPostmenopausal.replacingOccurrences(of: "?", with: "").trimmingCharacters(in: .whitespaces) }
        return text
    }

    private func formatDay(_ day: String, lang: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: lang == "en" ? "en_US" : "fr_FR")
        formatter.dateStyle = .long
        return formatter.string(from: TargetsReader.date(of: day))
    }
}
