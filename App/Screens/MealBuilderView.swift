// SPDX-License-Identifier: MPL-2.0

import SwiftUI
import PocketNutritionCore

/// Compose a meal, then analyse it.
///
/// DELIBERATE DIVERGENCE FROM THE SANDBOX
/// The sandbox groups rows into one drop-lane per cooking method and you drag a card between lanes to
/// re-cook it. That is a mouse interaction; on a phone it competes with scrolling and hides the method
/// behind a gesture nobody discovers. Here each row carries its own method picker instead, collapsed
/// behind a pill that states the current answer — the same shape the sandbox uses for the same reason,
/// which is that seven chips per row is most of the row.
///
/// The *behaviour* must not diverge, only the trigger — and it does not: selecting a method runs
/// `applyMethodChange` from the corpus, so the weight follows. Switch a grilled row to raw and the
/// grams move back to the raw equivalent, exactly as they do when a sandbox card is dragged between
/// lanes.
///
///
/// MULTI-TERM SELECTION, and the one deliberate divergence in it. Typing more than one ingredient phrase
/// turns a tap into a checkbox and adds the set in one go, as the sandbox does. What is NOT ported is the
/// sandbox's "Voir plus" pagination: it reveals six rows per click, where this list scrolls a capped
/// window, because scrolling is the phone's default gesture and a load-more button costs a tap per step.
/// `search.showMore` was re-scoped to sandbox-only in contracts 1.8.0 to record that.
/// Rows are `MealIngredient` rather than `MealItem` because that is what the corpus functions operate
/// on. `MealItem` is still the journal's persisted shape; the conversion happens once, at the save
/// boundary — see `MealIngredient+App.swift`.
struct MealBuilderView: View {

    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Set when this screen is editing a previously saved entry rather than composing a new one.
    let editingMeal: SavedMeal?

    @State private var query = ""
    @State private var suggestions: [IngredientSuggestion] = []
    @State private var items: [MealIngredient]
    @State private var isSearching = false
    @State private var errorMessage: String?
    /// The server's per-item answer for the meal as it currently stands. Recomputed automatically —
    /// see `scheduleRecompute()` — rather than behind an "Analyser" tap: this screen used to push a
    /// separate `ResultsView` once the user asked for a total, and merging the two into one screen
    /// only reads as one screen if the total is already there rather than one more step away.
    @State private var results: [NutritionalProfile]?
    /// Shown as a small inline spinner beside the total rather than disabling anything: recomputing is
    /// a background refresh of a number already on screen, not a blocking action the way the old
    /// "Analyser" tap was.
    @State private var isComputingTotals = false
    /// Guards against a double save the same way `ResultsView.save()` used to: a double tap landing
    /// before the view updates would otherwise write the meal twice.
    @State private var hasSaved = false
    @State private var searchTask: Task<Void, Never>?
    @State private var recomputeTask: Task<Void, Never>?
    /// The last server-confirmed profile for a row, keyed by the row's own id — not `ingredientId`,
    /// since the same ingredient added twice is two rows that can carry different methods or weights.
    /// Lets `scheduleRecompute` answer a pure quantity change (typing a weight, the +/- steppers, the
    /// quick-portion buttons) without a network call at all: nutrient content is linear in quantity for
    /// a fixed cooking method and measured state, so rescaling this is arithmetic on a fact the server
    /// already gave us, not a fact invented client-side.
    @State private var profileCache: [String: ProfileBaseline] = [:]
    @State private var isScanningBarcode = false
    @FocusState private var isQueryFocused: Bool

    /// How many ingredient phrases the server split the query into, from `X-Segment-Count`. 1 until a
    /// response says otherwise, so the single-term path is what a fresh screen does.
    @State private var segmentCount = 1

    /// Rows checked in multi-term mode, keyed by `ingredientId`. Cleared whenever the query changes, for
    /// the same reason `suggestions` is: a selection made against one query's rows means nothing against
    /// another's.
    @State private var selectedIds: Set<String> = []

    /// Which row is expanded, lifted here rather than kept in each `MealIngredientRow` — matching the
    /// sandbox's `MealBuilder`, which lifts the same state to the same effect: only one card can ever be
    /// open, so expanding a second one collapses the first without either row needing to know the other
    /// exists. New rows start collapsed, since this is `nil` until a row is tapped.
    @State private var expandedItemId: String?

    /// Whether some row's weight field currently has the keyboard up. Used to hide `summaryBar`
    /// entirely — see `showsSummaryBar` — since a kcal total that is about to change, plus a save
    /// button, is exactly the "too much on screen" a person midway through typing an exact weight does
    /// not need competing for room or attention.
    @State private var isEditingWeight = false

