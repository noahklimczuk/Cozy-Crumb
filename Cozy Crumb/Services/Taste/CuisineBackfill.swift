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

    /// Bumped whenever `CuisineClassifier` learns to place something it could
    /// not place before. Same reasoning as `IngredientRepair.parserVersion`:
    /// a recipe the classifier cannot read stays `nil`, so it is still a
    /// candidate next launch and the pass never finishes on its own. The note
    /// above called it "cheap enough to" run every launch on the strength of
    /// "steady state is a single fetch and no writes" — but the fetch is every
    /// recipe in the cookbook, and the classifier runs again on every one it
    /// failed to place last time.
    static let classifierVersion = 1

    /// How many recipes are classified before the main actor is handed back.
    /// Same reasoning as `IngredientRepair.batchSize`.
    private static let batchSize = 50

    /// Classifies everything that needs it. Returns how many were written.
    @discardableResult
    static func run(in modelContext: ModelContext, defaults: UserDefaults = .standard) async -> Int {
        guard defaults.integer(forKey: CozyDefaultsKey.cuisineBackfillVersion) < classifierVersion else {
            return 0
        }

        let recipes: [Recipe]
        do {
            recipes = try modelContext.fetch(FetchDescriptor<Recipe>())
        } catch {
            Log.data.error("Cuisine backfill could not fetch: \(error.localizedDescription, privacy: .public)")
            return 0
        }

        var written = 0
        var examined = 0

        for recipe in recipes where recipe.inferredCuisine == nil {
            if examined > 0, examined.isMultiple(of: batchSize) {
                try? await Task.sleep(for: .milliseconds(1))
            }
            examined += 1

            guard let cuisine = CuisineClassifier.cuisine(for: recipe) else { continue }
            recipe.inferredCuisine = cuisine
            written += 1
        }

        guard written > 0 else {
            markDone(in: defaults)
            return 0
        }

        do {
            try modelContext.save()
        } catch {
            Log.data.error("Cuisine backfill could not save: \(error.localizedDescription, privacy: .public)")
            return 0
        }

        Log.data.info("Classified \(written, privacy: .public) recipes by cuisine")
        markDone(in: defaults)
        return written
    }

    private static func markDone(in defaults: UserDefaults) {
        defaults.set(classifierVersion, forKey: CozyDefaultsKey.cuisineBackfillVersion)
    }

    /// Classifies one recipe now — called at the end of an import so a new
    /// recipe is never waiting on the next launch to be understood.
    static func classify(_ recipe: Recipe) {
        recipe.inferredCuisine = CuisineClassifier.cuisine(for: recipe)
    }
}
