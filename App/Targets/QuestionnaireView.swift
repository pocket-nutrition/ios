// SPDX-License-Identifier: MPL-2.0

import PocketNutritionCore
import SwiftUI

/// The optional questionnaire (spec 05 §4): five short steps and a preview, with "Skip, I'll enter my own
/// values" on each. It asks only what changes the numbers, never a gender. Saving appends a profile version
/// dated today (or replaces today's); an unsupported profile is still saved, with a pointer to a professional.
struct QuestionnaireView: View {
    @Environment(TargetsStore.self) private var targets
    @Environment(ReferenceIntakesStore.self) private var reference
    @Environment(\.dismiss) private var dismiss

    private enum Step: Int, CaseIterable { case birthYear = 1, body, basis, situation, activity, preview }

    @State private var step: Step = .birthYear
    @State private var birthYear = Calendar.current.component(.year, from: Date()) - 30
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var basis: CalculationBasis = .average
    @State private var postmenopausal = false
    @State private var situation: TargetSituation = .none
    @State private var trimester = 1
    @State private var lactation: LactationPeriod = .firstSixMonths
    @State private var activity: ActivityLevel = .moderate
    @State private var isSkipping = false
    @State private var didLoad = false

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var age: Int { currentYear - birthYear }
    private var weightKg: Double? { parse(weightText).flatMap { (20...400).contains($0) ? $0 : nil } }
    private var asksMenopause: Bool { basis != .male && age >= 40 }

    var body: some View {
        let s = Strings.active
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if step != .preview {
                        Text(s.qStep(step.rawValue, of: 5)).font(.caption.weight(.semibold)).foregroundStyle(PnColor.inkSoft)
                    }
                    content(s)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(PnColor.surfacePaper)
            .navigationTitle(s.targetsSetMine)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(s.targetCancel) { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { footer(s) }
            .navigationDestination(isPresented: $isSkipping) { TargetsScreen() }
            .onAppear(perform: loadLatest)
            .task { await reference.refreshIfStale() }
        }
    }

