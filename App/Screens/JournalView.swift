// SPDX-License-Identifier: MPL-2.0

import SwiftUI
import PocketNutritionCore
import PocketNutritionVault

/// Home screen: the meals kept on this device, newest day first, with the dictations and meal photos that
/// are not meals yet shown in their day as outlined "meal in progress" rows (see `JournalCaptureRow`).
///
/// This screen has no counterpart in the sandbox — the prototype persists nothing. It exists because
/// a food diary that forgets is not a diary, and it is the reason the app needs its own privacy copy
/// rather than the sandbox's "aucune donnée personnelle n'est conservée".
struct JournalView: View {

    @Environment(JournalStore.self) private var store
    @State private var composerTarget: ComposerTarget?
    @State private var isShowingAbout = false
    @State private var isShowingSettings = false
    @Environment(RecognitionEntryStore.self) private var recognitionStore
    @Environment(RecognitionCoordinator.self) private var recognition
    /// A ready capture whose result needs a look before it can become a meal (nothing usable, or a lookup
    /// that failed and may be retried).
    @State private var reviewCapture: RecognitionEntry?
    /// Set while a ready capture's ingredients are being looked up, so a second tap does nothing.
    @State private var openingCaptureId: String?
    @Environment(MealShortcutsStore.self) private var shortcuts
    /// The meal being saved as a dish, from its long-press menu.
    @State private var dishSource: SavedMeal?
    @State private var isShowingVault = false
    /// Cached: the Keychain is read when the screen appears and when the vault sheet closes, never in `body`.
    @State private var isVaultLinked = VaultInbox.live() != nil
    @AppStorage("vaultCardDismissed") private var isVaultCardDismissed = false
    @Environment(TargetsStore.self) private var targets
    @Environment(ReferenceIntakesStore.self) private var reference
    @AppStorage(TargetsFeature.defaultsKey) private var isTargetsEnabled = TargetsFeature.defaultEnabled
    @State private var detailDay: TargetsDay?
    @State private var isShowingQuestionnaire = false
    @State private var isLoggingWeight = false

