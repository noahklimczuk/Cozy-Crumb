//
//  KitchenTimers.swift
//  Cozy Crumb
//
//  The stacked kitchen timers Cook Mode is built on (Phase 6), and the thing
//  the duration chips in Recipe Detail have been waiting for.
//
//  Two decisions worth knowing about:
//
//  1. A timer is an *end date*, not a counter that ticks down. The ticker
//     below only nudges `now` so the screen redraws; every countdown is
//     recomputed from the clock. That means backgrounding the app, locking the
//     phone, or a ticker that misses a beat can't make a timer drift — which
//     matters, because the whole point is that dinner isn't overcooked.
//
//  2. Alerting is doubled up on purpose. A local notification fires whether or
//     not the app is on screen, and an in-app haptic plus the chip turning
//     "Time's up!" covers the case where the user is looking right at it with
//     notifications denied. Neither one alone is enough for someone standing
//     at a hob.
//
//  Timers are app-wide rather than owned by Cook Mode: walking out of Cook
//  Mode to check the shopping list should not cancel the rice.
//

import Foundation
import SwiftUI
import UserNotifications
import os

// MARK: - One timer

nonisolated struct KitchenTimer: Identifiable, Sendable, Equatable {
    let id: UUID
    /// What's cooking. Shown on the chip and in the notification.
    var label: String
    var recipeTitle: String
    /// The step this was started from, so that step can show its own
    /// countdown rather than a generic "a timer is running".
    var stepID: UUID?
    var totalSeconds: Int
    /// Set while running.
    var endDate: Date?
    /// Set while paused, and nil while running — exactly one of the two.
    var pausedRemaining: Int?

    nonisolated init(
        id: UUID = UUID(),
        label: String,
        recipeTitle: String,
        stepID: UUID? = nil,
        totalSeconds: Int,
        endDate: Date? = nil,
        pausedRemaining: Int? = nil
    ) {
        self.id = id
        self.label = label
        self.recipeTitle = recipeTitle
        self.stepID = stepID
        self.totalSeconds = totalSeconds
        self.endDate = endDate
        self.pausedRemaining = pausedRemaining
    }

    nonisolated var isRunning: Bool { endDate != nil }
    nonisolated var isPaused: Bool { pausedRemaining != nil }

    /// Seconds left, never below zero: a finished timer sits at 0:00 until
    /// it's dismissed rather than counting off into the negative.
    nonisolated func remaining(at date: Date) -> Int {
        if let pausedRemaining { return max(0, pausedRemaining) }
        guard let endDate else { return 0 }
        return max(0, Int(endDate.timeIntervalSince(date).rounded(.up)))
    }

    nonisolated func hasFinished(at date: Date) -> Bool {
        remaining(at: date) == 0
    }

    /// 0 to 1, for the ring around the chip.
    nonisolated func progress(at date: Date) -> Double {
        guard totalSeconds > 0 else { return 1 }
        return 1 - (Double(remaining(at: date)) / Double(totalSeconds))
    }

    nonisolated func display(at date: Date) -> String {
        Self.clock(remaining(at: date))
    }

    /// "12:05", "1:00:00" — a clock, because that's what a kitchen timer is.
    nonisolated static func clock(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - The stack

@Observable
@MainActor
final class KitchenTimers {

    private(set) var timers: [KitchenTimer] = []

    /// Nudged by the ticker so countdowns redraw. Views read the clock from
    /// here rather than calling `Date.now` themselves, so every chip on screen
    /// agrees about what time it is.
    private(set) var now: Date = .now

    /// Timers that have rung already, so a finished one doesn't buzz twice a
    /// second until it's dismissed.
    private var rung: Set<UUID> = []

    private var ticker: Task<Void, Never>?
    private var hasAskedForNotifications = false
    private let usesNotifications: Bool

    /// Previews and tests pass `usesNotifications: false` — nothing there
    /// should be asking for permission or leaving requests behind.
    init(usesNotifications: Bool = true) {
        self.usesNotifications = usesNotifications
    }

    // MARK: - Reading

    var hasTimers: Bool { !timers.isEmpty }

    /// Soonest to finish first, so the one that needs attention is on top.
    var sortedTimers: [KitchenTimer] {
        timers.sorted { $0.remaining(at: now) < $1.remaining(at: now) }
    }

    var finishedCount: Int {
        timers.filter { $0.hasFinished(at: now) }.count
    }

    func timer(forStep stepID: UUID) -> KitchenTimer? {
        timers.first { $0.stepID == stepID }
    }

    // MARK: - Starting and stopping

    /// Starts a countdown. Returns nil for a duration that isn't a duration.
    @discardableResult
    func start(
        seconds: Int,
        label: String,
        recipeTitle: String,
        stepID: UUID? = nil
    ) -> UUID? {
        guard seconds > 0 else { return nil }

        // One timer per step: tapping a step's chip again restarts it rather
        // than leaving two countdowns for the same pan.
        if let stepID, let existing = timer(forStep: stepID) {
            cancel(existing.id)
        }

        let timer = KitchenTimer(
            label: label,
            recipeTitle: recipeTitle,
            stepID: stepID,
            totalSeconds: seconds,
            endDate: Date.now.addingTimeInterval(TimeInterval(seconds))
        )

        timers.append(timer)
        schedule(timer)
        startTicking()
        Haptics.impact(.medium)

        return timer.id
    }

    func pause(_ id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }),
              timers[index].isRunning else { return }

        timers[index].pausedRemaining = timers[index].remaining(at: .now)
        timers[index].endDate = nil
        cancelNotification(for: id)
        Haptics.soft()
    }

    func resume(_ id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }),
              let remaining = timers[index].pausedRemaining, remaining > 0 else { return }

        timers[index].endDate = Date.now.addingTimeInterval(TimeInterval(remaining))
        timers[index].pausedRemaining = nil
        rung.remove(id)
        schedule(timers[index])
        startTicking()
        Haptics.soft()
    }

    /// "Another minute" — the most-used button on any kitchen timer.
    func addMinutes(_ minutes: Int, to id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }

        let extra = TimeInterval(minutes * 60)
        timers[index].totalSeconds += minutes * 60

        if let pausedRemaining = timers[index].pausedRemaining {
            timers[index].pausedRemaining = pausedRemaining + minutes * 60
        } else {
            // A finished timer restarts from now rather than from an end date
            // that's already in the past.
            let base = max(timers[index].endDate ?? .now, .now)
            timers[index].endDate = base.addingTimeInterval(extra)
            cancelNotification(for: id)
            schedule(timers[index])
        }

        rung.remove(id)
        startTicking()
        Haptics.soft()
    }

    func cancel(_ id: UUID) {
        timers.removeAll { $0.id == id }
        rung.remove(id)
        cancelNotification(for: id)
        stopTickingIfIdle()
    }

    func cancelAll() {
        for timer in timers {
            cancelNotification(for: timer.id)
        }
        timers.removeAll()
        rung.removeAll()
        stopTickingIfIdle()
    }

    // MARK: - Ticking

    private func startTicking() {
        guard ticker == nil else { return }

        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func stopTickingIfIdle() {
        guard timers.isEmpty else { return }
        ticker?.cancel()
        ticker = nil
    }

    private func tick() {
        now = .now

        for timer in timers where timer.hasFinished(at: now) && !rung.contains(timer.id) {
            rung.insert(timer.id)
            // The notification covers a backgrounded app; this covers a user
            // holding the phone and watching it.
            Haptics.notify(.success)
        }
    }

    // MARK: - Notifications

    /// Best effort, always. A denied permission costs the alert, not the
    /// timer — the countdown on screen carries on either way.
    private func schedule(_ timer: KitchenTimer) {
        guard usesNotifications, let endDate = timer.endDate else { return }

        let interval = endDate.timeIntervalSinceNow
        guard interval > 1 else { return }

        let label = timer.label
        let recipeTitle = timer.recipeTitle
        let identifier = timer.id.uuidString

        Task {
            await requestNotificationPermissionIfNeeded()

            let content = UNMutableNotificationContent()
            content.title = "Time's up!"
            content.body = "\(label) — \(recipeTitle)"
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            )

            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                Log.app.info("Could not schedule a timer notification")
            }
        }
    }

    private func cancelNotification(for id: UUID) {
        guard usesNotifications else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    /// Asked the first time a timer is started rather than at launch, so the
    /// prompt arrives attached to something the user just chose to do.
    private func requestNotificationPermissionIfNeeded() async {
        guard !hasAskedForNotifications else { return }
        hasAskedForNotifications = true

        do {
            _ = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.app.info("Notification permission unavailable")
        }
    }
}
