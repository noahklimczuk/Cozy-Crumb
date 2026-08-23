//
//  TasteProfileStore.swift
//  Cozy Crumb
//
//  The bridge between the store and the pure builder: reads SwiftData,
//  flattens it into plain values, builds, writes the result back, and hands
//  out the snapshot everything else uses.
//
//  Rebuild policy, from §3: on launch when the cached profile is more than a
//  day old, and immediately after anything that changes what the app knows —
//  a cook, or an explicit rating. Not on every signal; opening a recipe is
//  not worth re-deriving six months of history for.
//

import Foundation
import SwiftData
import os

@MainActor
enum TasteProfileStore {

    /// How stale the cache may get before a launch rebuilds it.
    static let maximumAge: TimeInterval = 24 * 60 * 60

    // MARK: - Reading

    /// The stored profile row, created empty on first use.
    static func profile(in modelContext: ModelContext) -> TasteProfile {
        var descriptor = FetchDescriptor<TasteProfile>()
        descriptor.fetchLimit = 1

        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }

        let fresh = TasteProfile()
        modelContext.insert(fresh)
        return fresh
    }

    /// What the engine and the digest read.
    static func snapshot(in modelContext: ModelContext) -> TasteProfileSnapshot {
        profile(in: modelContext).snapshot
    }

    // MARK: - Rebuilding

    /// Rebuilds if the cache is stale. Called on launch.
    @discardableResult
    static func rebuildIfStale(in modelContext: ModelContext, now: Date = .now) -> Bool {
        let profile = profile(in: modelContext)
        guard now.timeIntervalSince(profile.lastRebuiltAt) > maximumAge else { return false }

        rebuild(in: modelContext, now: now)
        return true
    }

    /// Rebuilds now. Called after a cook or a rating, where the new
    /// information is worth acting on straight away.
    static func rebuild(in modelContext: ModelContext, now: Date = .now) {
        let input = makeInput(in: modelContext, now: now)
        let snapshot = TasteProfileBuilder.build(from: input)

        let profile = profile(in: modelContext)
        // Aspirations are detected separately and must survive a rebuild that
        // knows nothing about them.
        var merged = snapshot
        merged.aspirationalRecipeIDs = Set(profile.aspirationalRecipeIDs)
        profile.apply(merged)

        do {
            try modelContext.save()
        } catch {
            Log.data.error("Could not save the taste profile: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Flattening

    /// Reads the store into the plain values the builder wants.
    static func makeInput(in modelContext: ModelContext, now: Date = .now) -> ProfileInput {
        let recipes = (try? modelContext.fetch(FetchDescriptor<Recipe>())) ?? []
        let signals = (try? modelContext.fetch(FetchDescriptor<TasteSignal>())) ?? []
        let profile = profile(in: modelContext)

        return ProfileInput(
            recipes: recipes.map(facts(for:)),
            signals: signals.map { signal in
                ProfileInput.SignalFacts(
                    kind: signal.kind,
                    recipeID: signal.recipeID,
                    ingredientName: signal.ingredientName,
                    tag: signal.tag,
                    weight: signal.weight,
                    timestamp: signal.timestamp,
                    context: signal.context
                )
            },
            overrides: profile.userOverrides,
            dismissed: Set(profile.dismissedKeys),
            now: now
        )
    }

    static func facts(for recipe: Recipe) -> ProfileInput.RecipeFacts {
        ProfileInput.RecipeFacts(
            id: recipe.id,
            title: recipe.title,
            cuisine: recipe.inferredCuisine ?? CuisineClassifier.cuisine(for: recipe),
            ingredients: IngredientCanonicalizer.canonical(ingredients: recipe.orderedIngredients),
            techniques: TechniqueClassifier.techniques(for: recipe),
            equipmentMentioned: KitchenEquipment.mentioned(in: recipe),
            totalMinutes: recipe.totalMinutes,
            servings: recipe.servings,
            rating: recipe.rating,
            cookCount: recipe.cookLogs.count,
            lastCookedAt: recipe.lastCookedAt,
            createdAt: recipe.createdAt
        )
    }

    // MARK: - Corrections (§8)

    /// Records a hand-set value. Locks it against future derivation.
    static func override(_ key: String, value: Double, in modelContext: ModelContext) {
        let profile = profile(in: modelContext)
        profile.userOverrides[key] = value
        profile.dismissedKeys.removeAll { $0 == key }
        rebuild(in: modelContext)
    }

    /// "Forget this." Removes the inference and stops it coming back.
    static func dismiss(_ key: String, in modelContext: ModelContext) {
        let profile = profile(in: modelContext)
        if !profile.dismissedKeys.contains(key) {
            profile.dismissedKeys.append(key)
        }
        profile.userOverrides.removeValue(forKey: key)
        rebuild(in: modelContext)
    }

    /// Undoes a "forget this" or a correction, letting derivation take over
    /// again.
    static func clearCorrection(_ key: String, in modelContext: ModelContext) {
        let profile = profile(in: modelContext)
        profile.dismissedKeys.removeAll { $0 == key }
        profile.userOverrides.removeValue(forKey: key)
        rebuild(in: modelContext)
    }

    /// "Start fresh." Deletes every signal and every correction.
    ///
    /// Deliberately total: a profile the user has disowned should not
    /// reassemble itself from the same evidence within a week.
    static func startFresh(in modelContext: ModelContext) {
        let signals = (try? modelContext.fetch(FetchDescriptor<TasteSignal>())) ?? []
        for signal in signals {
            modelContext.delete(signal)
        }

        let profile = profile(in: modelContext)
        profile.userOverrides = [:]
        profile.dismissedKeys = []
        profile.aspirationalRecipeIDs = []
        profile.apply(TasteProfileSnapshot(lastRebuiltAt: .now))

        do {
            try modelContext.save()
        } catch {
            Log.data.error("Could not clear the taste profile: \(error.localizedDescription, privacy: .public)")
        }
    }
}
