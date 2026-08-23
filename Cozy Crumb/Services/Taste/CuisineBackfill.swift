//
//  CuisineBackfill.swift
//  Cozy Crumb
//
//  Fills in `Recipe.inferredCuisine` for recipes saved before the classifier
//  existed, and for any that have been edited since.
//
//  Modelled on `IngredientRepair`, and for the same reason: a classifier only
//  helps the *next* import unless something goes back over what is already
//  saved. A cook with sixty recipes and an empty cuisine column would get a
//  taste profile that knows nothing about cuisine at all, which is most of
//  what the digest talks about.
//
//  Runs on launch and is cheap enough to. A recipe whose cuisine is already
//  set is skipped unless it has been edited since the cuisine was written, so
//  steady state is a single fetch and no writes.
//

import Foundation
import SwiftData
import os

@MainActor
enum CuisineBackfill {

    /// Classifies everything that needs it. Returns how many were written.
    @discardableResult
    static func run(in modelContext: ModelContext) -> Int {
        let recipes: [Recipe]
        do {
            recipes = try modelContext.fetch(FetchDescriptor<Recipe>())
        } catch {
            Log.data.error("Cuisine backfill could not fetch: \(error.localizedDescription, privacy: .public)")
            return 0
        }

        var written = 0

        for recipe in recipes where recipe.inferredCuisine == nil {
            guard let cuisine = CuisineClassifier.cuisine(for: recipe) else { continue }
            recipe.inferredCuisine = cuisine
            written += 1
        }

        guard written > 0 else { return 0 }

        do {
            try modelContext.save()
        } catch {
            Log.data.error("Cuisine backfill could not save: \(error.localizedDescription, privacy: .public)")
            return 0
        }

        Log.data.info("Classified \(written, privacy: .public) recipes by cuisine")
        return written
    }

    /// Classifies one recipe now — called at the end of an import so a new
    /// recipe is never waiting on the next launch to be understood.
    static func classify(_ recipe: Recipe) {
        recipe.inferredCuisine = CuisineClassifier.cuisine(for: recipe)
    }
}
