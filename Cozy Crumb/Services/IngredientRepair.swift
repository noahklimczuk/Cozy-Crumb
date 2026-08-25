//
//  IngredientRepair.swift
//  Cozy Crumb
//
//  Re-reads stored ingredient lines that have no quantity, and fills one in
//  when the parser can now find one.
//
//  This exists because parser fixes only help the *next* import. Recipes
//  already saved keep whatever was written at the time, so a social recipe
//  imported before the caption fixes would never scale no matter how much the
//  parser improved. Rather than asking anyone to delete and re-import, the app
//  quietly re-reads them.
//
//  Deliberately conservative: it only ever fills in a missing quantity. An
//  ingredient that already has one is left alone, so a hand-corrected amount
//  is never overwritten. That also makes it safe to run on every launch —
//  lines it cannot improve simply stay as they are.
//

import Foundation
import SwiftData
import os

@MainActor
enum IngredientRepair {

    /// Bumped whenever `IngredientLineParser` learns to read something it
    /// could not read before. The repair pass runs once per version and then
    /// stands down until this changes.
    ///
    /// It needs a version because it does not converge. A line the parser
    /// finds no quantity in — "salt to taste", "a knob of butter" — is left
    /// exactly as it was, which is correct, and means it is still a candidate
    /// next time. The comment this replaces called running on every launch
    /// "safe", and it is: nothing is corrupted. It is not *cheap*. Every
    /// launch fetched every ingredient in the cookbook and re-parsed every
    /// unquantified one, on the main actor, arriving at the same answer it
    /// had arrived at the launch before, for as long as the app was installed.
    static let parserVersion = 1

    /// Re-reads every quantity-less ingredient. Returns how many were fixed.
    @discardableResult
    static func run(in context: ModelContext, defaults: UserDefaults = .standard) -> Int {
        // Checked before the fetch, so a store that has already been through
        // this version costs nothing at all rather than costing a full scan.
        guard defaults.integer(forKey: CozyDefaultsKey.ingredientRepairVersion) < parserVersion else {
            return 0
        }

        let all: [Ingredient]
        do {
            all = try context.fetch(FetchDescriptor<Ingredient>())
        } catch {
            // Not recorded as done: a fetch that failed has examined nothing,
            // and the next launch should try again.
            Log.data.error("Ingredient repair could not fetch: \(error.localizedDescription, privacy: .public)")
            return 0
        }

        // Fetching everything and filtering here rather than in a #Predicate:
        // a personal cookbook is small, and optional comparisons in SwiftData
        // predicates are more trouble than they are worth.
        let candidates = all.filter { $0.quantity == nil && !$0.isSectionHeader }
        guard !candidates.isEmpty else {
            markDone(in: defaults)
            return 0
        }

        var repaired = 0

        for ingredient in candidates {
            let parsed = IngredientLineParser.parse(ingredient.rawText, order: ingredient.order)

            // No quantity found means the line genuinely has none — "salt to
            // taste", "a knob of butter". Leave it exactly as it is.
            guard let quantity = parsed.quantity else { continue }

            ingredient.quantity = quantity
            ingredient.unit = parsed.unit

            if !parsed.name.isEmpty {
                ingredient.name = parsed.name
            }
            if ingredient.note == nil {
                ingredient.note = parsed.note
            }
            ingredient.groceryCategory = GroceryCategoryGuesser.category(for: ingredient.name)

            repaired += 1
        }

        guard repaired > 0 else {
            markDone(in: defaults)
            return 0
        }

        do {
            try context.save()
            Log.data.info("Repaired \(repaired, privacy: .public) ingredient lines")
        } catch {
            // Left unmarked on purpose. The repairs are still sitting unsaved
            // in the context, so the next launch should have another go rather
            // than recording work that never reached the store.
            Log.data.error("Ingredient repair could not save: \(error.localizedDescription, privacy: .public)")
            return 0
        }

        markDone(in: defaults)
        return repaired
    }

    private static func markDone(in defaults: UserDefaults) {
        defaults.set(parserVersion, forKey: CozyDefaultsKey.ingredientRepairVersion)
    }
}
