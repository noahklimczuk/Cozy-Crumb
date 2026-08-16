//
//  KitchenTimerTests.swift
//  Cozy CrumbTests
//
//  A timer is an end date, not a counter, so all of the arithmetic that
//  matters can be tested against a fixed clock rather than by waiting.
//

import Foundation
import Testing

@testable import Cozy_Crumb

@Suite("Kitchen timers")
struct KitchenTimerTests {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func running(seconds: Int) -> KitchenTimer {
        KitchenTimer(
            label: "Step 2",
            recipeTitle: "Banana Bread",
            totalSeconds: seconds,
            endDate: start.addingTimeInterval(TimeInterval(seconds))
        )
    }

    @Test("A running timer counts down against the clock")
    func countdown() {
        let timer = running(seconds: 600)

        #expect(timer.remaining(at: start) == 600)
        #expect(timer.remaining(at: start.addingTimeInterval(90)) == 510)
        #expect(timer.isRunning)
        #expect(!timer.hasFinished(at: start))
    }

    @Test("Time past the end stops at zero rather than going negative")
    func doesNotOverrun() {
        let timer = running(seconds: 60)
        let wellPast = start.addingTimeInterval(6_000)

        #expect(timer.remaining(at: wellPast) == 0)
        #expect(timer.hasFinished(at: wellPast))
        #expect(timer.display(at: wellPast) == "0:00")
    }

    @Test("A paused timer holds its remaining time whatever the clock does")
    func paused() {
        let timer = KitchenTimer(
            label: "Step 4",
            recipeTitle: "Chickpea Curry",
            totalSeconds: 600,
            endDate: nil,
            pausedRemaining: 245
        )

        #expect(timer.isPaused)
        #expect(!timer.isRunning)
        #expect(timer.remaining(at: start) == 245)
        #expect(timer.remaining(at: start.addingTimeInterval(10_000)) == 245)
    }

    @Test("Countdowns read as a clock, with hours only when there are hours")
    func clockFormatting() {
        #expect(KitchenTimer.clock(0) == "0:00")
        #expect(KitchenTimer.clock(9) == "0:09")
        #expect(KitchenTimer.clock(65) == "1:05")
        #expect(KitchenTimer.clock(600) == "10:00")
        #expect(KitchenTimer.clock(3_600) == "1:00:00")
        #expect(KitchenTimer.clock(5_425) == "1:30:25")
        // Negative time is a bug elsewhere, not something to render.
        #expect(KitchenTimer.clock(-30) == "0:00")
    }

    @Test("Progress runs from nothing to full across the timer's life")
    func progress() {
        let timer = running(seconds: 100)

        #expect(abs(timer.progress(at: start) - 0) < 0.0001)
        #expect(abs(timer.progress(at: start.addingTimeInterval(25)) - 0.25) < 0.0001)
        #expect(abs(timer.progress(at: start.addingTimeInterval(100)) - 1) < 0.0001)
        #expect(abs(timer.progress(at: start.addingTimeInterval(500)) - 1) < 0.0001)
    }

    @Test("A timer with no duration reads as finished rather than dividing by zero")
    func zeroLength() {
        let timer = KitchenTimer(label: "Step 1", recipeTitle: "Toast", totalSeconds: 0)

        #expect(timer.remaining(at: start) == 0)
        #expect(timer.progress(at: start) == 1)
    }
}

@Suite("The timer stack")
@MainActor
struct KitchenTimersTests {

    private func makeTimers() -> KitchenTimers {
        KitchenTimers(usesNotifications: false)
    }

    @Test("Starting a timer puts it on the stack")
    func starting() {
        let timers = makeTimers()

        let id = timers.start(seconds: 300, label: "Step 1", recipeTitle: "Banana Bread")

        #expect(id != nil)
        #expect(timers.hasTimers)
        #expect(timers.timers.count == 1)
        #expect(timers.timers.first?.totalSeconds == 300)
    }

    @Test("A duration that isn't one starts nothing")
    func rejectsEmptyDuration() {
        let timers = makeTimers()

        #expect(timers.start(seconds: 0, label: "Step 1", recipeTitle: "Toast") == nil)
        #expect(timers.start(seconds: -60, label: "Step 1", recipeTitle: "Toast") == nil)
        #expect(!timers.hasTimers)
    }

    @Test("Timers stack — a roast and a pan of rice are a normal Sunday")
    func stacks() {
        let timers = makeTimers()

        timers.start(seconds: 3_600, label: "Step 1", recipeTitle: "Roast")
        timers.start(seconds: 600, label: "Step 2", recipeTitle: "Rice")

        #expect(timers.timers.count == 2)
        // Soonest first, so the one needing attention is on top.
        #expect(timers.sortedTimers.first?.recipeTitle == "Rice")
    }

    @Test("Restarting a step's timer replaces it instead of doubling it up")
    func oneTimerPerStep() {
        let timers = makeTimers()
        let stepID = UUID()

        timers.start(seconds: 600, label: "Step 3", recipeTitle: "Curry", stepID: stepID)
        timers.start(seconds: 900, label: "Step 3", recipeTitle: "Curry", stepID: stepID)

        #expect(timers.timers.count == 1)
        #expect(timers.timer(forStep: stepID)?.totalSeconds == 900)
    }

    @Test("Pausing holds the time, resuming sets a fresh end date")
    func pauseAndResume() throws {
        let timers = makeTimers()

        let id = try #require(timers.start(seconds: 600, label: "Step 2", recipeTitle: "Bread"))

        timers.pause(id)
        let paused = try #require(timers.timers.first)
        #expect(paused.isPaused)
        #expect(paused.endDate == nil)
        #expect(paused.remaining(at: .now) > 0)

        timers.resume(id)
        let resumed = try #require(timers.timers.first)
        #expect(resumed.isRunning)
        #expect(resumed.pausedRemaining == nil)
    }

    @Test("Another minute extends a running timer and revives a finished one")
    func addsMinutes() throws {
        let timers = makeTimers()

        let id = try #require(timers.start(seconds: 60, label: "Step 2", recipeTitle: "Eggs"))
        timers.addMinutes(1, to: id)

        let extended = try #require(timers.timers.first)
        #expect(extended.totalSeconds == 120)
        #expect(extended.remaining(at: .now) > 60)
    }

    @Test("Cancelling clears one, and clearing all clears the lot")
    func cancelling() throws {
        let timers = makeTimers()

        let first = try #require(timers.start(seconds: 300, label: "Step 1", recipeTitle: "Rice"))
        timers.start(seconds: 600, label: "Step 2", recipeTitle: "Rice")

        timers.cancel(first)
        #expect(timers.timers.count == 1)

        timers.cancelAll()
        #expect(!timers.hasTimers)
    }
}
