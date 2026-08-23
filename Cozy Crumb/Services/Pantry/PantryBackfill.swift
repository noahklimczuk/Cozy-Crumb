//
//  PantryBackfill.swift
//  Cozy Crumb
//
//  Brings pantry rows written before the revamp up to the new shape, and seeds
//  the staples on a kitchen that has never had any.
//
//  Modelled on `CuisineBackfill` and `IngredientRepair`, and running from the
//  same place on launch. That is deliberate: every field the revamp adds is
//  either new or an `@Attribute(originalName:)` rename, both of which ride
//  SwiftData's inferred migration, so the store opens fine on its own. What
//  inference cannot do is *derive* — it will happily give every existing row
//  `tier = .stock` and `lastConfirmedAt = <whenever the migration ran>`, and
//  the second of those is a lie that would make a two-year-old jar of tahini
//  look like it was confirmed this morning.
//
//  A custom `MigrationStage` could do the same job. It would also mean taking
//  snapshot copies of the models into a versioned namespace — see the note at
//  the top of `CozyCrumbSchema` for why that is more delicate than it sounds —
//  to solve a problem this repo already solves three other ways.
//
//  Idempotent, and cheap in steady state: one fetch, and a row that has been
//  through this is recognised by `hasBeenBackfilled` and skipped.
//

import Foundation
import SwiftData
import os

@MainActor
enum PantryBackfill {

    /// Backfills anything that needs it and seeds the staples. Returns how
    /// many rows were written, seeds included.
    @discardableResult
    static func run(
        in context: ModelContext,
        defaults store: UserDefaults = .standard
    ) -> Int {
        let items: [PantryItem]
        do {
            items = try context.fetch(FetchDescriptor<PantryItem>())
        } catch {
            Log.data.error(
                "Pantry backfill could not fetch: \(error.localizedDescription, privacy: .public)"
            )
            return 0
        }

        var written = backfill(items, defaults: store)
        written += seedStaples(alongside: items, in: context, defaults: store)

        guard written > 0 else { return 0 }

        do {
            try context.save()
            Log.data.info("Pantry backfill wrote \(written, privacy: .public) rows")
        } catch {
            Log.data.error(
                "Pantry backfill could not save: \(error.localizedDescription, privacy: .public)"
            )
        }

        return written
    }

    // MARK: - Existing rows

    /// Fills in the fields the old model never had.
    ///
    /// No `PantryEvent` is written for any of this. These are rows that were
    /// already here, and inventing an `.added` event dated today for each of
    /// them would hand restock prediction a fake purchase spike on the day of
    /// the upgrade — a history it would then take months to see past.
    private static func backfill(
        _ items: [PantryItem],
        defaults store: UserDefaults
    ) -> Int {
        var written = 0

        for item in items where !item.hasBeenBackfilled {
            // The old model's only timestamp. Using it rather than `.now` is
            // the whole point: a row added six weeks ago should decay like a
            // row added six weeks ago.
            item.lastConfirmedAt = item.addedAt
            item.confidenceAtConfirmation = min(
                item.addedVia.initialConfidence,
                item.addedVia.confidenceCap
            )
            item.tier = PantryTierClassifier.backfillTier(for: item, defaults: store)
            item.location = StorageLocation.inferred(from: item.category)
            written += 1
        }

        return written
    }

    // MARK: - Staples

    /// Writes the starter staples, once, on a kitchen that has never had them.
    ///
    /// Guarded twice, the same way `SeedData` is: a flag for "we have done
    /// this", and a check that the row is not already there under some name.
    /// Someone who deletes the salt should not get it back on next launch.
    private static func seedStaples(
        alongside items: [PantryItem],
        in context: ModelContext,
        defaults store: UserDefaults
    ) -> Int {
        guard !store.bool(forKey: PantryStaples.seededKey) else { return 0 }
        store.set(true, forKey: PantryStaples.seededKey)

        let existing = Set(items.map(\.canonicalName).filter { !$0.isEmpty })
        var written = 0

        for seed in PantryStaples.seeds {
            let canonical = IngredientCanonicalizer.canonical(seed.name)
            guard !canonical.isEmpty, !existing.contains(canonical) else { continue }

            context.insert(
                PantryItem(
                    displayName: seed.name,
                    category: seed.category,
                    tier: .staple,
                    isPinned: true,
                    addedVia: .manual
                )
            )
            written += 1
        }

        return written
    }
}
