//
//  PantryDecay.swift
//  Cozy Crumb
//
//  The pass that puts lapsed rows away, and the one place the rest of the app
//  asks for "what's actually in".
//
//  Two rules govern everything here, and they pull against each other on
//  purpose:
//
//    - The pantry must not keep claiming things it has no reason to believe
//      in. A row nobody has confirmed in three months is not inventory, it is
//      a rumour, and leaving it in the active list is how the recommendations
//      it feeds start being wrong.
//
//    - Nothing is ever deleted. Users find silent disappearance unnerving, and
//      a row that vanishes takes its history with it — which is the exact data
//      restock prediction and waste insight are built on.
//
//  So: archived, not removed. An archived row keeps its id, its history and
//  its evidence, is excluded from every active query, and comes back with one
//  tap and no loss.
//

import Foundation
import SwiftData
import os

@MainActor
enum PantryDecay {

    // MARK: - Reading

    /// Everything on the shelf: not archived, newest confirmation first.
    ///
    /// The single place "what's in the pantry" is answered, so no caller can
    /// forget to filter the archive out. Forgetting would not throw — it would
    /// quietly hand the Sous Chef food that decayed away months ago.
    static func activeItems(in context: ModelContext) -> [PantryItem] {
        let descriptor = FetchDescriptor<PantryItem>(
            predicate: #Predicate { $0.archivedAt == nil }
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            Log.data.error(
                "Pantry fetch failed: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    /// Rows that have been put away, newest first. For the "probably gone"
    /// list, where they can be restored.
    static func archivedItems(in context: ModelContext) -> [PantryItem] {
        let descriptor = FetchDescriptor<PantryItem>(
            predicate: #Predicate { $0.archivedAt != nil },
            sortBy: [SortDescriptor(\.archivedAt, order: .reverse)]
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            Log.data.error(
                "Pantry archive fetch failed: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    /// The rows the reconciliation sweep should ask about: doubtful, still on
    /// the shelf, least-sure first, capped so a sweep always ends quickly.
    static func needingReconciliation(
        in context: ModelContext,
        now: Date = .now,
        limit: Int = 12
    ) -> [PantryItem] {
        activeItems(in: context)
            .filter { $0.band(at: now) == .doubtful }
            .sorted { $0.confidence(at: now) < $1.confidence(at: now) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Archiving

    /// Puts away everything that has decayed out of the active bands.
    ///
    /// Runs on launch, next to the other backfills. Cheap in steady state: one
    /// fetch, and a kitchen where nothing has lapsed writes nothing.
    @discardableResult
    static func archiveLapsed(in context: ModelContext, now: Date = .now) -> Int {
        let items = activeItems(in: context)
        var archived = 0

        for item in items where item.band(at: now) == .lapsed {
            archive(item, at: now, logging: .expired, in: context)
            archived += 1
        }

        guard archived > 0 else { return 0 }

        do {
            try context.save()
            Log.data.info("Pantry archived \(archived, privacy: .public) lapsed rows")
        } catch {
            Log.data.error(
                "Pantry archive could not save: \(error.localizedDescription, privacy: .public)"
            )
        }

        return archived
    }

    /// Puts one row away, with a reason. Does not save — callers batch.
    static func archive(
        _ item: PantryItem,
        at date: Date = .now,
        logging kind: PantryEventKind,
        in context: ModelContext
    ) {
        guard !item.isArchived else { return }
        PantryLog.record(kind, for: item, at: date, in: context)
        item.archivedAt = date
    }

    /// Brings a row back, treating the restore as a confirmation — someone
    /// just told us it is there, which is the best evidence there is.
    static func restore(_ item: PantryItem, at date: Date = .now, in context: ModelContext) {
        guard item.isArchived else { return }
        item.confirm(at: date)
        PantryLog.record(.confirmed, for: item, at: date, in: context)
        save(context, "pantry restore")
    }

    // MARK: - Confirming

    /// "Still got it." The sweep's right-swipe, and the row's.
    static func confirm(_ item: PantryItem, at date: Date = .now, in context: ModelContext) {
        item.confirm(at: date)
        PantryLog.record(.confirmed, for: item, at: date, in: context)
        save(context, "pantry confirmation")
    }

    /// "All gone." The sweep's left-swipe. Archives rather than deletes.
    static func markGone(_ item: PantryItem, at date: Date = .now, in context: ModelContext) {
        archive(item, at: date, logging: .depleted, in: context)
        save(context, "pantry depletion")
    }

    /// "Running low." Keeps the row, drops the amount a level, and confirms it
    /// — they just looked at it, which is the whole point of the sweep.
    static func markRunningLow(_ item: PantryItem, at date: Date = .now, in context: ModelContext) {
        item.looseAmount = .runningLow
        item.confirm(at: date, strength: 0.9)
        PantryLog.record(.confirmed, for: item, at: date, in: context)
        save(context, "pantry running low")
    }

    // MARK: - Plumbing

    private static func save(_ context: ModelContext, _ what: String) {
        do {
            try context.save()
        } catch {
            Log.data.error(
                "Could not save \(what, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
