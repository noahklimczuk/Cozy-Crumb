//
//  PantryLog.swift
//  Cozy Crumb
//
//  The one way a `PantryEvent` gets written.
//
//  "Never mutate a PantryItem without logging" is a rule, and rules that need
//  three lines of boilerplate at each call site get skipped under deadline.
//  This makes it one line, and it takes the item so the canonical name, the
//  display name and the unit are never transcribed by hand at a call site that
//  might get one of them wrong.
//
//  The `canonicalName:` overload exists for the events that happen *after* the
//  row is gone — an item swiped away in the sweep, or archived out — where
//  there is nothing left to ask.
//

import Foundation
import SwiftData
import os

enum PantryLog {

    // MARK: - Writing

    /// Logs something that happened to an item that still exists.
    ///
    /// Does not save: the caller is mid-change and will save once, so that a
    /// failed write takes the event with it rather than leaving a history of
    /// something that did not happen.
    static func record(
        _ kind: PantryEventKind,
        for item: PantryItem,
        quantityDelta: Double? = nil,
        recipeID: UUID? = nil,
        at timestamp: Date = .now,
        in context: ModelContext
    ) {
        context.insert(
            PantryEvent(
                canonicalName: item.canonicalName,
                displayName: item.displayName,
                kind: kind,
                quantityDelta: quantityDelta,
                unit: item.unit,
                recipeID: recipeID,
                timestamp: timestamp
            )
        )
    }

    /// Logs something about a food rather than a row — used where the row has
    /// already gone, or never existed.
    static func record(
        _ kind: PantryEventKind,
        displayName: String,
        canonicalName: String? = nil,
        quantityDelta: Double? = nil,
        unit: String? = nil,
        recipeID: UUID? = nil,
        at timestamp: Date = .now,
        in context: ModelContext
    ) {
        context.insert(
            PantryEvent(
                canonicalName: canonicalName ?? IngredientCanonicalizer.canonical(displayName),
                displayName: displayName,
                kind: kind,
                quantityDelta: quantityDelta,
                unit: unit,
                recipeID: recipeID,
                timestamp: timestamp
            )
        )
    }

    // MARK: - Reading

    /// Every event for one food, oldest first.
    static func history(
        forCanonical canonicalName: String,
        in context: ModelContext
    ) -> [PantryEvent] {
        guard !canonicalName.isEmpty else { return [] }

        // Bound to a differently-named local before it goes into the
        // predicate: inside `#Predicate`, `canonicalName` is also the name of
        // the property being compared, and letting the parameter shadow it is
        // asking for the capture to resolve to the wrong one.
        let key = canonicalName

        var descriptor = FetchDescriptor<PantryEvent>(
            predicate: #Predicate { $0.canonicalName == key },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        descriptor.fetchLimit = 200

        do {
            return try context.fetch(descriptor)
        } catch {
            Log.data.error(
                "Pantry history fetch failed: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    /// Every event, newest first. For the debug inspector and the simulation
    /// harness; nothing in the app proper should need the whole log.
    static func all(in context: ModelContext, limit: Int = 500) -> [PantryEvent] {
        var descriptor = FetchDescriptor<PantryEvent>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        do {
            return try context.fetch(descriptor)
        } catch {
            Log.data.error(
                "Pantry log fetch failed: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }
}
