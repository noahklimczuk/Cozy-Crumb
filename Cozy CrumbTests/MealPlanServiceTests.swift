//
//  MealPlanServiceTests.swift
//  Cozy CrumbTests
//
//  Week arithmetic only. These avoid asserting *which* day a week starts on —
//  that's the user's calendar's business, and hard-coding Monday would fail in
//  half the world.
//

import Foundation
import Testing

@testable import Cozy_Crumb

@Suite("Meal plan weeks")
@MainActor
struct MealPlanServiceTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }

    @Test("A week is seven consecutive days")
    func sevenDays() {
        let days = MealPlanService.days(ofWeekContaining: date(2026, 8, 12), calendar: calendar)

        #expect(days.count == 7)

        for (earlier, later) in zip(days, days.dropFirst()) {
            let gap = calendar.dateComponents([.day], from: earlier, to: later).day
            #expect(gap == 1)
        }
    }

    @Test("Every day of a week resolves to the same start")
    func stableStart() {
        let anchor = date(2026, 8, 12)
        let start = MealPlanService.startOfWeek(containing: anchor, calendar: calendar)

        for day in MealPlanService.days(ofWeekContaining: anchor, calendar: calendar) {
            #expect(MealPlanService.startOfWeek(containing: day, calendar: calendar) == start)
        }
    }

    @Test("Stepping a week forward and back lands where it started")
    func roundTrip() {
        let anchor = date(2026, 8, 12)
        let forward = MealPlanService.week(offsetBy: 1, from: anchor, calendar: calendar)
        let back = MealPlanService.week(offsetBy: -1, from: forward, calendar: calendar)

        #expect(back == anchor)
    }

    @Test("Stepping a week moves exactly seven days")
    func weekStride() {
        let anchor = date(2026, 8, 12)
        let next = MealPlanService.week(offsetBy: 1, from: anchor, calendar: calendar)

        #expect(calendar.dateComponents([.day], from: anchor, to: next).day == 7)
    }

    @Test("A week label names both ends")
    func label() {
        let label = MealPlanService.weekLabel(for: date(2026, 8, 12), calendar: calendar)

        #expect(label.contains("–"))
        #expect(!label.isEmpty)
    }
}
