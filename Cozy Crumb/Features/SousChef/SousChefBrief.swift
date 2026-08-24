//
//  SousChefBrief.swift
//  Cozy Crumb
//
//  Everything one turn of conversation needs, assembled from the store.
//
//  This is the seam between the deterministic half of the feature and the
//  conversational one. By the time a brief exists, the ranking has already
//  happened: Swift has read the pantry, applied the hard filters, scored
//  every candidate and picked a balanced handful. What crosses to Gemini is a
//  digest and a list, both of them text, neither of them negotiable.
//
//  Keeping the assembly here rather than in the view model means the whole
//  pipeline — store to prompt — can be exercised in one place, and the view
//  model goes back to being about the conversation.
//

import Foundation
import SwiftData

@MainActor
enum SousChefBrief {

    nonisolated struct Assembled: Sendable {
        var digest: ContextDigest
        var appState: String
        var candidatesBlock: String
        /// The ids the model was actually offered. Anything it quotes back
        /// that is not in here gets dropped rather than shown.
        var offeredRecipeIDs: Set<UUID>
        /// §8's "Why this?" per candidate — the app's own reasoning, kept
        /// separate from whatever the model says about its pick. One is the
        /// score; the other is a sentence. They should not be confused.
        var reasoning: [UUID: [String]]
    }

