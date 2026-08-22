//
//  SignalRetention.swift
//  Cozy Crumb
//
//  Keeps the signal log from growing without end.
//
//  Opening recipes writes a row every time. A cook who uses the app daily for
//  two years produces tens of thousands of them, and profile derivation walks
//  the lot. That is worth heading off, but only for the rows that have
//  genuinely stopped meaning anything.
//
//  Which rows those are falls out of the decay curve rather than being picked
//  by taste. At the 180-day half-life a `viewed` is worth 0.05 and a
//  `searched` the same — less than the rounding on everything around them. A
//  `cooked` at the same age is still worth a full point, so it stays. The
//  pruner therefore only ever touches incidental signals, and only once they
//  are past the half-life.
//
//  Deleting is deliberately conservative in the other direction too: nothing
//  here removes a negative signal. A dislike that fades on its own is how you
//  end up recommending coriander again.
//

import Foundation
import SwiftData
import os

@MainActor
enum SignalRetention {

    /// Incidental signals older than this are dropped. Matches the decay
    /// half-life on purpose — past it they are worth less than 0.05.
    static let incidentalRetentionDays: Double = 180

    /// A ceiling for the pathological case: an enormous library browsed hard.
    /// Only incidental rows count against it and only they are dropped for
    /// it, oldest first.
    static let incidentalCeiling = 5_000

    /// Runs at most once a day. The work is cheap but it is not free, and
    /// nothing about it needs to happen twice in one session.
    static let minimumInterval: TimeInterval = 24 * 60 * 60

    /// Prunes if it is due. Returns how many rows were removed.
    @discardableResult
    static func runIfDue(
        in modelContext: ModelContext,
        defaults: UserDefaults = .standard,
        now: Date = .now
    ) -> Int {
        let last = defaults.object(forKey: CozyDefaultsKey.lastSignalPruneAt) as? Date

        if let last, now.timeIntervalSince(last) < minimumInterval {
            return 0
        }

        let removed = prune(in: modelContext, now: now)
        defaults.set(now, forKey: CozyDefaultsKey.lastSignalPruneAt)

        if removed > 0 {
            Log.data.info("Pruned \(removed, privacy: .public) spent taste signals")
        }

        return removed
    }

    /// The prune itself, with no once-a-day guard. Separate so tests can call
    /// it directly.
    @discardableResult
    static func prune(in modelContext: ModelContext, now: Date = .now) -> Int {
        let all: [TasteSignal]
        do {
            all = try modelContext.fetch(FetchDescriptor<TasteSignal>())
        } catch {
            Log.data.error("Could not read signals to prune: \(error.localizedDescription, privacy: .public)")
            return 0
        }

        let incidental = all
            .filter(\.kind.isIncidental)
            .sorted { $0.timestamp < $1.timestamp }

        let cutoff = now.addingTimeInterval(-incidentalRetentionDays * 86_400)

        var doomed = incidental.filter { $0.timestamp < cutoff }

        // Anything still over the ceiling after the age pass goes too, oldest
        // first, so the ceiling can never be exceeded by recent browsing.
        let surviving = incidental.count - doomed.count
        if surviving > incidentalCeiling {
            let excess = surviving - incidentalCeiling
            let remaining = incidental.filter { $0.timestamp >= cutoff }
            doomed.append(contentsOf: remaining.prefix(excess))
        }

        guard !doomed.isEmpty else { return 0 }

        for signal in doomed {
            modelContext.delete(signal)
        }

        do {
            try modelContext.save()
        } catch {
            Log.data.error("Could not save after pruning: \(error.localizedDescription, privacy: .public)")
            return 0
        }

        return doomed.count
    }
}
