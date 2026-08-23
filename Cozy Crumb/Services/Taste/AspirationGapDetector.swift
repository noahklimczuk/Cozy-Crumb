//
//  AspirationGapDetector.swift
//  Cozy Crumb
//
//  Finds the recipes someone means to make and never will.
//
//  §2 calls this critical and widely ignored, and it is the most interesting
//  thing in the whole signal system: people save elaborate recipes as a
//  statement of intent, look at them fondly, and cook the same stir-fry.
//  Every recommender that only counts saves ends up suggesting more
//  croissants to someone who has never once made a croissant.
//
//  The test is deliberately narrow. Saved 90+ days ago, opened at least
//  twice, never cooked. Saved-and-forgotten is not the same thing — a recipe
//  nobody has looked at since importing is not an aspiration, it is clutter,
//  and reading it as a preference would be inventing a taste out of silence.
//
//  What it does with the finding is gentle. One negative signal per recipe,
//  logged once and never repeated, so the genre stops being recommended. The
//  UI side of it is a "Someday" collection that quietly absorbs them rather
//  than a nag about the things you didn't do.
//

import Foundation
import SwiftData
import os

@MainActor
enum AspirationGapDetector {

    /// How long a recipe has to sit unmade before it counts.
    ///
    /// nonisolated, along with `minimumViews`: the enum is @MainActor for the
    /// half that touches the store, but `identify` is pure so it can be
    /// tested without one, and a main-actor constant is unreachable from
    /// there.
    nonisolated static let ageDays: Double = 90

    /// How many separate looks it takes. One is a glance; two is intent.
    nonisolated static let minimumViews = 2

    /// Runs at most once a day.
    static let minimumInterval: TimeInterval = 24 * 60 * 60

    @discardableResult
    static func runIfDue(
        in modelContext: ModelContext,
        defaults: UserDefaults = .standard,
        now: Date = .now
    ) -> Int {
        let last = defaults.object(forKey: CozyDefaultsKey.lastAspirationScanAt) as? Date
        if let last, now.timeIntervalSince(last) < minimumInterval { return 0 }

        let found = run(in: modelContext, now: now)
        defaults.set(now, forKey: CozyDefaultsKey.lastAspirationScanAt)
        return found
    }

    /// The scan itself. Returns how many new aspirational recipes it found.
    @discardableResult
    static func run(in modelContext: ModelContext, now: Date = .now) -> Int {
        let recipes = (try? modelContext.fetch(FetchDescriptor<Recipe>())) ?? []
        let signals = (try? modelContext.fetch(FetchDescriptor<TasteSignal>())) ?? []

        let profile = TasteProfileStore.profile(in: modelContext)
        var alreadyKnown = Set(profile.aspirationalRecipeIDs)

        let identified = identify(
            recipes: recipes.map { recipe in
                Candidate(
                    id: recipe.id,
                    createdAt: recipe.createdAt,
                    hasBeenCooked: recipe.lastCookedAt != nil || !recipe.cookLogs.isEmpty
                )
            },
            viewsByRecipe: viewCounts(from: signals),
            now: now
        )

        let fresh = identified.subtracting(alreadyKnown)
        guard !fresh.isEmpty else { return 0 }

        for recipeID in fresh {
            // Logged once per recipe, ever. The signal is "this genre is not
            // for them", not "remind them again next month".
            SignalLog.log(.savedButNeverCooked, recipeID: recipeID, in: modelContext, now: now)
            alreadyKnown.insert(recipeID)
        }

        profile.aspirationalRecipeIDs = Array(alreadyKnown)

        do {
            try modelContext.save()
        } catch {
            Log.data.error("Could not record the aspiration gap: \(error.localizedDescription, privacy: .public)")
        }

        Log.data.info("Aspiration gap: \(fresh.count, privacy: .public) saved-but-never-cooked recipes")
        return fresh.count
    }

    // MARK: - The pure part

    nonisolated struct Candidate: Sendable, Equatable {
        var id: UUID
        var createdAt: Date
        var hasBeenCooked: Bool
    }

    /// Which recipes fit the pattern. Separated out so it can be tested
    /// without a store.
    nonisolated static func identify(
        recipes: [Candidate],
        viewsByRecipe: [UUID: Int],
        now: Date
    ) -> Set<UUID> {
        let cutoff = now.addingTimeInterval(-ageDays * 86_400)

        return Set(
            recipes
                .filter { !$0.hasBeenCooked }
                .filter { $0.createdAt < cutoff }
                .filter { (viewsByRecipe[$0.id] ?? 0) >= minimumViews }
                .map(\.id)
        )
    }

    /// How many times each recipe has been opened, counting both the glance
    /// and the proper read.
    nonisolated static func viewCounts(from signals: [TasteSignal]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]

        for signal in signals {
            guard signal.kind == .viewed || signal.kind == .viewedLong,
                  let recipeID = signal.recipeID else { continue }
            counts[recipeID, default: 0] += 1
        }

        return counts
    }
}
