// SPDX-License-Identifier: MPL-2.0

import Foundation

// The journal shows saved meals and the captures (dictations, meal photos) that are not meals yet, side by
// side in the day they belong to. A capture is removed once its result has been made into a meal, so
// every entry still stored is a meal in progress. Pure and generic over the meal type (which lives in the
// app target) so Linux CI covers the ordering.

public enum JournalTimelineItem<Meal> {
    case meal(Meal)
    case capture(RecognitionEntry)
}

public struct JournalTimelineDay<Meal> {
    public let day: Date
    /// Newest first, meals and captures interleaved by time.
    public let items: [JournalTimelineItem<Meal>]

    public init(day: Date, items: [JournalTimelineItem<Meal>]) {
        self.day = day
        self.items = items
    }
}

/// One part of a day in the journal: its slot and what was eaten then, oldest first.
public struct JournalSlotGroup<Meal> {
    public let slot: MealSlot
    public let items: [JournalTimelineItem<Meal>]
}

/// A day's entries grouped by slot, in day order (breakfast, lunch, snack, dinner), each oldest first.
/// A capture's slot is the one of the moment it was taken. With `includeEmptyMainSlots` (today), a main
/// meal with nothing logged yet still gets its group, empty, so the journal can offer to fill it; snacks
/// never do, since a day without one is not missing anything.
public func groupBySlot<Meal>(
    _ day: JournalTimelineDay<Meal>, slotOf: (Meal) -> MealSlot, dateOf: (Meal) -> Date,
    includeEmptyMainSlots: Bool, calendar: Calendar = .current
) -> [JournalSlotGroup<Meal>] {
    func slot(_ item: JournalTimelineItem<Meal>) -> MealSlot {
        switch item {
        case .meal(let meal): slotOf(meal)
        case .capture(let entry): mealSlot(for: Date(timeIntervalSince1970: entry.createdAt), calendar: calendar)
        }
    }
    func date(_ item: JournalTimelineItem<Meal>) -> Date {
        switch item {
        case .meal(let meal): dateOf(meal)
        case .capture(let entry): Date(timeIntervalSince1970: entry.createdAt)
        }
    }
    let bySlot = Dictionary(grouping: day.items, by: slot)
    return MealSlot.allCases.sorted { $0.order < $1.order }.compactMap { candidate in
        let items = (bySlot[candidate] ?? []).sorted { date($0) < date($1) }
        if items.isEmpty && !(includeEmptyMainSlots && candidate != .snack) { return nil }
        return JournalSlotGroup(slot: candidate, items: items)
    }
}

/// Days newest first; within a day, meals and captures by time, newest first. A capture is dated when it
/// was recorded or photographed, which is also when its meal will be dated once saved.
public func journalTimeline<Meal>(
    meals: [Meal], dateOf: (Meal) -> Date, captures: [RecognitionEntry], calendar: Calendar = .current
) -> [JournalTimelineDay<Meal>] {
    let dated: [(date: Date, item: JournalTimelineItem<Meal>)] =
        meals.map { (dateOf($0), .meal($0)) }
        + captures.map { (Date(timeIntervalSince1970: $0.createdAt), .capture($0)) }
    let byDay = Dictionary(grouping: dated) { calendar.startOfDay(for: $0.date) }
    return byDay
        .map { day, entries in
            JournalTimelineDay(day: day, items: entries.sorted { $0.date > $1.date }.map(\.item))
        }
        .sorted { $0.day > $1.day }
}
