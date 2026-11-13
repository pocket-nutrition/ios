// SPDX-License-Identifier: MPL-2.0

import SwiftUI
import PocketNutritionCore

/// The portion control: a row of quick buttons, then the stepper and the editable weight.
///
/// ```
/// [ Demi ][ 1 Part ][ Double ]
/// [ − ][      150 g ✏️      ][ + ]
/// ```
///
/// Sized to match the sandbox's `PortionScale` (`docs/SPECIFICATION.md` §7.10) rather than this app's
/// own former, much smaller controls: 48-point steppers and a bold, large-type weight field, because
/// this is the one row in the meal builder a user touches for every single ingredient, and small
/// targets there cost taps across the whole meal. The summary line this row used to show — "≈ 1,3
/// portion" — now lives on the collapsed row instead (`MealBuilderView.swift`'s `collapsedSummary`),
/// which is also where the sandbox puts it.
///
/// Every label and every number here comes from a corpus function. Nothing is formatted locally —
/// `stepLabel` names each rung, `stepRawWeight` says what a rung weighs. That is the point: the
/// sandbox and the two apps show the same words for the same row, and a disagreement fails a vector
/// test rather than shipping.
///
/// TWO TRAPS THE CORPUS ENCODES AND THIS VIEW MUST NOT UNDO
/// `shortcutProfile` guarantees **between two and four** entries, never a fixed count. Equal-width flex
/// (rather than the horizontal scroll this view used before) matches the sandbox, and holds up because
/// the corpus caps this at four short labels — `.minimumScaleFactor` is the safety valve for the rare
/// long increment label rather than a scroll container. And `stepRawWeight` **ignores the base portion
/// for unit steps** — recomputing a weight here instead of calling it would reintroduce exactly the bug
/// its vectors exist to catch.
struct PortionLadder: View {
    @Binding var row: MealIngredient
    /// Reported up to `MealBuilderView`, which uses it to hide the bottom total/save bar while typing:
    /// that bar showing a kcal total that is about to change, plus a save button, was itself "too much
    /// info" competing with a field someone is midway through typing an exact number into.
    var onEditingChange: (Bool) -> Void = { _ in }

    /// Grams (or mL) moved per tap of the +/- buttons. One value for every ingredient rather than a
    /// step scaled to the current weight, so repeated taps stay predictable. Bounds match the
    /// sandbox's `PortionScale` so a weight typed on one client is always reachable by holding on
    /// another.
    private static let stepAmount: Double = 5
    private static let minimumQuantity: Double = 1
    private static let maximumQuantity: Double = 5000

    /// The decimal pad has no return key, so nothing dismisses it on its own — and the screen-wide
    /// "tap anywhere to blur" gesture in `MealBuilderView` only ever targeted the search field's own
    /// focus state, which this field never touched. Without a focus state of its own the keyboard, once
    /// open, had no way to close: not tap-outside, not a return key, nothing.
    @FocusState private var isValueFieldFocused: Bool

    /// Collapsed to just the field, plus the confirm button below it, while typing. The quick buttons
    /// and steppers answer "what should the weight be", which is not the question once someone is
    /// midway through typing an exact one — and shrinking them out of the way is what makes room for
    /// an on-screen confirm button that a person notices without having to look up at the keyboard's
    /// own toolbar for it, which is what this replaced.
    ///
    /// **Every view below stays in the tree at all times** — collapsed with `.frame`/`.opacity`, never
    /// removed with an `if`. `valueField`'s `TextField` is what is gaining focus at the exact moment
    /// this state flips, and restructuring its own parent hierarchy in that same instant (which an `if`
    /// around the surrounding `HStack` did — moving the field from a three-child row to a lone view)
    /// crashed: the focus engine and the view differ were fighting over the same view in the same
    /// transaction. Resizing views in place changes nothing about who is whose child, so the field's
    /// identity never moves while it is becoming first responder.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            quickButtons
                .frame(maxHeight: isValueFieldFocused ? 0 : nil, alignment: .top)
                .opacity(isValueFieldFocused ? 0 : 1)
                .allowsHitTesting(!isValueFieldFocused)
                .clipped()

            HStack(spacing: 8) {
                HoldRepeatStepButton(
                    systemName: "minus",
                    label: "Diminuer la quantité",
                    disabled: row.quantity <= Self.minimumQuantity,
                    step: { adjust(by: -Self.stepAmount) }
                )
                .frame(width: isValueFieldFocused ? 0 : nil)
                .opacity(isValueFieldFocused ? 0 : 1)
                .allowsHitTesting(!isValueFieldFocused)
                .clipped()

                valueField

                HoldRepeatStepButton(
                    systemName: "plus",
                    label: "Augmenter la quantité",
                    disabled: row.quantity >= Self.maximumQuantity,
                    step: { adjust(by: Self.stepAmount) }
                )
                .frame(width: isValueFieldFocused ? 0 : nil)
                .opacity(isValueFieldFocused ? 0 : 1)
                .allowsHitTesting(!isValueFieldFocused)
                .clipped()
            }

