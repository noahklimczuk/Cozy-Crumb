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

    /// Re-reads every quantity-less ingredient. Returns how many were fixed.
    @discardableResult
    static func run(in context: ModelContext) -> Int {
        let all: [Ingredient]
        do {
            all = try context.fetch(FetchDescriptor<Ingredient>())
        } catch {
            Log.data.error("Ingredient repair could not fetch: \(error.localizedDescription, privacy: .public)")
            return 0
        }

        // Fetching everything and filtering here rather than in a #Predicate:
        // a personal cookbook is small, and optional comparisons in SwiftData
        // predicates are more trouble than they are worth.
        let candidates = all.filter { $0.quantity == nil && !$0.isSectionHeader }
        guard !candidates.isEmpty else { return 0 }

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

        guard repaired > 0 else { return 0 }

        do {
            try context.save()
            Log.data.info("Repaired \(repaired, privacy: .public) ingredient lines")
        } catch {
            Log.data.error("Ingredient repair could not save: \(error.localizedDescription, privacy: .public)")
            return 0
        }

        return repaired
    }
}
