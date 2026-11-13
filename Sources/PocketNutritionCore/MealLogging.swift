// SPDX-License-Identifier: MPL-2.0

import Foundation

// Meal logging helpers: which part of the day a meal belongs to, how a saved dish scales to the portion
// eaten, how a bare calorie figure typed in the search field is read, and which past foods to suggest
// first. Ported from the sandbox reference (`mealLogging.ts`); the `meal-slot`, `meal-slot-default-time`,
// `scale-dish-quantity`, `parse-quick-add-kcal` and `rank-recents` vectors are the contract.

public enum MealSlot: String, Codable, CaseIterable, Sendable {
    case breakfast, lunch, dinner, snack

    /// Display order within a day.
    public var order: Int {
        switch self {
        case .breakfast: 0
        case .lunch: 1
        case .snack: 2
        case .dinner: 3
        }
    }
}

/// The slot a meal falls in, from its local time in minutes since midnight. Half-open bands:
/// breakfast [04:00, 10:30), lunch [10:30, 15:00), dinner [17:30, 22:30), snack otherwise.
public func mealSlot(forMinutes minutes: Double) -> MealSlot {
    let m = ((Int(minutes.rounded(.down)) % 1440) + 1440) % 1440
    if m >= 240 && m < 630 { return .breakfast }
    if m >= 630 && m < 900 { return .lunch }
    if m >= 1050 && m < 1350 { return .dinner }
    return .snack
}

/// The slot of a moment, in the given calendar's time zone.
public func mealSlot(for date: Date, calendar: Calendar = .current) -> MealSlot {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return mealSlot(forMinutes: Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)))
}

/// The time (minutes since midnight) given to a meal filed under [slot] when it is not logged now.
public func defaultMinutes(for slot: MealSlot) -> Int {
    switch slot {
    case .breakfast: 480
    case .lunch: 750
    case .dinner: 1170
    case .snack: 960
    }
}

/// That default time on the given day.
public func defaultDate(for slot: MealSlot, on day: Date, calendar: Calendar = .current) -> Date {
    let start = calendar.startOfDay(for: day)
    return calendar.date(byAdding: .minute, value: defaultMinutes(for: slot), to: start) ?? start
}

/// Grams of one ingredient of a dish saved for [servings] portions when [parts] portions are eaten,
/// rounded half-up to one decimal. `servings <= 0` counts as one portion.
public func scaleDishQuantity(_ quantityG: Double, servings: Double, parts: Double) -> Double {
    let portions = servings > 0 ? servings : 1
    return Double(roundHalfUp(quantityG * parts / portions * 10)) / 10
}

/// A calorie figure typed in the search field for quick add: a whole number 1-5000, optionally followed
/// by "kcal" (any case, optional space). Anything else returns nil.
public func parseQuickAddKcal(_ query: String) -> Int? {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    var digits = Substring(trimmed)
    if digits.lowercased().hasSuffix("kcal") {
        digits = digits.dropLast(4)
        digits = Substring(digits.trimmingCharacters(in: .whitespaces))
    }
    guard (1...4).contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isNumber }),
          let kcal = Int(digits), (1...5000).contains(kcal)
    else { return nil }
    return kcal
}

/// One past use of a food, for ranking suggestions. `at` is in seconds since the epoch.
public struct LoggedUse: Equatable, Sendable {
    public let key: String
    public let slot: MealSlot
    public let at: Double

    public init(key: String, slot: MealSlot, at: Double) {
        self.key = key
        self.slot = slot
        self.at = at
    }
}

/// Distinct keys to suggest, best first, at most [limit]: most uses in [slot], then most uses overall,
/// then most recent use, then key ascending.
public func rankRecents(_ uses: [LoggedUse], slot: MealSlot, limit: Int) -> [String] {
    struct Stats { var inSlot = 0; var total = 0; var last = 0.0 }
    var stats: [String: Stats] = [:]
    for use in uses {
        var s = stats[use.key] ?? Stats()
        s.total += 1
        if use.slot == slot { s.inSlot += 1 }
        if use.at > s.last { s.last = use.at }
        stats[use.key] = s
    }
    let ranked = stats.sorted { a, b in
        if a.value.inSlot != b.value.inSlot { return a.value.inSlot > b.value.inSlot }
        if a.value.total != b.value.total { return a.value.total > b.value.total }
        if a.value.last != b.value.last { return a.value.last > b.value.last }
        return a.key < b.key
    }
    return ranked.prefix(max(0, limit)).map(\.key)
}