            confirmButton
                .frame(maxHeight: isValueFieldFocused ? nil : 0, alignment: .top)
                .opacity(isValueFieldFocused ? 1 : 0)
                .allowsHitTesting(isValueFieldFocused)
                .clipped()
        }
        .animation(.easeInOut(duration: 0.2), value: isValueFieldFocused)
        .onChange(of: isValueFieldFocused) { _, focused in onEditingChange(focused) }
    }

    /// Only closes the keyboard — it does not save anything. `MealBuilderView`'s "Enregistrer ce repas"
    /// stays the one action that writes to the journal; conflating the two would mean a tap meant to
    /// finish typing a weight also ended the whole compose session, which is a far more consequential
    /// mistake than the stuck keyboard this replaces.
    private var confirmButton: some View {
        Button(Strings.active.done) { isValueFieldFocused = false }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(PnRole.buttonPrimaryForeground)
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .background(PnRole.buttonPrimaryBackground)
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
            // Every other custom-styled button in this app carries this — see `shortcutButton`'s own
            // note on why. Without it, inside a `List` row, this button's tap can be swallowed by the
            // row's own `.onTapGesture` (`MealIngredientRow.body`) instead of firing its own action,
            // which is exactly why tapping "Terminé" did nothing.
            .buttonStyle(.plain)
    }

    /// The flex-grow weight field: a large bold number, the unit, and a pencil hinting it is editable —
    /// `docs/SPECIFICATION.md` §7.10's "value field", sized up from a 68-point `TextField` to fill the
    /// room the bigger steppers now leave beside it.
    ///
    /// `.fixedSize()` on the `TextField` sizes it to exactly the digits it holds, e.g. the width of
    /// "150" — not to this whole pill. The "g" label and pencil glyph sitting right next to it visually
    /// read as one control, but a tap landing on either of them, or on the surrounding padding, missed
    /// the `TextField` entirely and did nothing: "difficult to open the keyboard" was a tap landing
    /// half a centimetre from a hit target far narrower than it looked. `.contentShape(Rectangle())` on
    /// the whole pill plus an explicit focus request on tap gives the entire visible control one hit
    /// area; a tap that lands on the digits themselves still focuses the `TextField` directly, so this
    /// only widens the target rather than replacing how it already worked.
    private var valueField: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            TextField(
                "",
                value: Binding(
                    get: { row.quantity },
                    // Typing a weight directly takes the row off the ladder, which is what
                    // portionFactor 0 means. Leaving it at 1 would make applyMethodChange recompute
                    // from the base portion on the next method change and silently discard what was
                    // typed — the case `a zero portion factor does not recompute from the base`.
                    set: { row.quantity = $0; row.portionFactor = 0 }
                ),
                format: .number.precision(.fractionLength(0...1))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .font(.title2.weight(.bold))
            .fixedSize()
            .focused($isValueFieldFocused)

            Text(row.displayUnit == "ml" ? "mL" : "g")
                .font(.title3.weight(.semibold))
                .foregroundStyle(PnColor.inkSoft)

            Image(systemName: "pencil")
                .font(.caption)
                .foregroundStyle(PnColor.inkSoft)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(PnColor.surfaceCream)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PnColor.inkLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { isValueFieldFocused = true }
    }

    /// The quick buttons: equal width now rather than a horizontal scroller, since the corpus caps this
    /// row at four entries and the sandbox's own layout assumes exactly that.
    private var quickButtons: some View {
        HStack(spacing: 8) {
            ForEach(Array(shortcutProfile(
                servingUnits: row.servingUnits,
                displayUnit: row.displayUnit,
                lang: LanguageSettings.shared.effective
            ).enumerated()), id: \.offset) { _, shortcut in
                switch shortcut {
                case .multiplier(let label, let factor):
                    // Active state, not on the increments below: a multiplier sets an absolute
                    // portion, so "is the current weight this portion" is a real, checkable fact.
                    // `docs/SPECIFICATION.md` §7.10's tolerance, `max(2 g, 4 %)` of the yield-aware
                    // target, matches the window `describeQuantity` already snaps an anchor label to
                    // — this button lighting up and the collapsed row's caption naming the same
                    // portion are the same threshold applied twice.
                    shortcutButton(label, active: isFactorActive(factor)) {
                        // A multiplier puts the row back *on* the ladder, so the factor is recorded
                        // as well as the weight. The two must move together: a weight without its
                        // factor is a row applyMethodChange can no longer rescale.
                        row.portionFactor = factor
                        row.quantity = Double(roundHalfUp(row.basePortionG * factor))
                    }
                case .increment(let label, let emoji, let grams):
                    // `active: nil`, not `false` — an increment is a momentary trigger with no state
                    // of its own to show, not a toggle that merely happens to be off right now.
                    shortcutButton([emoji, label].compactMap { $0 }.joined(separator: " "), active: nil) {
                        // An increment *adds* a serving unit's worth rather than replacing the
                        // weight — one more spoonful, not "a spoonful in total" — so it leaves the
                        // ladder, same as typing.
                        row.quantity += Double(grams)
                        row.portionFactor = 0
                    }
                }
            }
        }
    }

    private func shortcutButton(_ label: String, active: Bool?, action: @escaping () -> Void) -> some View {
        let isOn = active == true
        return Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 6)
                .background(isOn ? PnRole.buttonPrimaryBackground : PnColor.surfaceCream)
                .foregroundStyle(isOn ? PnRole.buttonPrimaryForeground : PnColor.inkDefault)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isOn ? Color.clear : PnColor.inkLine, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        // Only a multiplier (`active` non-nil) ever exposes a selected trait — an increment has no
        // pressed state to announce, same reasoning as `active: nil` above.
        .accessibilityAddTraits(active != nil && isOn ? [.isSelected] : [])
    }

    /// Whether the current weight already *is* this multiplier's portion, within
    /// `docs/SPECIFICATION.md` §7.10's tolerance — `max(2 g, 4 %)` of the target, computed through the
    /// yield when the row measures cooked so a grilled row's "1 Part" lights up against the grilled
    /// weight, not the raw one.
    private func isFactorActive(_ factor: Double) -> Bool {
        let target = row.measuredState == "cooked"
            ? row.basePortionG * factor * resolveYieldFactor(row.yieldFactors, method: row.cookingMethod)
            : row.basePortionG * factor
        let tolerance = max(2, target * 0.04)
        return abs(row.quantity - target) <= tolerance
    }

    /// Moves the weight off the ladder, same as typing directly — see the `set:` comment above.
    /// Returns `false` when the step could not apply because a bound was already reached, which
    /// tells `HoldRepeatStepButton` to stop repeating instead of holding at the bound forever.
    @discardableResult
    private func adjust(by delta: Double) -> Bool {
        let next = min(Self.maximumQuantity, max(Self.minimumQuantity, row.quantity + delta))
        guard next != row.quantity else { return false }
        row.quantity = next
        row.portionFactor = 0
        return true
    }
}

