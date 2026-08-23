//
//  GroceryService.swift
//  Cozy Crumb
//
//  The bridge between `GroceryMerge` (pure values) and SwiftData (the stored
//  list). Everything that writes to the grocery list goes through here so the
//  merge rules can't drift between the recipe screen and the manual add field.
//

import Foundation
import SwiftData
import os

enum GroceryService {

    /// What an add did, so the UI can say "3 added, 2 merged" rather than
    /// leaving the user to spot the difference.
    nonisolated struct AddOutcome: Sendable, Equatable {
        var added: Int
        var merged: Int

        nonisolated init(added: Int = 0, merged: Int = 0) {
            self.added = added
            self.merged = merged
        }

        nonisolated var total: Int { added + merged }

        /// Nil when nothing happened — there's no point announcing a no-op.
        nonisolated var summary: String? {
            switch (added, merged) {
            case (0, 0):
                nil
            case (let a, 0):
                "\(a) item\(a == 1 ? "" : "s") added."
            case (0, let m):
                "\(m) item\(m == 1 ? "" : "s") merged with what was already there."
            case (let a, let m):
                "\(a) added, \(m) merged in."
            }
        }
    }

    // MARK: - The list

    /// Fetches the single active list, creating it on first use.
    ///
    /// The model already supports several named lists; the app shows one, so
    /// this is where that choice lives rather than scattered through views.
    static func activeList(in context: ModelContext) -> GroceryList {
        let descriptor = FetchDescriptor<GroceryList>(sortBy: [SortDescriptor(\.createdAt)])

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let list = GroceryList()
        context.insert(list)
        return list
    }

    // MARK: - Recipes in

    /// Turns a recipe's ingredients into grocery lines at the servings the
    /// user is actually cooking.
    ///
    /// Section headers and lines with nothing to buy are dropped. Units are
    /// left exactly as the recipe wrote them — the shopping list is not the
    /// place to start converting between systems.
    static func lineItems(from recipe: Recipe, servings: Int) -> [GroceryLineItem] {
        let original = max(1, recipe.servings)

        let lines = recipe.orderedIngredients
            .filter { !$0.isSectionHeader }
            .compactMap { ingredient -> GroceryLineItem? in
                let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }

                let scaled = ServingsScaler.scale(ingredient, from: original, to: servings)

                return GroceryLineItem(
                    name: name,
                    quantity: scaled.quantity,
                    unit: scaled.unit,
                    category: ingredient.groceryCategory,
                    sourceRecipeTitles: [recipe.title]
                )
            }

        // Fold within the recipe first: some recipes list the same thing twice
        // ("butter, divided"), and adding it should still make one row.
        return GroceryMerge.folded(lines)
    }

    // MARK: - Adding

    @discardableResult
    static func add(
        _ lines: [GroceryLineItem],
        to list: GroceryList,
        in context: ModelContext
    ) -> AddOutcome {
        var outcome = AddOutcome()

        for line in GroceryMerge.folded(lines) {
            // Only unchecked rows are merge targets. Folding into something
            // already ticked off would silently un-buy it.
            let target = list.items.first { item in
                !item.isChecked && GroceryMerge.canMerge(lineItem(for: item), line)
            }

            if let target {
                apply(GroceryMerge.merging(lineItem(for: target), with: line), to: target)
                outcome.merged += 1
            } else {
                let item = GroceryItem(
                    name: line.name,
                    quantity: line.quantity,
                    unit: line.unit,
                    category: line.category,
                    sourceRecipeTitles: line.sourceRecipeTitles
                )
                item.list = list
                context.insert(item)
                outcome.added += 1
            }
        }

        save(context, "grocery additions")
        return outcome
    }

    // MARK: - Removing

    static func clearCompleted(from list: GroceryList, in context: ModelContext) {
        for item in list.items where item.isChecked {
            context.delete(item)
        }
        save(context, "clear completed")
    }

    static func clearAll(from list: GroceryList, in context: ModelContext) {
        for item in list.items {
            context.delete(item)
        }
        save(context, "clear list")
    }

    static func delete(_ item: GroceryItem, in context: ModelContext) {
        context.delete(item)
        save(context, "delete grocery item")
    }

    // MARK: - Pantry hand-off

    /// Ticking something off optionally means you now own it (§5.5). Merges
    /// into an existing pantry row rather than stacking duplicates.
    static func addToPantry(_ item: GroceryItem, in context: ModelContext, now: Date = .now) {
        let key = GroceryMerge.normalizedName(item.name)
        let existing = (try? context.fetch(FetchDescriptor<PantryItem>()))?
            .first { GroceryMerge.normalizedName($0.displayName) == key }

        if let existing {
            // They were holding it. That is a confirmation as much as an
            // addition, and the strongest evidence short of typing it in.
            existing.addedAt = now
            existing.lastConfirmedAt = now
            existing.confidenceAtConfirmation = max(
                existing.confidenceAtConfirmation,
                CaptureSource.groceryCheckoff.initialConfidence
            )
            if existing.quantity == nil {
                existing.quantity = item.quantity
                existing.unit = item.unit
            }
            PantryLog.record(.added, for: existing, quantityDelta: item.quantity, at: now, in: context)
        } else {
            let pantryItem = PantryItem(
                displayName: item.name,
                quantity: item.quantity,
                unit: item.unit,
                category: item.category,
                tier: PantryTierClassifier.tier(for: item.name, category: item.category),
                addedAt: now,
                addedVia: .groceryCheckoff
            )
            context.insert(pantryItem)
            PantryLog.record(.added, for: pantryItem, quantityDelta: item.quantity, at: now, in: context)
        }

        save(context, "pantry hand-off")
    }

    // MARK: - Plumbing

    static func lineItem(for item: GroceryItem) -> GroceryLineItem {
        GroceryLineItem(
            name: item.name,
            quantity: item.quantity,
            unit: item.unit,
            category: item.category,
            sourceRecipeTitles: item.sourceRecipeTitles
        )
    }

    private static func apply(_ line: GroceryLineItem, to item: GroceryItem) {
        item.quantity = line.quantity
        item.unit = line.unit
        item.category = line.category
        item.sourceRecipeTitles = line.sourceRecipeTitles
    }

    static func save(_ context: ModelContext, _ what: String) {
        do {
            try context.save()
        } catch {
            Log.data.error(
                "Could not save \(what, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