    @ViewBuilder
    private func content(_ s: any AppStrings) -> some View {
        switch step {
        case .birthYear:
            title(s.qBirthYear)
            Picker(s.qBirthYear, selection: $birthYear) {
                ForEach((1920...currentYear).reversed(), id: \.self) { Text(String($0)).tag($0) }
            }
            .pickerStyle(.wheel)
            .accessibilityIdentifier("q-birth-year")
        case .body:
            title(s.qBody)
            field(s.qWeight, text: $weightText, id: "q-weight")
            field(s.qHeight, text: $heightText, id: "q-height")
            note(s.qHeightNote)
        case .basis:
            title(s.qBasis)
            note(s.qBasisNote)
            choices(CalculationBasis.allCases, selection: $basis) { s.basisName($0) }
            if asksMenopause {
                Toggle(s.qPostmenopausal, isOn: $postmenopausal).padding(14).pnCard()
            }
        case .situation:
            title(s.qSituation)
            choices(TargetSituation.allCases, selection: $situation) { s.situationName($0) }
            if situation == .pregnant {
                Picker(s.qTrimester, selection: $trimester) {
                    ForEach(1...3, id: \.self) { Text(s.trimesterName($0)).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if situation == .lactating {
                Picker(s.qLactation, selection: $lactation) {
                    ForEach(LactationPeriod.allCases, id: \.self) { Text(s.lactationName($0)).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        case .activity:
            title(s.qActivity)
            choices(ActivityLevel.allCases, selection: $activity) { level in
                "\(s.activityName(level)) — \(s.activityExample(level))"
            }
        case .preview:
            title(s.qPreview)
            preview(s)
        }
    }

    private func footer(_ s: any AppStrings) -> some View {
        VStack(spacing: 8) {
            if step == .preview {
                Button(s.qSave) { save() }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("q-save")
            } else {
                Button(s.qNext) { advance() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(step == .body && weightKg == nil)
                    .accessibilityIdentifier("q-next")
            }
            HStack {
                if step != .birthYear {
                    Button(s.qBack) { back() }
                }
                Spacer()
                Button(s.qSkip) { isSkipping = true }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(PnColor.inkSoft)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(PnColor.surfacePaper)
    }

    // MARK: - Preview

    private var profileVersion: ProfileVersion {
        ProfileVersion(
            effectiveFrom: targets.today, birthYear: birthYear, basis: basis,
            situation: basis == .female ? situation : .none,
            trimester: basis == .female && situation == .pregnant ? trimester : nil,
            lactation: basis == .female && situation == .lactating ? lactation : nil,
            postmenopausal: asksMenopause ? postmenopausal : nil,
            pal: activity.pal, weightKg: weightKg ?? 0,
            heightCm: parse(heightText).flatMap { (50...260).contains($0) ? $0 : nil })
    }

    @ViewBuilder
    private func preview(_ s: any AppStrings) -> some View {
        let lang = LanguageSettings.shared.effective
        if let table = reference.rows,
           let profile = profileForDay([profileVersion], weights: [], day: targets.today) {
            switch dailyTargets(table, profile: profile) {
            case .unsupported(let reason):
                note(s.targetsUnsupported(reason))
            case .ok(let list):
                let byKey = Dictionary(list.map { ($0.nutrientKey, $0) }, uniquingKeysWith: { a, _ in a })
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(targets.watchList.keys, id: \.self) { key in
                        HStack {
                            Text(NutrientDisplay.ringName(key, s))
                            Spacer()
                            Text(byKey[key].map { NutrientDisplay.targetText(DayTarget($0, overridden: false), lang: lang) } ?? s.targetKindNone)
                                .foregroundStyle(PnColor.inkSoft)
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
                .padding(16)
                .pnCard()
                note(s.targetsNotMedicalAdvice)
            }
        } else {
            note(s.qPreviewNeedsTable)
        }
    }

    // MARK: - Navigation

    private func advance() {
        var next = Step(rawValue: step.rawValue + 1) ?? .preview
        if next == .situation && basis != .female { next = .activity }
        step = next
    }

    private func back() {
        var previous = Step(rawValue: step.rawValue - 1) ?? .birthYear
        if previous == .situation && basis != .female { previous = .basis }
        step = previous
    }

    private func save() {
        guard weightKg != nil else { return }
        targets.saveProfile(profileVersion)
        dismiss()
    }

    private func loadLatest() {
        guard !didLoad else { return }
        didLoad = true
        guard let latest = targets.latestProfile else { return }
        birthYear = latest.birthYear
        weightText = formatNumber(latest.weightKg, lang: LanguageSettings.shared.effective)
        heightText = latest.heightCm.map { formatNumber($0, lang: LanguageSettings.shared.effective) } ?? ""
        basis = latest.basis
        postmenopausal = latest.postmenopausal ?? false
        situation = latest.situation
        trimester = latest.trimester ?? 1
        lactation = latest.lactation ?? .firstSixMonths
        activity = ActivityLevel.allCases.first { $0.pal == latest.pal } ?? .moderate
    }

    // MARK: - Building blocks

    private func title(_ text: String) -> some View {
        Text(text).font(.title3.weight(.semibold)).foregroundStyle(PnColor.brandLeafDeep)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(PnColor.inkSoft).fixedSize(horizontal: false, vertical: true)
    }

    private func field(_ label: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.footnote.weight(.medium)).foregroundStyle(PnColor.inkSoft)
            TextField(label, text: text)
                .keyboardType(.decimalPad)
                .padding(12)
                .pnInput(focused: false)
                .accessibilityIdentifier(id)
        }
    }

    private func choices<T: Hashable>(_ options: [T], selection: Binding<T>, label: @escaping (T) -> String) -> some View {
        VStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection.wrappedValue = option
                } label: {
                    HStack {
                        Text(label(option)).multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: selection.wrappedValue == option ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selection.wrappedValue == option ? PnColor.brandLeaf : PnColor.inkLine)
                    }
                    .font(.subheadline)
                    .foregroundStyle(PnColor.inkDefault)
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .pnCard()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func parse(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }
}