/// A +/- button that fires once on press and, if still held, repeats — the same cadence as the
/// sandbox's `useHoldRepeat` hook: an initial 400ms delay, then a step every 75ms, so holding the
/// button scrolls the value instead of forcing many taps. `step` returns `false` at a boundary
/// (the value already hit its floor/ceiling), which stops the repeat early.
///
/// 48×48 points, matching `docs/SPECIFICATION.md` §7.10's stepper size — up from the 28-point circle
/// this button used to be, which is most of why the row was hard to tap precisely.
///
/// Built on a plain gesture rather than `Button` because a real touch-down/up pair is what drives
/// the repeat timer; `Button.action` only fires on release, by which point a hold has already come
/// and gone. VoiceOver still activates it as a button via the added trait, and a quick tap there
/// resolves to a single press-then-release, which fires `step` exactly once.
private struct HoldRepeatStepButton: View {
    let systemName: String
    let label: String
    let disabled: Bool
    let step: () -> Bool

    private static let initialDelay: Duration = .milliseconds(400)
    private static let repeatInterval: Duration = .milliseconds(75)

    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: systemName)
            .font(.title2.weight(.bold))
            .frame(width: 48, height: 48)
            .background(PnColor.surfaceCream)
            .foregroundStyle(disabled ? PnColor.inkSoft.opacity(0.4) : PnColor.inkDefault)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(PnColor.inkLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
            .onLongPressGesture(minimumDuration: 0, maximumDistance: 50, pressing: { isPressing in
                if isPressing {
                    startRepeating()
                } else {
                    stopRepeating()
                }
            }, perform: {})
    }

    private func startRepeating() {
        stopRepeating()
        guard !disabled, step() else { return }
        repeatTask = Task {
            try? await Task.sleep(for: Self.initialDelay)
            while !Task.isCancelled {
                if !step() { break }
                try? await Task.sleep(for: Self.repeatInterval)
            }
        }
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}