    init(editingMeal: SavedMeal? = nil) {
        self.editingMeal = editingMeal
        // Rebuilt from the saved shape rather than kept as-is: the builder works in `MealIngredient`,
        // the journal's persisted shape is `MealItem`, and the conversion happens once, at this
        // boundary, same as the reverse happens once at the save boundary in `ResultsView`.
        //
        // Sorted alphabetically only here, on reopening a saved meal: at that point the addition order
        // is a fact about a past session the person is no longer holding in mind, and a long meal reads
        // faster alphabetically than in whatever sequence it happened to be typed. Composing a new meal
        // does NOT sort — `add(_:)` still appends, so a row stays where it was just added, which is
        // where a person expects to find the item they are actively building.
        let rebuilt = editingMeal?.items.map { $0.asMealIngredient(id: $0.id.uuidString) } ?? []
        _items = State(initialValue: rebuilt.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                content
            }
            .background(PnColor.surfacePaper)
            // A tap anywhere but the field itself (which owns its own touch handling and takes
            // priority) blurs it. Without this the only way to dismiss the keyboard was to scroll the
            // results, which is not obvious when the list is short enough not to need scrolling.
            .onTapGesture { isQueryFocused = false }
            .navigationTitle(Fr.mealHeading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Fr.searchCancel) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if showsSummaryBar {
                    summaryBar
                }
            }
            .fullScreenCover(isPresented: $isScanningBarcode) {
                BarcodeScanFlowView { suggestion in
                    add(suggestion)
                    isScanningBarcode = false
                }
            }
            // Totals follow the meal automatically rather than waiting for an "Analyser" tap — see
            // `scheduleRecompute()`. Reacting to `items` rather than calling `scheduleRecompute()`
            // directly from every mutation site (`add`, the portion ladder, the method sheet, delete)
            // means a fifth call site added later cannot forget to trigger it.
            .onChange(of: items) { _, _ in scheduleRecompute() }
            // A row closing is not itself an `items` mutation, so it needs its own trigger: the person
            // just finished adjusting a weight or method with nothing recomputing underneath them (see
            // `scheduleRecompute()`'s guard), and closing the row is the signal that they are done.
            .onChange(of: expandedItemId) { _, newValue in
                if newValue == nil { scheduleRecompute() }
            }
            // Focusing the search field to look for another ingredient implicitly answers "are you done
            // with the open row" — yes — so it closes the row rather than leaving it open behind the
            // keyboard, where the weighed-state toggle a person opened it for is no longer reachable.
            .onChange(of: isQueryFocused) { _, focused in
                if focused { expandedItemId = nil }
            }
            // Only path that supplies a total without a mutation to react to: reopening a saved meal.
            .onAppear { scheduleRecompute() }
        }
    }

    // MARK: - Search

    /// The search field, rendered from the design system's `input` role rather than from `pnCard()`.
    ///
    /// TWO MEASURED DEFECTS THIS FIXES, both sampled from a simulator screenshot rather than reasoned
    /// about from tokens — which matters, because the token pairing looked fine and the pixels did not:
    ///
    /// 1. **The placeholder was #C5C5C7 on #FFFFFF — 1.72:1.** WCAG AA wants 4.5:1 for text. This was
    ///    the "white on white" a user actually sees: near-white grey inside a white box.
    ///    `TextField(_:text:)` renders its placeholder in the platform's `placeholderText` colour, and
    ///    the design deck's `.input` rule specifies a fill, a border, a radius and a text colour but
    ///    **no placeholder colour at all** — so each platform fell through to its own default. Android
    ///    happened to land on `inkSoft` (6.12:1) via Material's `onSurfaceVariant`; iOS landed here.
    ///    An undefined token, not a client bug, which is why the fix is to name the colour explicitly
    ///    on both clients and why the deck should grow the entry.
    ///
    /// 2. **No focus state.** `PnRole.inputFocus*` has existed in the generated tokens since the first
    ///    emit and neither client ever used it. The deck is emphatic that fields focus in *brand green*
    ///    while everything else uses the accent ring — a distinction `semantic-map.json` explicitly asks
    ///    a port to keep rather than unify.
    ///
    /// Still short of WCAG 1.4.11: the unfocused boundary is `ink.line`, 14% ink, which measures
    /// **1.23:1** against paper where a component boundary wants 3:1. That is not fixable from here —
    /// 14% cannot reach 3:1 on any of these backgrounds — so it needs a stronger line token in
    /// `pocket-nutrition-design`, a decision for the design owner rather than a colour invented in a
    /// client. Recorded rather than papered over.
    private var searchField: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(PnColor.inkSoft)
                TextField(
                    text: $query,
                    prompt: Text(Fr.searchPlaceholder).foregroundStyle(PnColor.inkSoft)
                ) { EmptyView() }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(PnRole.inputDefaultForeground)
                    .focused($isQueryFocused)
                    .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
                if isSearching { ProgressView().controlSize(.small) }
                Button {
                    isScanningBarcode = true
                } label: {
                    Image(systemName: "barcode.viewfinder").foregroundStyle(PnColor.inkSoft)
                }
                .accessibilityLabel(Fr.scanBarcodeButton)
            }
            .padding(12)
            .pnInput(focused: isQueryFocused)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if !suggestions.isEmpty {
                suggestionList
            } else if !query.isEmpty && !isSearching {
                Text(Fr.searchNoResults)
                    .font(.footnote)
                    .foregroundStyle(PnColor.inkSoft)
                    .padding(.bottom, 12)
            }

            multiTermHint
        }
    }

    /// Teaches multi-term search, which is otherwise undiscoverable — nothing about a search field
    /// suggests that typing three words behaves differently.
    ///
    /// It is a line under the field rather than the deck's `search.placeholder`, and that is a measured
    /// choice: that string is 51 characters against a field that fits roughly 22, so the
    /// "(riz poulet pomme)" carrying the lesson is exactly what a phone truncates away. The short
    /// placeholder stays legible, and this says the rest.
    ///
    /// Hidden as soon as the server reports a second term — at that point the person is already doing it.
    @ViewBuilder
    private var multiTermHint: some View {
        if segmentCount <= 1 {
            Text(Fr.multiTermHint)
                .font(.caption2)
                .foregroundStyle(PnColor.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
    }

    /// Cancel / confirm for a multi-term selection, shown only while something is checked.
    ///
    /// Lives in the bottom bar beside the analyse button rather than pinned inside the result list, which
    /// is where the sandbox puts it: a sticky footer inside a 5-row scroll window would eat a row, and
    /// the bar is already the screen's action area.
    @ViewBuilder
    private var selectionBar: some View {
        if !selectedIds.isEmpty {
            HStack(spacing: 8) {
                Button(Fr.searchCancel) {
                    selectedIds = []
                    query = ""
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PnColor.inkSoft)

                Button(Fr.confirmAdd(count: selectedIds.count)) { confirmSelection() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private var suggestionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(suggestions) { suggestion in
                    Button {
                        tap(suggestion)
                    } label: {
                        SuggestionRow(
                            suggestion: suggestion,
                            alreadyAdded: items.contains { $0.ingredientId == suggestion.ingredientId },
                            // nil, not false, when the query is a single term: the checkbox slot is
                            // absent rather than empty, so the single-term row keeps exactly the layout
                            // it had before this feature existed.
                            checked: shouldToggleSelection(termCount: segmentCount, productType: suggestion.productType)
                                ? selectedIds.contains(suggestion.ingredientId)
                                : nil
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(items.contains { $0.ingredientId == suggestion.ingredientId })
                    Divider().overlay(PnColor.inkLine)
                }
            }
        }
        // A whole number of rows, deliberately. Rows are 60 points tall (44-point thumbnail plus 8
        // above and below), so a cap that is not a multiple of that slices the last row's second line
        // in half and the list reads as broken rather than scrollable — which is exactly what 220 did
        // once the thumbnail and brand line made rows taller than the 40 points they used to be.
        .frame(maxHeight: SuggestionRow.height * 5)
        .pnCard()
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    /// Debounced by 300 ms — the same interval as the sandbox's `useSearch`, matched on purpose so a
    /// keystroke that costs a request there costs one here too.
    ///
    /// One difference is deliberate and worth keeping: this cancels the in-flight request, where the
    /// sandbox only clears its pending timer. An unaborted `fetch` can still resolve after a newer one
    /// and overwrite it, which is a race clearing alone does not close.
    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            suggestions = []
            isSearching = false
            // Back to one term, so the hint returns for the next search. Without this the count stays at
            // whatever the last response said, and an empty field after a multi-term search silently
            // withholds the hint from a user who has not necessarily understood the feature yet.
            segmentCount = 1
            selectedIds = []
            return
        }
        isSearching = true
        // Drop the previous query's results *now*, not when the new ones land.
        //
        // Leaving them up was observed on the simulator as the field reading "poulet" while the list
        // still offered "Poule" — hen, 252 g, an Open Food Facts product — because those rows were the
        // answer to a query the user had already moved on from. Not a latency problem: the API answers
        // in ~70 ms. The bug is that `suggestions` was only ever reassigned on success, so every
        // in-flight moment rendered stale food with nothing marking it stale. In a nutrition app that
        // is the dangerous failure: not blank, not an error, just confidently the wrong ingredient.
        //
        // Clearing costs a spinner-only gap rather than a flash of "Aucun résultat", because that
        // message is itself gated on `!isSearching`.
        //
        // NOT covered by a corpus vector, deliberately: the corpus pins pure functions, and "when may
        // these results be shown" is state-machine timing. Modelling it as a reducer neither client
        // actually calls would produce a green test that proves nothing. Verified on the simulator
        // instead — type "poulet" and the list must never offer "Poule".
        suggestions = []
        selectedIds = []
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let found = try await PocketNutritionApi.shared.search(trimmed, limit: maximumSuggestions)
                guard !Task.isCancelled else { return }
                // The corpus rule, not a local tweak: collapses the duplicate labels the API returns,
                // pins recipes on top, and prefers French once there are enough French results. Without
                // it a search for "poulet" showed four rows all reading "Poulet / 100 g / Produit".
                //
                // NOTE it reorders: recipes are lifted to the top and French floats up above
                // MIN_SAME_LANG. So the server's "first N rows are one best match per term" ordering does
                // NOT survive to here, which is why multi-select is a free-form checklist rather than one
                // slot per term. The header is a count, not a mapping.
                suggestions = deduplicateByLabel(found.rows, preferLanguage: "fr")
                segmentCount = found.segmentCount
                errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                suggestions = []
                errorMessage = (error as? ApiError)?.errorDescription ?? "\(error)"
            }
            isSearching = false
        }
    }

    /// What a tap does: toggle a selection, or add the food straight away.
    ///
    /// The decision is `shouldToggleSelection` from the corpus rather than a local `segmentCount > 1`,
    /// because of the branch that is easy to miss — a **recipe always adds immediately**, even when the
    /// query had three terms, since it unpacks into a whole meal rather than being one of those terms.
    /// The `selection-mode` suite pins it, and a mutation test confirmed the case fails without it.
    private func tap(_ suggestion: IngredientSuggestion) {
        guard shouldToggleSelection(termCount: segmentCount, productType: suggestion.productType) else {
            add(suggestion)
            return
        }
        if selectedIds.contains(suggestion.ingredientId) {
            selectedIds.remove(suggestion.ingredientId)
        } else {
            selectedIds.insert(suggestion.ingredientId)
        }
    }

    /// Adds every checked row, then closes the picker.
    ///
    /// Goes through `add` per row rather than appending directly, so a checked *recipe* still unpacks
    /// through `unpackRecipe` — the same path a single tap takes. `add` clears `query` and `suggestions`
    /// as a side effect, which is why the selection is captured first.
    private func confirmSelection() {
        let chosen = suggestions.filter { selectedIds.contains($0.ingredientId) }
        selectedIds = []
        chosen.forEach(add)
    }

    private func add(_ suggestion: IngredientSuggestion) {
        // A recipe expands into its components; anything else is one row. `unpackRecipe` returning an
        // empty list for a component-less recipe is why this cannot just take `.first`.
        let incoming: [MealIngredient]
        if suggestion.isRecipe {
            incoming = unpackRecipe(suggestion).enumerated().compactMap { index, item in
                buildMealIngredient(item, id: rowId(suggestion.ingredientId, index))
            }
        } else {
            incoming = [suggestion.asMealRow(id: rowId(suggestion.ingredientId, 0))]
        }
        items.append(contentsOf: incoming)
        query = ""
        suggestions = []
    }

    /// The row identity Core will not build: it needs a clock, and `PocketNutritionCore` has none by
    /// design — which is also why the `build-meal-ingredient` vectors exclude `id`.
    private func rowId(_ ingredientId: String, _ index: Int) -> String {
        "\(ingredientId)-\(Date().timeIntervalSince1970)-\(index)"
    }

    /// Removing a row while it is the expanded one must also clear `expandedItemId` — leaving it
    /// pointing at an id no row carries any more would permanently satisfy `scheduleRecompute`'s
    /// "nothing is open" guard as false, since `expandedItemId == nil` never becomes true again on its
    /// own, and the total would go stale after exactly this one interaction.
    private func remove(_ id: String) {
        items.removeAll { $0.id == id }
        if expandedItemId == id { expandedItemId = nil }
        profileCache.removeValue(forKey: id)
    }

    // MARK: - Composed meal

    @ViewBuilder
    private var content: some View {
        // Hidden whenever the suggestion list is open, whatever `items` holds — not just for the empty
        // hint below. A meal with one row already in it (the common case right after a barcode scan,
        // which adds a row in one step rather than the several searches typing usually takes to get
        // there) left the full `List` on screen underneath the suggestion box, and the two competed for
        // the same vertical space: on a compact phone the suggestion list — itself capped at five rows —
        // had nowhere near five rows' worth of room left once the list below it had claimed its share.
        // Collapsing the list here costs nothing a person notices: it reappears the moment a suggestion
        // is tapped and `suggestions` clears, which is the same instant it would have been unable to
        // stay hidden.
        if suggestions.isEmpty {
            if items.isEmpty {
                VStack(spacing: 12) {
                    Text("🥗").font(.system(size: 44))
                    Text(Fr.mealEmpty)
                        .font(.subheadline)
                        .foregroundStyle(PnColor.inkSoft)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            } else {
                List {
                    ForEach($items) { $item in
                        MealIngredientRow(
                            row: $item,
                            isExpanded: expandedItemId == item.id,
                            onToggleExpand: {
                                // The row's own tap target consumes the gesture before it can reach the
                                // outer `.onTapGesture { isQueryFocused = false }` on the whole screen,
                                // so opening or closing a row left the keyboard up if the search field
                                // still had focus from adding the item just above it.
                                isQueryFocused = false
                                expandedItemId = expandedItemId == item.id ? nil : item.id
                            },
                            onEditingWeightChange: { isEditingWeight = $0 }
                        )
                        .listRowBackground(PnColor.surfaceCard)
                    }
                    .onDelete { offsets in
                        offsets.map { items[$0].id }.forEach(remove)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        } else {
            Spacer()
        }
    }

    // MARK: - Totals

    /// Whether the bottom bar is drawn at all.
    ///
    /// A checked multi-term selection always wins: `selectionBar`'s confirm/cancel lives here and has
    /// nowhere else to go. Otherwise the bar hides while the suggestion list is competing for the same
    /// vertical room, and — the point of this property — while there is nothing in it worth showing: an
    /// empty meal with no error has neither a total nor a save button to offer.
    private var showsSummaryBar: Bool {
        // Wins over everything else below: a total about to change, and a save button, are exactly
        // the extra screen noise a person typing an exact weight does not need — see `isEditingWeight`.
        guard !isEditingWeight else { return false }
        guard selectedIds.isEmpty else { return true }
        guard suggestions.isEmpty else { return false }
        return !items.isEmpty || errorMessage != nil
    }

    /// Summed here rather than requested: `POST /nutrition` answers per item, and summing on the client
    /// keeps the total honest when one row fails to resolve — the visible rows always add up to the
    /// total shown. Ported from the former `ResultsView`, unchanged.
    private var totals: Macros {
        (results ?? []).map(Macros.init).reduce(Macros.zero, +)
    }

    /// What used to be `ResultsView`'s whole screen — a total, and a save action — folded into this
    /// one's bottom bar instead of a second screen a tap away. There is no "Modifier le repas" button
    /// here, unlike the old `ResultsView`: that button only ever dismissed back to this screen, which
    /// is exactly where a person already is once the two are merged.
    private var summaryBar: some View {
        VStack(spacing: 8) {
            selectionBar

            // Hidden while the suggestion list is open, same reasoning as `content` hiding the meal
            // list then. `selectionBar` above still has to show while multi-selecting — its
            // confirm/cancel controls are the only way to finish that action — but checking the first
            // box was enough on its own to make this bar appear, and stacking the settled meal's total
            // and save button underneath it doubled the bar's height at exactly the moment the
            // suggestion list, itself capped at five rows, most needed the room.
            if suggestions.isEmpty {
                if let errorMessage {
                    HStack {
                        Text(Fr.error(errorMessage))
                            .font(.footnote)
                            .foregroundStyle(PnColor.onSoftBad)
                        Spacer()
                        Button(Fr.retry) { scheduleRecompute(debounced: false) }
                            .font(.footnote.weight(.semibold))
                    }
                    .padding(12)
                    .background(PnColor.statusBadSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Hidden rather than merely disabled for an empty meal: nothing to total or save yet,
                // and the search field above is the screen's one real task at that point.
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(Fr.resultsTotal)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PnColor.inkSoft)
                            if isComputingTotals {
                                ProgressView().controlSize(.mini)
                            }
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(roundHalfUp(totals.energyKcal)) kcal")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(PnColor.brandLeafDeep)
                            Text(macroSummary)
                                .font(.caption)
                                .foregroundStyle(PnColor.inkSoft)
                        }
                    }

                    Button(Fr.resultsSave) { save() }
                        .buttonStyle(PrimaryButtonStyle())
                        // Nothing to save before the first total lands, and nothing to save twice.
                        .disabled(results == nil || hasSaved)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private var macroSummary: String {
        "P \(formatFrenchNumber((totals.proteinG * 10).rounded() / 10)) g · "
            + "G \(formatFrenchNumber((totals.carbohydratesG * 10).rounded() / 10)) g · "
            + "L \(formatFrenchNumber((totals.fatG * 10).rounded() / 10)) g"
    }

    /// Debounced the same way `scheduleSearch` is, and for the same reason: a burst of changes — every
    /// keystroke typing an exact weight, every 75 ms step while a stepper is held, several rows added
    /// from a multi-term confirm — should cost one request 400 ms after the last change, not one per
    /// mutation. The debounce alone is what keeps this to one request: each new mutation cancels
    /// `recomputeTask` and restarts the wait, so a continuous hold or a fast typist never lets the
    /// timer complete until they actually pause, and a hold lasting several seconds costs the same one
    /// request a hold lasting 400 ms would.
    ///
    /// Deliberately **not** gated on `expandedItemId` any more — an earlier revision only recomputed
    /// once a row closed, on the reasoning that dragging a stepper open should not call the server per
    /// frame. That reasoning was sound but the fix was wrong: the debounce above already prevents that
    /// on its own, and gating on the row being closed meant the total stayed stale for as long as
    /// someone was still looking at the row they had just finished typing an exact number into — which
    /// is exactly when they most want to see it update.
    private func scheduleRecompute(debounced: Bool = true) {
        recomputeTask?.cancel()
        guard !items.isEmpty else {
            results = nil
            errorMessage = nil
            profileCache = [:]
            return
        }

        // A pure quantity change against rows every one of which already has a same-method,
        // same-state server baseline needs no request at all — see `locallyRescaledResults`. This is
        // the common case a typed weight or a stepper tap hits, and it resolves instantly rather than
        // waiting out the debounce below, because there is no network round trip to wait for.
        if let rescaled = locallyRescaledResults() {
            results = rescaled
            errorMessage = nil
            isComputingTotals = false
            return
        }

        recomputeTask = Task {
            if debounced {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
            }
            isComputingTotals = true
            do {
                // Snapshotted rather than read again after the `await` below: `items` could have
                // changed while the request was in flight, and the cache must remember what was
                // actually asked for, not whatever is on screen by the time the answer arrives.
                let requested = items
                let profiles = try await PocketNutritionApi.shared.analyse(requested.map { $0.asRequest() })
                results = profiles
                errorMessage = nil
                for (item, profile) in zip(requested, profiles) {
                    profileCache[item.id] = ProfileBaseline(
                        quantity: item.quantity,
                        cookingMethod: item.cookingMethod,
                        measuredState: item.measuredState,
                        profile: profile
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = (error as? ApiError)?.errorDescription ?? "\(error)"
            }
            isComputingTotals = false
        }
    }

    /// One server-confirmed answer for one row, and the exact inputs it was correct for. A cached
    /// answer is only reusable while `cookingMethod` and `measuredState` still match — those change
    /// the yield-adjusted per-gram values in a way quantity alone does not, so a method or state change
    /// always falls through to a real request, same as a brand-new row with no entry at all.
    private struct ProfileBaseline {
        let quantity: Double
        let cookingMethod: String
        let measuredState: String
        let profile: NutritionalProfile
    }

    /// `nil` unless every current row has a cached baseline at its current cooking method and measured
    /// state — in which case this scales each baseline profile by `quantity / baseline.quantity` and
    /// returns the result, needing no request. A single row failing that test (new, or its method/state
    /// moved on from its baseline) means the whole meal falls back to one real request instead — the
    /// endpoint answers for the whole list at once, so there is no partial-request shape to reuse here.
    private func locallyRescaledResults() -> [NutritionalProfile]? {
        var rescaled: [NutritionalProfile] = []
        rescaled.reserveCapacity(items.count)
        for item in items {
            guard let baseline = profileCache[item.id],
                  baseline.cookingMethod == item.cookingMethod,
                  baseline.measuredState == item.measuredState,
                  baseline.quantity > 0
            else { return nil }
            rescaled.append(baseline.profile.scaled(to: item.quantity, from: baseline.quantity))
        }
        return rescaled
    }

    private func save() {
        // Guarded rather than merely disabled: a double tap that lands before the view updates would
        // otherwise write the meal twice, and a duplicated diary entry is worse than a missed one.
        guard !hasSaved, results != nil else { return }
        hasSaved = true
        let savedItems = items.map { $0.asMealItem() }
        if let editingMealId = editingMeal?.id {
            store.update(id: editingMealId, items: savedItems, totals: totals)
        } else {
            store.save(items: savedItems, totals: totals)
        }
        dismiss()
    }
}

/// One row in the suggestion list.
///
/// The row used to be a label, a weight in grams and a "Produit" capsule, and that was not enough to
/// choose with: a search for "salade" returned rows whose only visible difference was nothing at all.
/// Three things were added, in the order a person actually uses them:
///
/// 1. **A filled thumbnail slot.** An Open Food Facts photo when there is one, the food-group glyph
///    when there is not. Both branches draw something, which is the point — Open Food Facts has photos
///    for about four fifths of its products and the knowledge base has none at all, so drawing only
///    `imageUrl` would have given every industrial product a photograph and every curated ingredient a
///    hole, making the packaged result look more authoritative than the reference one.
/// 2. **The brand**, on a second line. This is what distinguishes two products that share a name, and
///    the reason the deduplication key now includes it.
/// 3. **A distinct recipe row.** `deduplicateByLabel` pins recipes to the top of the list, so the most
///    valuable result — one tap becoming a whole meal — was sitting first with nothing to say so.
private struct SuggestionRow: View {
    /// Fixed row height: a 44-point thumbnail plus 8 points of padding above and below.
    ///
    /// Exposed because the list caps its own height and must do so on a row boundary — see the comment
    /// on that cap. Keeping the number here means changing the row cannot silently start slicing it.
    static let height: CGFloat = 60

    let suggestion: IngredientSuggestion
    let alreadyAdded: Bool

    /// `nil` in single-term mode, so the checkbox is **absent rather than unchecked**.
    ///
    /// That distinction is the whole point: `height` is 60 points and the list caps itself at a whole
    /// number of rows, so anything that changes the row's height starts slicing the last one in half. An
    /// always-present checkbox would also tell a single-term user there is a selection to make when there
    /// is not.
    let checked: Bool?

    var body: some View {
        HStack(spacing: 10) {
            if let checked {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.body)
                    .foregroundStyle(checked ? PnColor.brandLeafDeep : PnColor.inkSoft)
                    .frame(width: 22)
            }
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(alreadyAdded ? PnColor.inkSoft : PnColor.inkDefault)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(PnColor.inkSoft)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            trailingBadge
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // Pinned rather than left to intrinsic sizing, so `height` above is enforced instead of merely
        // describing what the padding happens to add up to. Both labels are lineLimit(1), so nothing
        // needs more room than this.
        .frame(height: Self.height)
        .contentShape(Rectangle())
    }

    // MARK: - Pieces

    /// A fixed 44-point square whatever it contains, so the labels stay aligned down the list. 44 is
    /// also the minimum comfortable touch target, and the whole row is tappable.
    private var thumbnail: some View {
        ZStack {
            // surfaceCream, not surfaceCard. The row sits on a white card, so a white slot was white
            // on white — 1.00:1, an invisible container that left the glyph floating while photo rows
            // showed a solid block. Cream is the design system's recessed surface and is the token
            // meant for exactly this.
            RoundedRectangle(cornerRadius: 8).fill(PnColor.surfaceCream)
            if suggestion.isRecipe {
                Text("🍲").font(.title3)
            } else if let raw = suggestion.imageUrl, let url = URL(string: raw) {
                // AsyncImage rather than a dependency: it is SwiftUI's own, it caches within the
                // session, and it only fetches for rows the List actually realises. The URL is used as
                // served — Open Food Facts also publishes .100.jpg and .200.jpg variants at the same
                // path, but deriving one means pattern-matching their filename scheme, and a wrong
                // guess is a broken image rather than a smaller one.
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        // A dead link falls back to the same glyph a photo-less row gets, so a row is
                        // never left with an empty square.
                        glyph
                    case .empty:
                        glyph
                    @unknown default:
                        glyph
                    }
                }
            } else {
                glyph
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// The food-group icon, or a neutral mark when the group has none — `sauce`, `seaweed` and `other`
    /// are unmapped on purpose, and `other` is what every product and recipe carries.
    private var glyph: some View {
        Text(foodGroupIcon(suggestion.foodGroup) ?? "🍽️")
            .font(.title3)
            .foregroundStyle(PnColor.inkSoft)
    }

    private var title: String {
        suggestion.isRecipe
            ? String(format: Fr.searchRecipePrefix, suggestion.label)
            : suggestion.label
    }

    /// Brand first, because it is the discriminator; the reference weight second. A recipe lists its
    /// components instead, which is what tells you whether this is the raclette you meant.
    private var subtitle: String? {
        if suggestion.isRecipe {
            let names = (suggestion.recipeComponents ?? []).map(\.ingredient.label)
            return names.isEmpty ? nil : names.joined(separator: ", ")
        }
        let grams = suggestion.servingG.map { "\(formatFrenchNumber($0)) g" }
        return [suggestion.brand, grams].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }

    @ViewBuilder
    private var trailingBadge: some View {
        if alreadyAdded {
            Text(Fr.searchAlreadyAdded)
                .font(.caption2)
                .foregroundStyle(PnColor.inkSoft)
        } else if suggestion.isRecipe {
            let count = (suggestion.recipeComponents ?? []).count
            Text(String(format: Fr.searchRecipeComponentCount, count))
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(PnColor.huePlumSoft)
                .foregroundStyle(PnColor.onSoftPlum)
                .clipShape(Capsule())
        } else if suggestion.isProduct {
            Text(Fr.searchProductBadge)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(PnColor.hueSeaSoft)
                .foregroundStyle(PnColor.onSoftSea)
                .clipShape(Capsule())
        }
    }
}

private extension String {
    /// `joined` on an empty list yields "", which would render as a blank second line rather than none.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension NutritionalProfile {
    /// Rescales every quantity-dependent field to `newQuantity`, given it was correct at `oldQuantity`.
    /// Name, unit, cooking method and measured state are unaffected by how much of the food there is,
    /// so only the nutrient fields move. Optional fields stay optional under scaling — multiplying
    /// `nil` by a ratio would manufacture a fibre or sugar figure the server never actually sent.
    func scaled(to newQuantity: Double, from oldQuantity: Double) -> NutritionalProfile {
        let ratio = newQuantity / oldQuantity
        return NutritionalProfile(
            name: name,
            quantity: newQuantity,
            unit: unit,
            cookingMethod: cookingMethod,
            measuredState: measuredState,
            energyKcal: energyKcal * ratio,
            proteinG: proteinG * ratio,
            fatG: fatG * ratio,
            carbohydratesG: carbohydratesG * ratio,
            fiberG: fiberG.map { $0 * ratio },
            sugarsG: sugarsG.map { $0 * ratio }
        )
    }
}

/// One row of the meal: collapsed to a name, a one-line portion summary and the weight until tapped
/// open, then the cooking pill, a remove button and the full portion ladder.
///
/// THE ACCORDION MATCHES THE SANDBOX (`docs/SPECIFICATION.md` §7.6–7.8), which this app's row used not
/// to: every ingredient used to show its full portion ladder at once, so composing a five-item meal
/// meant scrolling past five stepper rows to reach the sixth ingredient. Collapsed, a row is a single
/// line — name, `describeQuantity`'s own summary, the weight — and expanding it is `MealBuilderView`'s
/// `expandedItemId`, not local state, because only one row may be open at a time, same as the sandbox's
/// `expandedId`.
///
/// THE METHOD CHIPS ARE ALSO COLLAPSED, as they are in the sandbox. Seven always-visible chips per row
/// cost a horizontal scroller and most of the row's height while answering a question the user has
/// usually already answered — the API's `typicalState` gets the method right most of the time.
/// Collapsing them behind a pill that *states the current answer* trades a tap for the room the
/// weighed-state toggle needs, and that toggle is the more consequential of the two by a wide margin.
private struct MealIngredientRow: View {
    @Binding var row: MealIngredient
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    /// Forwarded straight from `PortionLadder`'s own `onEditingChange` — see that type's doc comment.
    var onEditingWeightChange: (Bool) -> Void = { _ in }

    /// Closed by default: the pill's whole purpose is that the row is short until you ask it not to be.
    @State private var isPickingMethod = false

    /// Closed by default, same reasoning as `isPickingMethod` — the feedback form is rare enough that
    /// it should cost a tap, not a permanent line in every expanded row.
    @State private var isReportingFeedback = false
    @State private var expandedFeedbackDraft: (category: String, error: FeedbackErrorDef)?
    @State private var feedbackDraftValue = ""
    @State private var feedbackDraftUnit = ""
    @State private var feedbackCorrections: [FeedbackCorrection] = []
    @State private var feedbackComment = ""
    @State private var feedbackStatus: FeedbackSubmitStatus = .idle
    /// Fetched once per sheet presentation, purely to enrich `feedbackCurrentValue`'s hints for the
    /// nutrition/identity categories — `MealIngredient` carries neither a raw nutrient profile nor the
    /// canonical name/food group, only what `/ingredients/search` returns. `nil` (fetch still pending,
    /// failed, or the id is unknown) just means those hints stay absent; the form works either way.
    @State private var fetchedIngredientDetail: IngredientDetail?

    private enum FeedbackSubmitStatus: Equatable {
        case idle
        case sending
        case done
        case error
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isExpanded {
                expandedHeader
                PortionLadder(row: $row, onEditingChange: onEditingWeightChange)
                feedbackFooter
            } else {
                collapsedRow
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        // Unconditional now that the chevron button is gone — it was the only way to collapse an
        // expanded row, so the row itself has to answer both directions of the tap. Nested controls
        // (methodPill, the weight field, the steppers) all claim their own taps ahead of this: each
        // is `.buttonStyle(.plain)` or its own gesture, which is exactly what lets a plain SwiftUI
        // `.onTapGesture` on an ancestor lose to a real control's tap rather than swallow it — the
        // same rule the "Terminé" button crash/no-op bugs were about, applied on purpose this time.
        .onTapGesture { onToggleExpand() }
        .sheet(isPresented: $isPickingMethod) { methodSheet }
        .sheet(isPresented: $isReportingFeedback) { feedbackSheet }
    }

    // MARK: - Collapsed

    /// "Riz blanc cuit" / "1 part" / "165g" / ⌄ — `docs/SPECIFICATION.md` §7.6. The caption is
    /// `describeQuantity`'s own summary, the same corpus output the expanded ladder used to show
    /// trailing its stepper row; moved here rather than duplicated, since a collapsed row is exactly
    /// the "one line a user reads without expanding anything" that function was written for.
    private var collapsedRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PnColor.inkDefault)
                    .lineLimit(1)
                if !row.summary.primary.isEmpty {
                    Text(row.summary.primary)
                        .font(.caption2)
                        .foregroundStyle(PnColor.inkSoft)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text("\(formatFrenchNumber(row.quantity)) \(row.displayUnit == "ml" ? "mL" : "g")")
                .font(.caption)
                .foregroundStyle(PnColor.inkSoft)
        }
    }

    // MARK: - Expanded

    /// Name, the cooking pill, a remove button and a collapse chevron — `docs/SPECIFICATION.md` §7.8.
    /// The remove button is new here: collapsed rows still delete via the List's native swipe, but an
    /// expanded row has no swipe target of its own (it is no longer a single compact line), so it needs
    /// an explicit affordance instead of losing delete entirely while open.
    /// Stacked rather than side by side. A long product name (Open Food Facts labels routinely run
    /// three lines at this width, and are not this app's to shorten) wraps on the left while the pill
    /// floated alone at the top right, which read as lopsided: a name using its full height on one
    /// side, empty space under the pill on the other. Neither the name nor the pill's own text is the
    /// fix — putting them on separate lines, pill left-aligned below rather than pinned to the trailing
    /// edge, is what removes the imbalance without touching either.
    /// Tries the side-by-side layout first and only drops to the stacked one when the label does not
    /// fit beside the pill on one line — a fixed choice either way loses somewhere: side by side always
    /// wraps a long Open Food Facts name into an ugly float next to an orphaned pill, and always
    /// stacking costs a short name ("carotte") a line of height it never needed. `ViewThatFits` measures
    /// both at each row's actual width and picks the one that means the label does not have to wrap,
    /// rather than guessing a length threshold that would drift out of sync with font size or Dynamic
    /// Type.
    private var expandedHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PnColor.inkDefault)
                Spacer(minLength: 0)
                methodPill
            }

            // Extra bottom padding only here, not on the side-by-side variant above: stacked, the pill
            // is the header's last line, so it sits right above the quick buttons with only the outer
            // VStack's 10 pt gap between them — next to the 6 pt gap already separating it from the
            // label above, the pill read as sandwiched between two nearly-equal gaps rather than
            // clearly the end of the header. Side by side the whole header is one line, already farther
            // from the buttons below, so it never needed this.
            VStack(alignment: .leading, spacing: 6) {
                Text(row.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PnColor.inkDefault)
                methodPill
            }
            .padding(.bottom, 6)
        }
    }

    // MARK: - Feedback

    /// A discreet trailing link, not a full-width button: reporting an imprecision is rare next to
    /// changing the method or the weight, and this row already has three tap targets fighting the
    /// outer `onTapGesture` — the sandbox's own footer button is the same size of afterthought.
    private var feedbackFooter: some View {
        HStack {
            Spacer()
            Button {
                isReportingFeedback = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "flag")
                        .font(.caption2)
                    Text(Fr.ingredientReport)
                        .font(.caption)
                }
                .foregroundStyle(PnColor.inkSoft)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Fr.ingredientReportAria)
        }
    }

    // MARK: - The pill

    /// States the current answer rather than being a bare disclosure arrow — "🔥 Grillé (pesé après
    /// cuisson)". A chevron alone would hide two decisions that change the numbers, and the point of
    /// collapsing is to save room, not to save the user from knowing.
    private var methodPill: some View {
        Button {
            isPickingMethod = true
        } label: {
            HStack(spacing: 4) {
                Text(pillText)
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(pillBackground)
            .foregroundStyle(pillForeground)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Fr.changeCooking)
        .accessibilityValue(pillText)
    }

    private var pillText: String {
        let method = PnCooking.methods.first { $0.id == row.cookingMethod }
        let emoji = row.cookingMethod == "raw" ? "🌿" : (method?.emoji ?? "🍲")
        let label = Fr.cookingMethod(row.cookingMethod)
        // The weighed state is only meaningful once something has been cooked: a raw weight of a raw
        // food is the same number either way, so appending "(pesé avant cuisson)" there would be noise
        // dressed as information. The sandbox makes the same call.
        guard row.cookingMethod != "raw" else { return "\(emoji) \(label)" }
        return "\(emoji) \(label) \(Fr.weighedInline(Fr.measuredWhen(row.measuredState)))"
    }

    private var pillBackground: Color {
        PnCooking.methods.first { $0.id == row.cookingMethod }?.soft ?? PnColor.surfaceCream
    }

    private var pillForeground: Color {
        PnCooking.methods.first { $0.id == row.cookingMethod }?.onSoft ?? PnColor.inkSoft
    }

    // MARK: - The bottom sheet

    /// The method picker that replaces the sandbox's drag-between-lanes, and replaces this row's own
    /// former inline chip-scroller: a sheet gives the seven options and the weighed-state toggle a full
    /// screen width instead of squeezing both into whatever room the row had left.
    ///
    /// Selecting a row runs `applyMethodChange`, so the weight follows the method: switch a grilled row
    /// to raw and the grams move back to the raw equivalent. That is the corpus function,
    /// vector-verified, rather than arithmetic repeated here. The sheet stays open after a tap — closing
    /// it is a separate, deliberate action — because the weighed-state toggle below the list is often the
    /// next thing to check, and dismissing on every method tap would cost a re-open for that.
    ///
    /// No generic "cuit (générique)" row: Knowledge now names a specific method for every ingredient, and
    /// `asMealRow`'s own fallback defaults to "grilled" rather than that retired bucket, so a row's
    /// `cookingMethod` is always one of `PnCooking.methods` here.
    private var methodSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(PnCooking.methods) { method in
                        let selected = method.id == row.cookingMethod
                        methodOptionRow(
                            emoji: method.emoji,
                            label: Fr.cookingMethod(method.id),
                            subtitle: yieldHint(for: method.id),
                            selected: selected
                        ) {
                            row = applyMethodChange(row, to: method.id)
                        }
                    }
                }

                // Whether the weight is a pre- or post-cooking measurement. The copy deck calls this
                // "the most consequential control in the UI": it is the only control in the product
                // that can be wrong by 15–40% while every screen still looks correct. Listed as two
                // rows rather than the two side-by-side capsules this used to be, so it reads the same
                // way as the method list above it instead of switching shape halfway down the sheet.
                // Hidden for raw rows, where there is nothing to convert and the question has no answer.
                if row.cookingMethod != "raw" {
                    Section(Fr.weighedLabel) {
                        methodOptionRow(
                            emoji: "🌿",
                            label: Fr.measuredBeforeLong,
                            selected: row.measuredState == "raw"
                        ) {
                            row = switchMeasuredState(row, to: "raw")
                        }
                        methodOptionRow(
                            emoji: "🍽️",
                            label: Fr.measuredAfterLong,
                            selected: row.measuredState == "cooked"
                        ) {
                            row = switchMeasuredState(row, to: "cooked")
                        }
                    }
                }
            }
            .navigationTitle(Fr.mealCooking)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Fr.aboutClose) { isPickingMethod = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Why the weight moves when this method is chosen — "Cet aliment pèse 2,4x plus lourd une fois
    /// cuit" for rice, which gains water as it boils, or the "moins lourd" counterpart for a food that
    /// loses moisture, like grilled meat. Answers the question the picker itself cannot: which of these
    /// six is worth tapping.
    ///
    /// Goes through `resolveYieldFactor`, the same corpus function `applyMethodChange` uses, rather than
    /// reading `yieldFactors` directly — so this always describes the ratio that will actually apply,
    /// generic-`cooked`-key fallback included. Nil rather than "1x" when Knowledge has no data at all:
    /// a fabricated "no change" reads as a measured fact, and the corpus does not invent yields.
    private func yieldHint(for methodId: String) -> String? {
        let factor = resolveYieldFactor(row.yieldFactors, method: methodId)
        guard factor != 1 else { return nil }
        let ratio = factor > 1 ? factor : 1 / factor
        let display = formatFrenchNumber((ratio * 10).rounded() / 10)
        let direction = factor > 1 ? "plus" : "moins"
        return "Cet aliment pèse \(display)x \(direction) lourd une fois cuit"
    }

    /// One row of the sheet's method (or weighed-state) list: emoji, label, an optional yield subtitle,
    /// and a trailing checkmark when it is the current answer — the sheet's equivalent of the collapsed
    /// chip's fill colour.
    ///
    /// `.contentShape(Rectangle())` on the full-width HStack, not just the two `Text`s inside it,
    /// because a plain SwiftUI `Button` without a background otherwise hit-tests only the glyphs
    /// themselves: the `Spacer` and the blank trailing space on an unselected row (no checkmark to
    /// fill it) registered no tap at all, so "tap the row" worked only if the row happened to be the
    /// selected one or the finger landed on the label text exactly.
    private func methodOptionRow(
        emoji: String,
        label: String,
        subtitle: String? = nil,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(emoji)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).foregroundStyle(PnColor.inkDefault)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(PnColor.inkSoft)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(PnColor.brandLeafDeep)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // aria-pressed's equivalent: without it VoiceOver reads every row and never says which is on.
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - The feedback sheet

    /// Guided-correction form behind "Signaler": pick a category, pick the specific error, type the
    /// corrected value, repeat for as many fields as apply, then an optional free comment. Ports
    /// `FeedbackDialog.tsx`'s category → error → typed-input flow onto `List`/`DisclosureGroup` rather
    /// than the sandbox's own accordion markup — a `DisclosureGroup` already gives each category
    /// independent expand/collapse state for free, so nothing here tracks which one is open.
    private var feedbackSheet: some View {
        NavigationStack {
            Group {
                if feedbackStatus == .done {
                    feedbackSuccessView
                } else {
                    feedbackFormView
                }
            }
            .navigationTitle(Fr.feedbackTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Fr.feedbackClose) { isReportingFeedback = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Runs once per presentation (SwiftUI re-runs `.task` each time this view appears, and cancels
        // it on dismiss) — best-effort only, so a slow or failed fetch never blocks the form itself.
        .task { await loadIngredientDetail() }
    }

    private func loadIngredientDetail() async {
        fetchedIngredientDetail = try? await PocketNutritionApi.shared.ingredientDetail(row.ingredientId)
    }

    private var feedbackSuccessView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(PnColor.brandLeafDeep)
            Text(Fr.feedbackSuccess)
                .multilineTextAlignment(.center)
                .foregroundStyle(PnColor.inkDefault)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var feedbackFormView: some View {
        List {
            if !feedbackCorrections.isEmpty {
                Section {
                    ForEach(Array(feedbackCorrections.enumerated()), id: \.offset) { index, correction in
                        HStack {
                            Text(feedbackCorrectionSummary(correction))
                                .font(.caption)
                                .foregroundStyle(PnColor.inkDefault)
                            Spacer()
                            Button {
                                feedbackCorrections.remove(at: index)
                                if feedbackStatus == .error { feedbackStatus = .idle }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(PnColor.inkSoft)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Fr.feedbackRemoveCorrection)
                        }
                    }
                }
            }

            Section(Fr.feedbackIntro) {
                ForEach(FeedbackCatalog.categories) { category in
                    DisclosureGroup(category.label) {
                        ForEach(category.errors) { error in
                            feedbackErrorRow(category: category, error: error)
                        }
                    }
                }
            }

            Section(Fr.feedbackComment) {
                TextField(Fr.feedbackComment, text: $feedbackComment, axis: .vertical)
                    .lineLimit(2...4)
                    .onChange(of: feedbackComment) {
                        if feedbackStatus == .error { feedbackStatus = .idle }
                    }
            }

            Section {
                Button {
                    Task { await submitFeedback() }
                } label: {
                    HStack {
                        Spacer()
                        if feedbackStatus == .sending {
                            ProgressView()
                        } else {
                            Text(Fr.feedbackSubmit)
                        }
                        Spacer()
                    }
                }
                .disabled(!canSendFeedback)

                if feedbackStatus == .error {
                    Text(Fr.feedbackFailure)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    /// One reportable field within an expanded category: its label, the current-value hint when it has
    /// one, and — once tapped — the typed input matching `error.input`'s kind plus an "Ajouter" step
    /// that appends a `FeedbackCorrection` to the pending list. Mirrors `FeedbackDialog.tsx`'s per-error
    /// row and its `DraftInput`.
    private func feedbackErrorRow(category: FeedbackCategory, error: FeedbackErrorDef) -> some View {
        let isActive = expandedFeedbackDraft?.category == category.code && expandedFeedbackDraft?.error.code == error.code
        let hint = feedbackCurrentValue(for: error.hint)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                selectFeedbackError(category: category.code, error: error)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(error.label)
                            .foregroundStyle(PnColor.inkDefault)
                        if let hint {
                            Text("actuel : \(hint)")
                                .font(.caption2)
                                .foregroundStyle(PnColor.inkSoft)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isActive {
                feedbackDraftInput(for: error)
            }
        }
    }

    @ViewBuilder
    private func feedbackDraftInput(for error: FeedbackErrorDef) -> some View {
        HStack(spacing: 8) {
            switch error.input {
            case .select(let options):
                Picker(error.label, selection: $feedbackDraftValue) {
                    ForEach(options) { option in
                        Text(option.label).tag(option.code)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            case .numberUnit(let units):
                TextField(error.label, text: $feedbackDraftValue)
                    .keyboardType(.decimalPad)
                Picker(Fr.feedbackUnitAria, selection: $feedbackDraftUnit) {
                    ForEach(units, id: \.self) { unit in
                        Text(unit).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            case .number(let suffix):
                TextField(error.label, text: $feedbackDraftValue)
                    .keyboardType(.decimalPad)
                if let suffix {
                    Text(suffix).font(.caption).foregroundStyle(PnColor.inkSoft)
                }
            case .text(let placeholder):
                TextField(placeholder ?? "", text: $feedbackDraftValue)
            }

            Button(Fr.feedbackAdd) {
                addFeedbackCorrection()
            }
            .buttonStyle(.borderedProminent)
            .disabled(feedbackDraftValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func selectFeedbackError(category: String, error: FeedbackErrorDef) {
        expandedFeedbackDraft = (category, error)
        switch error.input {
        case .select(let options):
            feedbackDraftValue = options.first?.code ?? ""
            feedbackDraftUnit = ""
        case .numberUnit(let units):
            feedbackDraftValue = ""
            feedbackDraftUnit = units.first ?? ""
        case .number, .text:
            feedbackDraftValue = ""
            feedbackDraftUnit = ""
        }
    }

    private func addFeedbackCorrection() {
        guard let draft = expandedFeedbackDraft else { return }
        let value = feedbackDraftValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let unit: String?
        if case .numberUnit = draft.error.input {
            unit = feedbackDraftUnit
        } else {
            unit = nil
        }
        feedbackCorrections.append(
            FeedbackCorrection(category: draft.category, code: draft.error.code, value: value, unit: unit)
        )
        expandedFeedbackDraft = nil
        feedbackDraftValue = ""
        feedbackDraftUnit = ""
        if feedbackStatus == .error { feedbackStatus = .idle }
    }

    /// "Mesures & portions › Poids de référence : 180 g" — resolves the label back out of
    /// `FeedbackCatalog` by code, the same lookup `FeedbackDialog.tsx`'s `categoryLabel`/`errorLabel`
    /// do, rather than carrying the label alongside each pending correction.
    private func feedbackCorrectionSummary(_ correction: FeedbackCorrection) -> String {
        let category = FeedbackCatalog.categories.first { $0.code == correction.category }
        let error = category?.errors.first { $0.code == correction.code }
        var text = "\(category?.label ?? correction.category) › \(error?.label ?? correction.code)"
        if let value = correction.value {
            text += " : \(value)"
            if let unit = correction.unit { text += " \(unit)" }
        }
        return text
    }

    /// The ingredient's current value for a hinted error, shown next to it so the user can see what
    /// they would be contradicting — mirrors `FeedbackDialog.tsx`'s `currentValue()`. Only the fields
    /// this row actually carries: there is no result context here, unlike the sandbox, which also reads
    /// hints from a prediction result when the dialog opens from there instead of from the card.
    private func feedbackCurrentValue(for hint: FeedbackCurrentValueHint?) -> String? {
        guard let hint else { return nil }
        switch hint {
        case .referenceWeight:
            return "\(Int(row.basePortionG.rounded())) g"
        case .displayUnit:
            return row.displayUnit
        case .servingUnits:
            return row.servingUnits.isEmpty ? "aucune" : row.servingUnits.map(\.labelFr).joined(separator: ", ")
        case .rawCooked:
            guard let canEatRaw = row.canEatRaw else { return nil }
            return canEatRaw ? "cru possible" : "cuisson requise"
        case .cookingMethod:
            return row.cookingMethod
        case .energy:
            guard let value = fetchedIngredientDetail?.referenceNutrition?.energyKcal else { return nil }
            return "\(Int(value.rounded())) kcal"
        case .protein:
            guard let value = fetchedIngredientDetail?.referenceNutrition?.proteinG else { return nil }
            return "\(formatFrenchNumber(value)) g"
        case .fat:
            guard let value = fetchedIngredientDetail?.referenceNutrition?.fatG else { return nil }
            return "\(formatFrenchNumber(value)) g"
        case .carbs:
            guard let value = fetchedIngredientDetail?.referenceNutrition?.carbohydratesG else { return nil }
            return "\(formatFrenchNumber(value)) g"
        case .fiber:
            guard let value = fetchedIngredientDetail?.referenceNutrition?.fiberG else { return nil }
            return "\(formatFrenchNumber(value)) g"
        case .nameFr:
            return fetchedIngredientDetail?.nameFr
        case .nameEn:
            return fetchedIngredientDetail?.nameEn
        case .foodGroup:
            guard let code = fetchedIngredientDetail?.foodGroup else { return nil }
            return FeedbackCatalog.foodGroups.first { $0.code == code }?.label ?? code
        }
    }

    private var canSendFeedback: Bool {
        let hasContent = !feedbackCorrections.isEmpty
            || !feedbackComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasContent && feedbackStatus != .sending && feedbackStatus != .done
    }

    private func submitFeedback() async {
        guard canSendFeedback else { return }
        feedbackStatus = .sending
        let trimmedComment = feedbackComment.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = FeedbackRequest(
            name: row.label,
            corrections: feedbackCorrections,
            comment: trimmedComment.isEmpty ? nil : trimmedComment,
            cookingMethod: row.cookingMethod,
            measuredState: row.measuredState,
            source: nil
        )
        do {
            try await PocketNutritionApi.shared.submitFeedback(request)
            feedbackStatus = .done
        } catch {
            feedbackStatus = .error
        }
    }
}
