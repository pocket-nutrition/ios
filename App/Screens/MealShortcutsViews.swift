// SPDX-License-Identifier: MPL-2.0

import SwiftUI
import PocketNutritionCore

/// Names a meal and saves it as a dish. The name is suggested from the main ingredients; "makes N
/// portions" is what lets a batch (a gratin for 4) be applied a quarter at a time later.
struct SaveDishSheet: View {
    let items: [MealItem]
    let onSave: (_ name: String, _ servings: Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var servings = 1

    init(items: [MealItem], onSave: @escaping (String, Int) -> Void) {
        self.items = items
        self.onSave = onSave
        _name = State(initialValue: items.filter { !$0.isQuickAdd }.prefix(3).map(\.label).joined(separator: ", "))
    }

    var body: some View {
        let t = Strings.active
        NavigationStack {
            Form {
                TextField(t.dishNameField, text: $name)
                    .textInputAutocapitalization(.sentences)
                Stepper(t.dishServings(servings), value: $servings, in: 1...12)
                Section {
                    Text(items.filter { !$0.isQuickAdd }.map(\.label).joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(PnColor.inkSoft)
                }
            }
            .navigationTitle(t.saveAsDish)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t.searchCancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t.dishSave) {
                        onSave(name, servings)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// One line of the empty-search suggestions: a dish or a past food, with a one-tap add.
struct ShortcutRow: View {
    let title: String
    let detail: String
    let isPinned: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if isPinned {
                Image(systemName: "star.fill").font(.caption).foregroundStyle(PnColor.brandLeaf)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundStyle(PnColor.inkDefault).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(PnColor.inkSoft).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(PnColor.brandLeafDeep)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Strings.active.shortcutAddA11y(title))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onAdd)
    }
}

/// A quick-add row in the meal: an energy figure typed by the person, with no ingredient behind it.
struct QuickAddMealRow: View {
    let kcal: Double

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill").font(.caption).foregroundStyle(PnColor.inkSoft)
            Text("\(roundHalfUp(kcal)) kcal").font(.subheadline.weight(.medium)).foregroundStyle(PnColor.inkDefault)
            Spacer()
            Text(Strings.active.quickAddNote).font(.caption).foregroundStyle(PnColor.inkSoft)
        }
        .padding(.vertical, 6)
    }
}

/// The head of a dish applied to the meal: its name, energy, and a portion stepper that rescales every
/// ingredient of the dish at once. Tapping it shows or hides the ingredients, which stay editable.
struct DishGroupHeader: View {
    let name: String
    let summary: String
    let kcal: Double?
    let servings: Int
    let parts: Double
    let isExpanded: Bool
    let onToggle: () -> Void
    let onParts: (Double) -> Void

    static let steps: [Double] = [0.5, 1, 1.5, 2]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PnColor.inkSoft)
                    Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(PnColor.inkDefault)
                    Spacer()
                    if let kcal { Text("\(roundHalfUp(kcal)) kcal").font(.subheadline).foregroundStyle(PnColor.brandLeafDeep) }
                }
            }
            .buttonStyle(.borderless)
            HStack(spacing: 6) {
                ForEach(Self.steps, id: \.self) { step in
                    Button {
                        onParts(step)
                    } label: {
                        Text(Self.label(step))
                            .font(.footnote.weight(step == parts ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(step == parts ? PnColor.brandLeaf.opacity(0.18) : PnColor.surfacePaper)
                            .clipShape(Capsule())
                            .foregroundStyle(step == parts ? PnColor.brandLeafDeep : PnColor.inkDefault)
                    }
                    .buttonStyle(.borderless)
                }
                Text(Strings.active.dishPartsUnit(servings: servings, parts: parts))
                    .font(.caption)
                    .foregroundStyle(PnColor.inkSoft)
            }
            if !isExpanded {
                Text(summary).font(.caption).foregroundStyle(PnColor.inkSoft).lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    static func label(_ step: Double) -> String {
        switch step {
        case 0.5: "½"
        case 1.5: "1½"
        default: String(Int(step))
        }
    }
}