    var body: some View {
        NavigationStack {
            Group {
                if store.meals.isEmpty && recognitionStore.entries.isEmpty {
                    emptyState
                } else {
                    mealList
                }
            }
            .background(PnColor.surfacePaper)
            .navigationTitle(Strings.active.journalTitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        composerTarget = .new
                    } label: {
                        Label(Strings.active.journalAdd, systemImage: "plus")
                    }
                }
                // A real menu, not a single-purpose button: About (licence/attribution/privacy) and
                // Settings (language, server override) are two distinct destinations, not one screen
                // wearing two hats — see AboutView's and SettingsView's own doc comments for why they
                // were split.
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            isShowingAbout = true
                        } label: {
                            Label(Strings.active.aboutTitle, systemImage: "info.circle")
                        }
                        Button {
                            isShowingSettings = true
                        } label: {
                            Label(Strings.active.settingsTitle, systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Menu")
                }
            }
            .fullScreenCover(item: $composerTarget) { target in
                switch target {
                case .new:
                    MealBuilderView()
                case .edit(let meal):
                    MealBuilderView(editingMeal: meal)
                case .capture(let entry, let rows):
                    MealBuilderView(initialItems: rows, sourceCapture: entry)
                case .slot(let slot):
                    MealBuilderView(slot: slot)
                }
            }
            .sheet(isPresented: $isShowingAbout) {
                AboutView()
            }
            .sheet(item: $dishSource) { meal in
                SaveDishSheet(items: meal.items) { name, servings in
                    shortcuts.saveDish(name: name, servings: servings, items: meal.items)
                }
            }
            .sheet(item: $reviewCapture) { entry in
                NavigationStack {
                    VoiceReviewView(localId: entry.localId) { rows in
                        reviewCapture = nil
                        // After the sheet is gone: SwiftUI will not present over a sheet that is leaving.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(450))
                            composerTarget = .capture(entry, rows)
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(Strings.active.aboutClose) { reviewCapture = nil }
                        }
                    }
                }
            }
            // Captures in the journal move on by themselves: sending, then following each ticket.
            .onAppear {
                recognition.start()
                recognition.refreshProcessingOnce()
            }
            .sheet(isPresented: $isShowingSettings, onDismiss: { isVaultLinked = VaultInbox.live() != nil }) {
                SettingsView()
            }
            .sheet(isPresented: $isShowingVault, onDismiss: { isVaultLinked = VaultInbox.live() != nil }) {
                VaultView()
            }
            .sheet(item: $detailDay) { day in
                DayDetailView(day: day.id, reader: targetsReader)
            }
            .sheet(isPresented: $isShowingQuestionnaire) { QuestionnaireView() }
            .sheet(isPresented: $isLoggingWeight) { WeightEntrySheet() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("🥗").font(.system(size: 52))
            Text(Strings.active.journalEmpty)
                .font(.subheadline)
                .foregroundStyle(PnColor.inkSoft)
                .multilineTextAlignment(.center)
            Button(Strings.active.journalAdd) { composerTarget = .new }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
            if isTargetsEnabled && !targets.isConfigured {
                Button(Strings.active.targetsSetMine) { isShowingQuestionnaire = true }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PnColor.brandLeafDeep)
                    .accessibilityIdentifier("set-my-targets")
            }
            // Shown on the empty state rather than buried in a settings screen: the one moment the
            // user is deciding whether to trust the app with a diary is before they start one.
            Text(Strings.active.journalPrivacy)
                .font(.caption)
                .foregroundStyle(PnColor.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Offered once the person has a first meal, which is when a vault starts to mean something. It can be
    /// dismissed for good; the vault stays reachable from Settings and from the microphone.
    private var vaultCard: some View {
        let t = Strings.active
        return VStack(alignment: .leading, spacing: 8) {
            Label(t.journalVaultCardTitle, systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PnColor.brandLeafDeep)
            Text(t.journalVaultCardBody)
                .font(.footnote)
                .foregroundStyle(PnColor.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(t.journalVaultCardAction) { isShowingVault = true }
                    .buttonStyle(PrimaryButtonStyle())
                Button(t.journalVaultCardLater) { isVaultCardDismissed = true }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PnColor.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .pnCard()
    }

    private var mealList: some View {
        List {
            if !isVaultLinked && !isVaultCardDismissed {
                vaultCard
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            if recognitionStore.isBlocked || !recognitionStore.unsavedClips.isEmpty {
                storageBanner
                    .listRowBackground(PnColor.surfaceCream)
            }
            ForEach(days, id: \.day) { day in
                let isToday = Calendar.current.isDateInToday(day.day)
                Section {
                    if isTargetsEnabled {
                        targetsRow(for: day.day, isToday: isToday)
                    }
                    ForEach(groupBySlot(
                        day, slotOf: \.effectiveSlot, dateOf: \.savedAt, includeEmptyMainSlots: isToday
                    ), id: \.slot) { group in
                        slotHeader(group.slot)
                        if group.items.isEmpty {
                            emptySlotRow(group.slot)
                        }
                        ForEach(group.items, id: \.id) { item in
                            row(item)
                        }
                        .onDelete { offsets in offsets.map { group.items[$0] }.forEach(delete) }
                    }
                } header: {
                    dayHeader(day)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var targetsReader: TargetsReader {
        TargetsReader(journal: store, targets: targets, reference: reference)
    }

    /// The day's watch-list rings (spec 05 §6), tappable for the day detail. Days with no target keep their
    /// totals only, exactly as before. Today also offers "Set my targets" (until something is set up) and
    /// "Log weight".
    @ViewBuilder
    private func targetsRow(for date: Date, isToday: Bool) -> some View {
        let day = localDay(date)
        let outcome = targetsReader.outcome(on: day)
        let t = Strings.active
        if outcome != .none || isToday {
            VStack(alignment: .leading, spacing: 10) {
                if outcome == .needsTable {
                    Text(t.targetsNeedConnection).font(.caption).foregroundStyle(PnColor.inkSoft)
                } else if outcome != .none {
                    Button {
                        detailDay = TargetsDay(id: day)
                    } label: {
                        DayRingsRow(day: day, reader: targetsReader, keys: targets.watchList.keys)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("day-rings-\(day)")
                }
                if isToday && !targets.isConfigured {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(t.targetsSetMine, systemImage: "target")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PnColor.brandLeafDeep)
                        Text(t.targetsSetMineBody).font(.footnote).foregroundStyle(PnColor.inkSoft)
                        Button(t.targetsSetMine) { isShowingQuestionnaire = true }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("set-my-targets")
                    }
                }
                if isToday && targets.isConfigured {
                    Button {
                        isLoggingWeight = true
                    } label: {
                        Label(t.weightLog, systemImage: "scalemass")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(PnColor.brandLeafDeep)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("log-weight")
                }
            }
            .padding(.vertical, 6)
            .listRowBackground(PnColor.surfaceCard)
            .task { await reference.refreshIfStale() }
        }
    }

    private var timeline: [JournalTimelineDay<SavedMeal>] {
        journalTimeline(meals: store.meals, dateOf: \.savedAt, captures: recognitionStore.entries)
    }

    /// The timeline, with today always present (even before anything is logged) so its empty meals
    /// can be offered.
    private var days: [JournalTimelineDay<SavedMeal>] {
        let all = timeline
        if let first = all.first, Calendar.current.isDateInToday(first.day) { return all }
        return [JournalTimelineDay(day: Calendar.current.startOfDay(for: Date()), items: [])] + all
    }

    private func dayHeader(_ day: JournalTimelineDay<SavedMeal>) -> some View {
        let kcal = day.items.reduce(0.0) { sum, item in
            if case .meal(let meal) = item { return sum + meal.totals.energyKcal }
            return sum
        }
        return HStack {
            Text(Self.dayFormatter(lang: LanguageSettings.shared.effective).string(from: day.day))
            Spacer()
            if kcal > 0 { Text("\(roundHalfUp(kcal)) kcal") }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(PnColor.inkSoft)
    }

    private func slotHeader(_ slot: MealSlot) -> some View {
        Text(Strings.active.mealSlotName(slot).uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(PnColor.inkSoft)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 2, trailing: 16))
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(.isHeader)
    }

    /// Today's main meal with nothing logged: one tap to compose it, and one tap to repeat yesterday's.
    private func emptySlotRow(_ slot: MealSlot) -> some View {
        HStack(spacing: 12) {
            Button {
                composerTarget = .slot(slot)
            } label: {
                // The whole row left of the repeat button is the tap target, not just the label.
                Label(Strings.active.mealSlotName(slot), systemImage: "plus")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PnColor.brandLeafDeep)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            if let previous = yesterdaysMeal(in: slot) {
                Button {
                    repeatMeal(previous, in: slot)
                } label: {
                    HStack(spacing: 4) {
                        Text(Strings.active.journalSameAsYesterday(previous.items.map(\.label).joined(separator: " · ")))
                            .lineLimit(1)
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .font(.footnote)
                    .foregroundStyle(PnColor.inkSoft)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Strings.active.journalRepeatYesterdayA11y(Strings.active.mealSlotName(slot)))
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clear.pnPendingCard(cornerRadius: 10).padding(.horizontal, 2).padding(.vertical, 2))
    }

    /// The latest meal eaten in this slot yesterday, if any.
    private func yesterdaysMeal(in slot: MealSlot) -> SavedMeal? {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else { return nil }
        return store.meals
            .filter { Calendar.current.isDate($0.savedAt, inSameDayAs: yesterday) && $0.effectiveSlot == slot }
            .max { $0.savedAt < $1.savedAt }
    }

    /// Logs the same meal today, in the same slot: now if this is the current part of the day, else at the
    /// slot's usual time. Same items and quantities, so the same nutrition.
    private func repeatMeal(_ meal: SavedMeal, in slot: MealSlot) {
        let now = Date()
        let date = mealSlot(for: now) == slot ? now : defaultDate(for: slot, on: now)
        let items = meal.items.map { item -> MealItem in
            var copy = item
            copy.id = UUID()
            return copy
        }
        store.save(items: items, totals: meal.totals, at: date, slot: slot, nutrients: meal.nutrients)
    }

    @ViewBuilder
    private func row(_ item: JournalTimelineItem<SavedMeal>) -> some View {
        switch item {
        case .meal(let meal):
            Button {
                composerTarget = .edit(meal)
            } label: {
                MealRow(meal: meal)
            }
            .buttonStyle(.plain)
            .listRowBackground(PnColor.surfaceCard)
            .contextMenu {
                Button {
                    repeatMeal(meal, in: mealSlot(for: Date()))
                } label: {
                    Label(Strings.active.logAgainNow, systemImage: "arrow.counterclockwise")
                }
                Button {
                    dishSource = meal
                } label: {
                    Label(Strings.active.saveAsDish, systemImage: "square.and.arrow.down")
                }
                .disabled(!meal.items.contains { !$0.isQuickAdd })
            }
        case .capture(let entry):
            Button {
                open(entry)
            } label: {
                JournalCaptureRow(entry: entry, isOffline: recognition.isOffline)
                    .opacity(openingCaptureId == entry.localId ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(openingCaptureId != nil)
            .listRowBackground(
                Color.clear.pnPendingCard(cornerRadius: 10).padding(.horizontal, 2).padding(.vertical, 2)
            )
        }
    }

    private func delete(_ item: JournalTimelineItem<SavedMeal>) {
        switch item {
        case .meal(let meal): store.delete(meal)
        case .capture(let entry): recognition.delete(entry.localId)
        }
    }

    /// What a tap on a capture does, by state. A ready one goes straight to the meal builder with its best
    /// matches, editable; only a result that needs a look (nothing usable, a lookup to retry) opens the review.
    private func open(_ entry: RecognitionEntry) {
        switch entry.state {
        case .pendingUpload, .needsRetry:
            recognition.sendNow(entry.localId)
        case .ready:
            guard let result = entry.result else { return }
            openingCaptureId = entry.localId
            Task {
                let selections = result.items.map { ImportSelection(item: $0, candidate: $0.candidates.first) }
                let outcome = await RecognitionImporter.resolve(selections, lang: LanguageSettings.shared.effective)
                openingCaptureId = nil
                if !outcome.rows.isEmpty, canDiscardAfterImport(skips: outcome.skipped.map(\.kind)) {
                    composerTarget = .capture(entry, outcome.rows)
                } else {
                    reviewCapture = entry
                }
            }
        case .processing, .unrecoverable:
            break
        }
    }

    /// Recordings or photos that could not be stored: never hidden behind an empty-looking journal.
    private var storageBanner: some View {
        HStack(spacing: 12) {
            Text(Strings.active.voiceStorageUnavailable).font(.footnote).foregroundStyle(PnColor.inkDefault)
            Spacer(minLength: 0)
            Button(Strings.active.retry) {
                recognitionStore.retryUnsavedClips().forEach { recognition.track($0.localId) }
                recognition.start()
            }
            .font(.footnote.weight(.semibold))
        }
    }

    /// A date formatter *is* the right tool here, unlike for numbers. The corpus pins number rendering
    /// because a thousands separator changes the value a user reads; a date header has no such
    /// contract and the platform's own formatting for the active language is what a user expects.
    ///
    /// A function, not a `static let`, because the active language can change at runtime — a cached
    /// formatter built once at first access would keep rendering in whichever language was active
    /// then.
    private static func dayFormatter(lang: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: lang == "en" ? "en_US" : "fr_FR")
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter
    }
}

/// What the meal builder's `fullScreenCover` is showing: a blank compose, or an existing entry to edit.
///
/// A single presented item rather than two booleans, so the cover can never end up representing both at
/// once — a state a pair of `Bool`s would have allowed by construction.
private enum ComposerTarget: Identifiable {
    case new
    case edit(SavedMeal)
    /// A dictation or photo made into a new meal: its rows pre-fill the builder, which dates the meal at
    /// the capture and deletes the capture once saved.
    case capture(RecognitionEntry, [MealIngredient])
    /// "+ Breakfast" in today's journal: a new meal already filed under that slot.
    case slot(MealSlot)

    /// Fixed rather than freshly generated, since `.new` carries no identity of its own: a random UUID
    /// re-computed on every access would look like a *different* item to SwiftUI on each diff, which is
    /// exactly the identity churn `Identifiable` exists to avoid.
    private static let newId = UUID()
    private static let slotIds = Dictionary(uniqueKeysWithValues: MealSlot.allCases.map { ($0, UUID()) })

    var id: UUID {
        switch self {
        case .new: Self.newId
        case .edit(let meal): meal.id
        case .capture(let entry, _): UUID(uuidString: entry.localId) ?? Self.newId
        case .slot(let slot): Self.slotIds[slot] ?? Self.newId
        }
    }
}

/// A journal day as a sheet item ("YYYY-MM-DD").
private struct TargetsDay: Identifiable {
    let id: String
}

extension JournalTimelineItem<SavedMeal> {
    /// Meals and captures share one list; their ids never collide (a capture id is prefixed).
    var id: String {
        switch self {
        case .meal(let meal): meal.id.uuidString
        case .capture(let entry): "capture-" + entry.localId
        }
    }
}

/// One saved meal: what was eaten, and the four macros.
private struct MealRow: View {
    let meal: SavedMeal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meal.items.map(\.label).joined(separator: " · "))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PnColor.inkDefault)
                .lineLimit(2)

            // An item the server could not compute is named, never shown as 0 kcal: the totals below
            // already leave it out (see `MealItem.available`).
            ForEach(meal.items.filter { !$0.isAvailable }) { item in
                Label("\(item.label) · \(Strings.active.resultsUnavailable)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(PnColor.onSoftBad)
                    .lineLimit(2)
            }

            // Nothing in the meal could be computed: no totals to show, rather than a row of zeros.
            if meal.items.isEmpty || meal.items.contains(where: \.isAvailable) {
                HStack(spacing: 12) {
                    // roundHalfUp rather than Int(): the corpus rule, so the phone and the web never
                    // disagree about which side of a .5 a number lands on.
                    Text("\(roundHalfUp(meal.totals.energyKcal)) kcal")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(PnColor.brandLeafDeep)
                    let s = Strings.active
                    macro(s.nutrientProteinAbbr, meal.totals.proteinG)
                    macro(s.nutrientCarbsAbbr, meal.totals.carbohydratesG)
                    macro(s.nutrientFatAbbr, meal.totals.fatG)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// contract: nutrients.proteinAbbr / carbsAbbr / fatAbbr.
    private func macro(_ abbreviation: String, _ grams: Double) -> some View {
        Text("\(abbreviation) \(formatNumber((grams * 10).rounded() / 10, lang: LanguageSettings.shared.effective)) g")
            .font(.caption)
            .foregroundStyle(PnColor.inkSoft)
    }
}

/// The one filled button style in the app, from the design tokens rather than SwiftUI defaults.
extension View {
    /// The design system's card: white fill, rounded corner, **and a hairline border**.
    ///
    /// The border is not decoration. `surfaceCard` is #FFFFFF and `surfacePaper` is #FAF7F0, which is a
    /// contrast ratio of **1.07:1** — indistinguishable. Every card in the app was therefore a white
    /// shape on a white background with nothing marking where it began or ended, which is what makes a
    /// screen read as "white on white" even when all its text passes contrast comfortably.
    ///
    /// `pocket-nutrition-design` had this right all along and the app simply dropped it:
    /// `.card { background:#fff; border:1px solid var(--line); … }`. `inkLine` is that `--line`, the
    /// same token the row dividers already use. A boundary only has to be perceivable, not legible, so
    /// the 1.40:1 it lands at against the card is doing its job.
    func pnCard(cornerRadius: CGFloat = 14) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(PnColor.surfaceCard)
            .clipShape(shape)
            .overlay(shape.stroke(PnColor.inkLine, lineWidth: 1))
    }

    /// The design system's text input, including its focus state.
    ///
    /// Distinct from `pnCard()` on purpose, even though the unfocused appearance is nearly the same
    /// white-plus-hairline. A card is a passive container; a field is a control, so it needs a focus
    /// affordance and the deck gives it a specific one — **brand green**, where every other focusable
    /// element uses the carrot accent ring. `semantic-map.json` flags that asymmetry and asks a port to
    /// preserve it rather than unify the two, so this is the modifier that honours it.
    ///
    /// Radius is `PnRadius.small` (10 pt), not the card's 18: the deck gives inputs their own radius,
    /// and reusing the card's made the Android and iOS fields visibly different shapes.
    func pnInput(focused: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: PnRadius.small, style: .continuous)
        return self
            .background(PnRole.inputDefaultBackground)
            .clipShape(shape)
            .overlay(
                shape.stroke(
                    focused ? PnRole.inputFocusBorderColor : PnRole.inputDefaultBorderColor,
                    lineWidth: focused ? 1.5 : 1
                )
            )
            // The 3 pt ring is drawn outside the border, as a stroked shape rather than a shadow, so it
            // cannot bleed into the field's own fill and change the text's background.
            .overlay(
                shape
                    .stroke(PnRole.inputFocusRingColor, lineWidth: 3)
                    .padding(-2)
                    .opacity(focused ? 1 : 0)
            )
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// The filled primary action, including its disabled appearance.
///
/// The disabled look lives here rather than at each call site, and that is the fix for a real
/// legibility bug: the meal builder used to wrap this button in `.opacity(0.4)`. Opacity fades the
/// fill and the label *together*, so a white label over a deep-green fill became a near-white label
/// over a washed-out grey-green one — measured at **2.23:1**, below even WCAG's 3.0 floor for large
/// text. It was the worst contrast anywhere in the app, and it sat on the screen's main call to action.
///
/// Disabled is now a muted fill with dark text — cream + inkSoft, **6.12:1** — rather than a faded
/// copy of the enabled state. It still reads as inert, because the fill drops from deep green to a
/// pale cream while the label stops being white, but it stays readable, which matters here: the label
/// is `Analyser le repas (0 aliment)`, and the count is the very thing telling you why you cannot
/// press it.
///
/// The design deck defines no disabled state for `.btn-primary`, so this pairing is a local decision.
/// It should go back into pocket-nutrition-design before a third client needs it.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? PnRole.buttonPrimaryForeground : PnColor.inkSoft)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isEnabled ? PnRole.buttonPrimaryBackground : PnColor.surfaceCream)
            .clipShape(shape)
            // A border on the disabled state only. Enabled, the deep-green fill is 6.85:1 against paper
            // and the shape is unmistakable. Disabled, the cream fill measures **1.12:1** against the
            // paper behind it — so while the *label* is a comfortable 6.12:1, the button had no
            // perceivable edge and read as a stray line of text rather than a control you cannot press
            // yet. WCAG 1.4.11 asks for 3:1 on a control's boundary; a hairline of ink.line does not get
            // there either, but it is the deck's own line token and it does make the shape visible.
            .overlay(shape.stroke(PnColor.inkLine, lineWidth: isEnabled ? 0 : 1))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
