// SPDX-License-Identifier: MPL-2.0

import SwiftUI
import PocketNutritionCore

/// Home screen: the meals kept on this device, newest day first.
///
/// This screen has no counterpart in the sandbox — the prototype persists nothing. It exists because
/// a food diary that forgets is not a diary, and it is the reason the app needs its own privacy copy
/// rather than the sandbox's "aucune donnée personnelle n'est conservée".
struct JournalView: View {

    @Environment(JournalStore.self) private var store
    @State private var composerTarget: ComposerTarget?
    @State private var isShowingAbout = false

    var body: some View {
        NavigationStack {
            Group {
                if store.meals.isEmpty {
                    emptyState
                } else {
                    mealList
                }
            }
            .background(PnColor.surfacePaper)
            .navigationTitle(Fr.journalTitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        composerTarget = .new
                    } label: {
                        Label(Fr.journalAdd, systemImage: "plus")
                    }
                }
                // A menu rather than a direct button, even though it holds one entry today: the shape
                // a second entry (settings, export, whatever comes next) can grow into without a
                // redesign, at the cost of one extra tap for the entry it actually holds right now.
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            isShowingAbout = true
                        } label: {
                            Text("Informations de licence")
                        }
                    } label: {
                        Image(systemName: "gearshape")
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
                }
            }
            .sheet(isPresented: $isShowingAbout) {
                AboutView()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("🥗").font(.system(size: 52))
            Text(Fr.journalEmpty)
                .font(.subheadline)
                .foregroundStyle(PnColor.inkSoft)
                .multilineTextAlignment(.center)
            Button(Fr.journalAdd) { composerTarget = .new }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
            // Shown on the empty state rather than buried in a settings screen: the one moment the
            // user is deciding whether to trust the app with a diary is before they start one.
            Text(Fr.journalPrivacy)
                .font(.caption)
                .foregroundStyle(PnColor.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mealList: some View {
        List {
            ForEach(store.mealsByDay, id: \.day) { group in
                Section {
                    ForEach(group.meals) { meal in
                        Button {
                            composerTarget = .edit(meal)
                        } label: {
                            MealRow(meal: meal)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(PnColor.surfaceCard)
                    }
                    .onDelete { offsets in
                        offsets.map { group.meals[$0] }.forEach(store.delete)
                    }
                } header: {
                    Text(Self.dayFormatter.string(from: group.day))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PnColor.inkSoft)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    /// A date formatter *is* the right tool here, unlike for numbers. The corpus pins number rendering
    /// because a thousands separator changes the value a user reads; a date header has no such
    /// contract and the platform's French formatting is what a French user expects.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter
    }()
}

/// What the meal builder's `fullScreenCover` is showing: a blank compose, or an existing entry to edit.
///
/// A single presented item rather than two booleans, so the cover can never end up representing both at
/// once — a state a pair of `Bool`s would have allowed by construction.
private enum ComposerTarget: Identifiable {
    case new
    case edit(SavedMeal)

    /// Fixed rather than freshly generated, since `.new` carries no identity of its own: a random UUID
    /// re-computed on every access would look like a *different* item to SwiftUI on each diff, which is
    /// exactly the identity churn `Identifiable` exists to avoid.
    private static let newId = UUID()

    var id: UUID {
        switch self {
        case .new: Self.newId
        case .edit(let meal): meal.id
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

            HStack(spacing: 12) {
                // roundHalfUp rather than Int(): the corpus rule, so the phone and the web never
                // disagree about which side of a .5 a number lands on.
                Text("\(roundHalfUp(meal.totals.energyKcal)) kcal")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(PnColor.brandLeafDeep)
                macro("P", meal.totals.proteinG)
                macro("G", meal.totals.carbohydratesG)
                macro("L", meal.totals.fatG)
            }
        }
        .padding(.vertical, 4)
    }

    /// contract: nutrients.proteinAbbr / carbsAbbr / fatAbbr — P, G, L.
    private func macro(_ abbreviation: String, _ grams: Double) -> some View {
        Text("\(abbreviation) \(formatFrenchNumber((grams * 10).rounded() / 10)) g")
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