    /// Reads the store and does all the scoring for one question.
    static func assemble(
        query: String,
        in modelContext: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Assembled {
        let recipes = (try? modelContext.fetch(FetchDescriptor<Recipe>())) ?? []
        // Active rows only. An archived row is one the app stopped believing
        // in; handing it to the Sous Chef would be the staleness bug wearing a
        // different hat.
        let pantryItems = PantryDecay.activeItems(in: modelContext)
        let groceries = (try? modelContext.fetch(FetchDescriptor<GroceryItem>())) ?? []
        let plannedMeals = (try? modelContext.fetch(FetchDescriptor<PlannedMeal>())) ?? []

        let profile = TasteProfileStore.snapshot(in: modelContext)
        let facts = CookFactStore.digestFacts(in: modelContext)

        let unitsRaw = UserDefaults.standard.string(forKey: CozyDefaultsKey.measurementSystem)
        let units = unitsRaw.flatMap(MeasurementSystem.init(rawValue:)) ?? .asWritten

        // The old context still renders the shopping list and the week's
        // plan, which the digest deliberately does not cover.
        let appContext = SousChefContext.build(
            recipes: recipes,
            pantry: pantryItems,
            groceries: groceries,
            plannedMeals: plannedMeals,
            units: units,
            now: now,
            calendar: calendar
        )

        let digest = ContextDigestBuilder.build(
            query: query,
            profile: profile,
            facts: facts,
            recipes: recipes.map(digestRecipe(for:)),
            pantry: appContext.pantry,
            now: now,
            calendar: calendar
        )

        let context = RecommendationContext(
            pantry: pantryItems.map { item in
                PantryEntry(
                    item: item.displayName,
                    category: item.category,
                    evidence: item.evidence
                )
            },
            profile: profile,
            statedMinutes: ConversationConstraints.minutes(in: query),
            date: now,
            calendar: calendar,
            allergens: CookFactStore.allergens(in: modelContext),
            diets: CookFactStore.diets(in: modelContext)
                .union(ConversationConstraints.diets(in: query)),
            excludedIngredients: ConversationConstraints.excludedIngredients(in: query)
        )

        let ranked = RecommendationEngine.recommend(
            from: recipes.map(candidate(for:)),
            context: context,
            limit: RankedCandidatesBlock.limit
        )

        return Assembled(
            digest: digest,
            appState: appContext.appStateText,
            candidatesBlock: RankedCandidatesBlock.render(ranked, now: now),
            offeredRecipeIDs: Set(ranked.map(\.recipe.id)),
            reasoning: Dictionary(
                ranked.map { ($0.recipe.id, $0.whyThis) },
                uniquingKeysWith: { first, _ in first }
            )
        )
    }

    // MARK: - Flattening

    static func candidate(for recipe: Recipe) -> CandidateRecipe {
        CandidateRecipe(
            id: recipe.id,
            title: recipe.title,
            cuisine: recipe.inferredCuisine,
            ingredients: IngredientCanonicalizer.canonical(ingredients: recipe.orderedIngredients),
            rawIngredientText: recipe.shoppableIngredients
                .map { $0.rawText.isEmpty ? $0.name : $0.rawText }
                .joined(separator: ", "),
            techniques: TechniqueClassifier.techniques(for: recipe),
            totalMinutes: recipe.totalMinutes,
            servings: recipe.servings,
            rating: recipe.rating,
            cookCount: recipe.cookLogs.count,
            lastCookedAt: recipe.lastCookedAt,
            tags: recipe.tags
        )
    }

    static func digestRecipe(for recipe: Recipe) -> DigestRecipe {
        DigestRecipe(
            id: recipe.id,
            title: recipe.title,
            tags: recipe.tags,
            cuisine: recipe.inferredCuisine,
            minutes: recipe.totalMinutes,
            rating: recipe.rating,
            cookCount: recipe.cookLogs.count,
            lastCookedAt: recipe.lastCookedAt,
            ingredients: IngredientCanonicalizer.canonical(ingredients: recipe.orderedIngredients)
        )
    }
}

// MARK: - Reading the question

/// Constraints someone states in the message itself.
///
/// §4 requires anything said in the current turn to be a hard filter, not a
/// weight — "something vegetarian" means vegetarian, not mostly-vegetarian.
/// This is a small keyword reader rather than another model call: it runs
/// before the request, it has to be instant, and getting "no mushrooms"
/// wrong in a way that costs an API round trip would be worse than the
/// occasional missed phrasing.
nonisolated enum ConversationConstraints {

    /// "in 20 minutes", "half an hour", "quick".
    nonisolated static func minutes(in query: String) -> Int? {
        let text = query.lowercased()

        if text.contains("half an hour") || text.contains("half hour") { return 30 }
        if text.contains("an hour") { return 60 }

        // "in 25 minutes", "25 min", "25-minute"
        let scanner = text.components(separatedBy: CharacterSet.decimalDigits.inverted)
        let numbers = scanner.compactMap(Int.init).filter { $0 > 0 && $0 <= 600 }

        if let number = numbers.first, text.contains("min") || text.contains("hour") {
            return text.contains("hour") && !text.contains("min") ? number * 60 : number
        }

        // A bare "something quick" is a real constraint even without a number.
        if text.contains("quick") || text.contains("fast") || text.contains("no time") {
            return 25
        }

        return nil
    }

    nonisolated static func diets(in query: String) -> Set<DietaryRule> {
        let text = query.lowercased()
        var rules: Set<DietaryRule> = []

        if text.contains("vegan") { rules.insert(.vegan) }
        if text.contains("vegetarian") || text.contains("veggie") { rules.insert(.vegetarian) }
        if text.contains("pescatarian") { rules.insert(.pescatarian) }
        if text.contains("gluten free") || text.contains("gluten-free") { rules.insert(.glutenFree) }
        if text.contains("dairy free") || text.contains("dairy-free") { rules.insert(.dairyFree) }
        if text.contains("no pork") { rules.insert(.porkFree) }

        return rules
    }

    /// "without mushrooms", "no coriander", "hold the olives".
    nonisolated static func excludedIngredients(in query: String) -> Set<String> {
        let markers = ["without ", "no ", "not ", "hold the ", "skip the ", "minus "]
        let text = query.lowercased()

        var excluded: Set<String> = []

        for marker in markers {
            var searchStart = text.startIndex

            while let range = text.range(of: marker, range: searchStart..<text.endIndex) {
                searchStart = range.upperBound

                // Take the next word or two, stopping at punctuation.
                let tail = text[range.upperBound...]
                    .prefix { $0.isLetter || $0.isWhitespace || $0 == "-" }

                let words = tail
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .prefix(2)

                guard let first = words.first, first.count > 2 else { continue }

                // Both the single word and the pair: "no spring onions"
                // should exclude spring onion, "no mushrooms" mushroom.
                excluded.insert(IngredientCanonicalizer.canonical(first))
                if words.count == 2 {
                    excluded.insert(IngredientCanonicalizer.canonical(words.joined(separator: " ")))
                }
            }
        }

        return excluded.filter { !$0.isEmpty }
    }
}
