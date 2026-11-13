// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

import PocketNutritionCore

@Suite("journal timeline")
struct JournalTimelineTests {

    private struct Meal: Equatable { let name: String; let at: Date }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2026-11-02 at the given UTC hour.
    private func nov2(_ hour: Double) -> Date { Date(timeIntervalSince1970: 1_793_577_600 + hour * 3600) }

    private func labels(_ day: JournalTimelineDay<Meal>) -> [String] {
        day.items.map {
            switch $0 {
            case .meal(let meal): meal.name
            case .capture(let entry): "capture:" + entry.localId
            }
        }
    }

    @Test("captures sit in their day, between meals, newest first")
    func interleaved() {
        let meals = [Meal(name: "lunch", at: nov2(12)), Meal(name: "dinner", at: nov2(20))]
        let photo = RecognitionEntry(localId: "p", createdAt: nov2(16).timeIntervalSince1970, audioFile: "p.jpg")
        let days = journalTimeline(meals: meals, dateOf: \.at, captures: [photo], calendar: utc)
        #expect(days.count == 1)
        #expect(labels(days[0]) == ["dinner", "capture:p", "lunch"])
    }

    @Test("a day with only a capture still gets its own section, days newest first")
    func captureOnlyDay() {
        let meals = [Meal(name: "yesterday", at: nov2(-12))]
        let voice = RecognitionEntry(localId: "v", createdAt: nov2(9).timeIntervalSince1970, audioFile: "v.m4a")
        let days = journalTimeline(meals: meals, dateOf: \.at, captures: [voice], calendar: utc)
        #expect(days.map(labels) == [["capture:v"], ["yesterday"]])
        #expect(days[0].day > days[1].day)
    }

    @Test("nothing in, nothing out")
    func empty() {
        #expect(journalTimeline(meals: [Meal](), dateOf: \.at, captures: [], calendar: utc).isEmpty)
    }
}

@Suite("journal slot groups")
struct JournalSlotGroupTests {

    private struct Meal { let name: String; let at: Date; let slot: MealSlot }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func nov2(_ hour: Double) -> Date { Date(timeIntervalSince1970: 1_793_577_600 + hour * 3600) }

    private func names(_ groups: [JournalSlotGroup<Meal>]) -> [String] {
        groups.map { group in
            group.slot.rawValue + ":" + group.items.map {
                switch $0 {
                case .meal(let meal): meal.name
                case .capture(let entry): "capture-" + entry.localId
                }
            }.joined(separator: ",")
        }
    }

    @Test("groups in day order, oldest first inside a slot; captures take their moment's slot")
    func ordering() {
        let meals = [
            Meal(name: "dinner", at: nov2(20), slot: .dinner),
            Meal(name: "coffee", at: nov2(8), slot: .breakfast),
            Meal(name: "toast", at: nov2(7.5), slot: .breakfast),
        ]
        let photo = RecognitionEntry(localId: "p", createdAt: nov2(12.5).timeIntervalSince1970, audioFile: "p.jpg")
        let day = journalTimeline(meals: meals, dateOf: \.at, captures: [photo], calendar: utc)[0]
        let groups = groupBySlot(day, slotOf: \.slot, dateOf: \.at, includeEmptyMainSlots: false, calendar: utc)
        #expect(names(groups) == ["breakfast:toast,coffee", "lunch:capture-p", "dinner:dinner"])
    }

    @Test("today shows empty main meals but never an empty snack")
    func emptyMainSlots() {
        let day = JournalTimelineDay<Meal>(day: nov2(0), items: [.meal(Meal(name: "apple", at: nov2(16), slot: .snack))])
        let groups = groupBySlot(day, slotOf: \.slot, dateOf: \.at, includeEmptyMainSlots: true, calendar: utc)
        #expect(names(groups) == ["breakfast:", "lunch:", "snack:apple", "dinner:"])
        let past = groupBySlot(day, slotOf: \.slot, dateOf: \.at, includeEmptyMainSlots: false, calendar: utc)
        #expect(names(past) == ["snack:apple"])
    }

    @Test("an explicit slot wins over the meal's time")
    func explicitSlot() {
        let day = JournalTimelineDay<Meal>(day: nov2(0), items: [.meal(Meal(name: "late lunch", at: nov2(15.5), slot: .lunch))])
        let groups = groupBySlot(day, slotOf: \.slot, dateOf: \.at, includeEmptyMainSlots: false, calendar: utc)
        #expect(names(groups) == ["lunch:late lunch"])
    }
}
