//
//  RecommendationEngine.swift
//  Cozy Crumb
//
//  The heart of the Sous Chef, and the part that contains no AI at all.
//
//  Asking a language model to rank two hundred recipes by how much someone
//  will like them is slow, expensive, non-deterministic, untestable, and
//  worse at arithmetic than a for-loop. So the ranking happens here, in
//  Swift, over plain values, and Gemini's job is to read the result out loud
//  in a way that sounds like a friend rather than a spreadsheet.
//
//  Three rules this file is built around:
//
//  1. Hard filters are not weights. An allergen does not reduce a score, it
//     removes the recipe — before anything is scored, with no path back and
//     no "you could substitute" caveat. Everything else in here is a matter
//     of taste; that one is not.
//
//  2. Every number is explainable. `ScoreBreakdown` keeps each component
//     separately and can put it into plain English, because "Why this?" (§8)
//     has to show the actual reasoning rather than a plausible retelling of
//     it. A total on its own would make that impossible.
//
//  3. Some of the answer is deliberately not the best answer. Returning only
//     top scorers converges on the same six dinners forever, which §10 names
//     as the default failure of preference systems. A share of every result
//     set is a deliberate stretch, tagged as such so the model can be honest
//     about why it is there.
//

import Foundation

// MARK: - Inputs

/// A recipe as the engine sees it: canonical, flat, no SwiftData.
nonisolated struct CandidateRecipe: Sendable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var cuisine: String?
    /// Canonical names, staples included.
    var ingredients: Set<String>
    /// Raw ingredient lines, kept for allergen matching — the canonical form
    /// can lose the word that mattered.
    var rawIngredientText: String
    var techniques: Set<String>
    var totalMinutes: Int?
    var servings: Int
    var rating: Int?
    var cookCount: Int
    var lastCookedAt: Date?
    var tags: [String]

    nonisolated init(
        id: UUID,
        title: String,
        cuisine: String? = nil,
        ingredients: Set<String> = [],
        rawIngredientText: String = "",
        techniques: Set<String> = [],
        totalMinutes: Int? = nil,
        servings: Int = 4,
        rating: Int? = nil,
        cookCount: Int = 0,
        lastCookedAt: Date? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.cuisine = cuisine
        self.ingredients = ingredients
        self.rawIngredientText = rawIngredientText
        self.techniques = techniques
        self.totalMinutes = totalMinutes
        self.servings = servings
        self.rating = rating
        self.cookCount = cookCount
        self.lastCookedAt = lastCookedAt
        self.tags = tags
    }

    /// Ingredients that actually have to be bought, staples aside.
    var coreIngredients: Set<String> {
        ingredients.filter { !IngredientCanonicalizer.isStaple($0) }
    }
}

/// Something in the pantry, with enough context to judge how much to trust it.
nonisolated struct PantryEntry: Sendable, Equatable {
    var name: String
    var category: GroceryCategory
    var addedAt: Date
    var expiresAt: Date?

    nonisolated init(
        name: String,
        category: GroceryCategory = .other,
        addedAt: Date = .now,
        expiresAt: Date? = nil
    ) {
        self.name = name
        self.category = category
        self.addedAt = addedAt
        self.expiresAt = expiresAt
    }

    var canonicalName: String {
        IngredientCanonicalizer.canonical(name)
    }
}

/// Everything the engine needs to know about right now.
nonisolated struct RecommendationContext: Sendable {
    var pantry: [PantryEntry]
    var profile: TasteProfileSnapshot

    /// A limit the user said out loud: "something in 20 minutes".
    var statedMinutes: Int?
    var date: Date
    var calendar: Calendar

    /// Absolute. Never softened, never substituted around.
    var allergens: Set<String>
    var diets: Set<DietaryRule>
    /// Things ruled out by this turn of the conversation only.
    var excludedIngredients: Set<String>
    /// Something they asked for specifically.
    var requiredIngredients: Set<String>
    var excludedRecipeIDs: Set<UUID>

    nonisolated init(
        pantry: [PantryEntry] = [],
        profile: TasteProfileSnapshot = TasteProfileSnapshot(),
        statedMinutes: Int? = nil,
        date: Date = .now,
        calendar: Calendar = .current,
        allergens: Set<String> = [],
        diets: Set<DietaryRule> = [],
        excludedIngredients: Set<String> = [],
        requiredIngredients: Set<String> = [],
        excludedRecipeIDs: Set<UUID> = []
    ) {
        self.pantry = pantry
        self.profile = profile
        self.statedMinutes = statedMinutes
        self.date = date
        self.calendar = calendar
        self.allergens = allergens
        self.diets = diets
        self.excludedIngredients = excludedIngredients
        self.requiredIngredients = requiredIngredients
        self.excludedRecipeIDs = excludedRecipeIDs
    }

    var weekday: Int {
        calendar.component(.weekday, from: date)
    }

    var month: Int {
        calendar.component(.month, from: date)
    }

    /// How long they've got: what they said, or what they usually do today.
    var effortBudgetMinutes: Int {
        if let statedMinutes { return statedMinutes }
        return profile.typicalMinutes(onWeekday: weekday)
    }
}

// MARK: - Outputs

/// Why a recipe is in the list, in a form the prompt can use honestly.
nonisolated enum RecommendationReason: String, Sendable, Codable {
    case safePick = "safe pick"
    case pantry
    case stretch
}

nonisolated struct MissingIngredient: Sendable, Equatable {
    var name: String
    /// 0 (barely matters) to 1 (that's the dish).
    var severity: Double
    var substitute: String?
}

nonisolated struct ScoreWeights: Sendable, Equatable {
    var pantryMatch: Double
    var tasteAffinity: Double
    var effortFit: Double
    var noveltyBalance: Double
    var seasonality: Double
    var recency: Double
    var rating: Double

    /// §4's table, for a cook the app actually knows.
    nonisolated static let established = ScoreWeights(
        pantryMatch: 0.30,
        tasteAffinity: 0.25,
        effortFit: 0.15,
        noveltyBalance: 0.10,
        seasonality: 0.08,
        recency: 0.07,
        rating: 0.05
    )

    /// §9's cold start. Taste affinity is nearly ignored, because a profile
    /// built from four signals is noise, and leaning on it produces
    /// confidently wrong suggestions in exactly the fortnight that decides
    /// whether anyone keeps using this. The weight goes to things that are
    /// true regardless: what's in the fridge, and whether the recipe is any
    /// good.
    nonisolated static let coldStart = ScoreWeights(
        pantryMatch: 0.40,
        tasteAffinity: 0.08,
        effortFit: 0.15,
        noveltyBalance: 0.05,
        seasonality: 0.10,
        recency: 0.07,
        rating: 0.15
    )

    /// Slides from cold-start to established as confidence climbs to the
    /// usable threshold, so the change is gradual rather than a cliff the
    /// user would feel as the app suddenly changing its mind.
    nonisolated static func forConfidence(_ confidence: Double) -> ScoreWeights {
        let progress = min(1, max(0, confidence / TasteProfileSnapshot.usableConfidence))

        func blend(_ cold: Double, _ warm: Double) -> Double {
            cold + (warm - cold) * progress
        }

        return ScoreWeights(
            pantryMatch: blend(coldStart.pantryMatch, established.pantryMatch),
            tasteAffinity: blend(coldStart.tasteAffinity, established.tasteAffinity),
            effortFit: blend(coldStart.effortFit, established.effortFit),
            noveltyBalance: blend(coldStart.noveltyBalance, established.noveltyBalance),
            seasonality: blend(coldStart.seasonality, established.seasonality),
            recency: blend(coldStart.recency, established.recency),
            rating: blend(coldStart.rating, established.rating)
        )
    }

    var total: Double {
        pantryMatch + tasteAffinity + effortFit + noveltyBalance + seasonality + recency + rating
    }
}

/// Each component on its own, so "Why this?" can show the reasoning rather
/// than a story about it.
nonisolated struct ScoreBreakdown: Sendable, Equatable {
    var pantryMatch: Double
    var tasteAffinity: Double
    var effortFit: Double
    var noveltyBalance: Double
    var seasonality: Double
    var recency: Double
    var rating: Double
    var weights: ScoreWeights

    var total: Double {
        pantryMatch * weights.pantryMatch
            + tasteAffinity * weights.tasteAffinity
            + effortFit * weights.effortFit
            + noveltyBalance * weights.noveltyBalance
            + seasonality * weights.seasonality
            + recency * weights.recency
            + rating * weights.rating
    }

    /// Components ranked by how much they actually contributed.
    var contributions: [(name: String, value: Double)] {
        [
            ("what you have in", pantryMatch * weights.pantryMatch),
            ("your taste", tasteAffinity * weights.tasteAffinity),
            ("the time you've got", effortFit * weights.effortFit),
            ("variety", noveltyBalance * weights.noveltyBalance),
            ("the season", seasonality * weights.seasonality),
            ("not repeating yourself", recency * weights.recency),
            ("your own rating", rating * weights.rating)
        ]
        .sorted { $0.value > $1.value }
    }
}

nonisolated struct ScoredRecipe: Sendable, Equatable, Identifiable {
    var recipe: CandidateRecipe
    var breakdown: ScoreBreakdown
    var reason: RecommendationReason
    var have: [String]
    var missing: [MissingIngredient]

    nonisolated var id: UUID { recipe.id }
    var total: Double { breakdown.total }

    /// The worst thing that's missing, which is the thing worth mentioning.
    var mostSeriousMissing: MissingIngredient? {
        missing.max { $0.severity < $1.severity }
    }

    var hasEverything: Bool {
        missing.isEmpty
    }
}

// MARK: - The engine

nonisolated enum RecommendationEngine {

    /// How much of a result set is a deliberate stretch at neutral novelty.
    /// §4 asks for roughly 30%.
    nonisolated static func stretchShare(noveltyAppetite: Double) -> Double {
        0.15 + 0.3 * min(1, max(0, noveltyAppetite))
    }

    /// A recipe cooked within this many days is penalised. Nobody wants the
    /// same dinner twice in a week.
    nonisolated static let recencyWindowDays: Double = 10

    /// What a staple contributes to a pantry match, relative to a real
    /// ingredient. Missing the chicken matters; missing the salt does not.
    nonisolated static let stapleWeight = 0.15

    // MARK: Entry point

    /// The ranked list. Deterministic: same inputs, same order, every time.
    nonisolated static func recommend(
        from candidates: [CandidateRecipe],
        context: RecommendationContext,
        limit: Int = 10
    ) -> [ScoredRecipe] {
        let allowed = candidates.filter { isAllowed($0, in: context) }
        guard !allowed.isEmpty else { return [] }

        let weights = ScoreWeights.forConfidence(context.profile.confidence)
        let scored = allowed.map { score($0, in: context, weights: weights) }

        return balance(scored, context: context, limit: limit)
    }

    // MARK: Hard filters

    /// Everything the user may not be shown, whatever it scores.
    ///
    /// This runs before scoring rather than as a penalty, and that ordering
    /// is the safety property: there is no combination of weights, no
    /// unusually good pantry match, no tuning mistake in some other component
    /// that can push an allergen recipe back into the list.
    nonisolated static func isAllowed(_ recipe: CandidateRecipe, in context: RecommendationContext) -> Bool {
        if context.excludedRecipeIDs.contains(recipe.id) { return false }

        let banned = forbiddenFoods(in: context)
        if contains(recipe, anyOf: banned) { return false }

        // Something they asked for by name this turn.
        if !context.requiredIngredients.isEmpty {
            let required = Set(context.requiredIngredients.map(IngredientCanonicalizer.canonical))
            guard required.isSubset(of: recipe.ingredients) else { return false }
        }

        return true
    }

    /// Every food that rules a recipe out: allergens, diets, stated dislikes,
    /// and anything excluded by the current conversation.
    nonisolated static func forbiddenFoods(in context: RecommendationContext) -> Set<String> {
        var banned = AllergenIndex.excludedFoods(forAllergies: context.allergens)

        for diet in context.diets {
            banned.formUnion(diet.excludedFoods)
        }

        // Stated dislikes are an exact set rather than a score threshold, so
        // this cannot drift with the tuning of the sigmoid.
        banned.formUnion(context.profile.explicitlyDisliked)

        for excluded in context.excludedIngredients {
            banned.insert(excluded.lowercased())
            banned.insert(IngredientCanonicalizer.canonical(excluded))
        }

        return banned.filter { !$0.isEmpty }
    }

    /// Matches on the canonical set *and* on the raw ingredient text.
    ///
    /// The canonical set is the reliable half. The raw pass is a safety net
    /// for foods the canonicaliser reduces to something the allergen lists do
    /// not name, and it is deliberately fussy about two things:
    ///
    ///   * Word boundaries, with each word singularised. A plain substring
    ///     search finds "egg" inside "eggplant" and removes every aubergine
    ///     dish from someone with an egg allergy.
    ///
    ///   * Compound heads are exempt from it. "Milk", "butter", "cream" and
    ///     the rest are the head nouns of things that are not them — coconut
    ///     milk, peanut butter — and matching those by word would take every
    ///     dairy-free curry away from the lactose intolerant, which is the
    ///     opposite of helping. Those foods must match through the canonical
    ///     set, which keeps the compound whole.
    nonisolated static func contains(_ recipe: CandidateRecipe, anyOf foods: Set<String>) -> Bool {
        guard !foods.isEmpty else { return false }

        if !recipe.ingredients.isDisjoint(with: foods) { return true }

        let words = recipe.rawIngredientText
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'-")).inverted)
            .filter { !$0.isEmpty }
            .map(IngredientCanonicalizer.singularised)

        guard !words.isEmpty else { return false }
        let haystack = " " + words.joined(separator: " ") + " "

        return foods.contains { food in
            guard !food.isEmpty, !compoundHeads.contains(food) else { return false }
            return haystack.contains(" " + food + " ")
        }
    }

    /// The last word of every protected compound. These only ever match
    /// through the canonical set — see `contains(_:anyOf:)`.
    nonisolated static let compoundHeads: Set<String> = {
        Set(IngredientCanonicalizer.compounds.compactMap { $0.components(separatedBy: " ").last })
    }()

    // MARK: Scoring

    nonisolated static func score(
        _ recipe: CandidateRecipe,
        in context: RecommendationContext,
        weights: ScoreWeights
    ) -> ScoredRecipe {
        let pantry = pantryMatch(recipe, in: context)

        let breakdown = ScoreBreakdown(
            pantryMatch: pantry.score,
            tasteAffinity: tasteAffinity(recipe, in: context),
            effortFit: effortFit(recipe, in: context),
            noveltyBalance: noveltyBalance(recipe, in: context),
            seasonality: Seasonality.score(ingredients: recipe.ingredients, month: context.month),
            recency: recencyScore(recipe, in: context),
            rating: ratingScore(recipe),
            weights: weights
        )

        return ScoredRecipe(
            recipe: recipe,
            breakdown: breakdown,
            reason: .safePick,
            have: pantry.have.sorted(),
            missing: pantry.missing.sorted { $0.severity > $1.severity }
        )
    }

    /// How much of the recipe is already in the kitchen.
    ///
    /// Two refinements over a plain fraction. Staples count for a fraction of
    /// a real ingredient, so a recipe is not marked "missing 3" because
    /// nobody thought to add salt to their pantry. And each pantry item is
    /// discounted by how long it has been sitting there, at a rate that
    /// depends on what it is — nothing consumes pantry items when you cook, so
    /// three-week-old spinach is a claim the score should not fully believe.
    nonisolated static func pantryMatch(
        _ recipe: CandidateRecipe,
        in context: RecommendationContext
    ) -> (score: Double, have: Set<String>, missing: [MissingIngredient]) {
        guard !recipe.ingredients.isEmpty else { return (0.5, [], []) }

        var freshnessByFood: [String: Double] = [:]
        for entry in context.pantry {
            let name = entry.canonicalName
            guard !name.isEmpty else { continue }
            let freshness = self.freshness(of: entry, on: context.date)
            freshnessByFood[name] = max(freshnessByFood[name] ?? 0, freshness)
        }

        var earned = 0.0
        var possible = 0.0
        var have: Set<String> = []
        var missing: [MissingIngredient] = []

        for ingredient in recipe.ingredients {
            let isStaple = IngredientCanonicalizer.isStaple(ingredient)
            let weight = isStaple ? stapleWeight : 1.0
            possible += weight

            if let freshness = freshnessByFood[ingredient] {
                earned += weight * freshness
                have.insert(ingredient)
            } else if isStaple {
                // Assumed present. Someone who has cooked anything has salt,
                // and the pantry screen is not a stocktake.
                earned += weight * 0.9
                have.insert(ingredient)
            } else {
                missing.append(MissingIngredient(
                    name: ingredient,
                    severity: IngredientSubstitutions.severity(ofMissing: ingredient),
                    substitute: IngredientSubstitutions.substitute(for: ingredient)
                ))
            }
        }

        let score = possible > 0 ? earned / possible : 0
        return (min(1, max(0, score)), have, missing)
    }

    /// How much to believe that a pantry item is still there.
    ///
    /// Nothing deducts from the pantry when a recipe is cooked, so an old
    /// entry is a claim rather than a fact. Perishables lose credibility
    /// quickly and cupboard things barely at all, which is the difference
    /// between three-week-old spinach and three-week-old rice.
    nonisolated static func freshness(of entry: PantryEntry, on date: Date) -> Double {
        if let expiresAt = entry.expiresAt, expiresAt < date {
            // Explicitly past its date. Not removed — they might have used it
            // in time, or it might be fine — but not counted on either.
            return 0.25
        }

        let days = max(0, date.timeIntervalSince(entry.addedAt) / 86_400)
        let halfLife = halfLifeDays(for: entry.category)
        return max(0.3, pow(0.5, days / halfLife))
    }

    /// How long each aisle stays believable, in days.
    nonisolated static func halfLifeDays(for category: GroceryCategory) -> Double {
        switch category {
        case .produce: 14
        case .bakery: 7
        case .meat: 14
        case .dairy: 21
        case .frozen: 180
        case .pantry: 365
        case .condiment: 365
        case .other: 60
        }
    }

    /// 0–1 from the cuisine, ingredient and technique affinities.
    nonisolated static func tasteAffinity(
        _ recipe: CandidateRecipe,
        in context: RecommendationContext
    ) -> Double {
        let profile = context.profile
        var scores: [Double] = []

        if let cuisine = recipe.cuisine, let affinity = profile.cuisineAffinity[cuisine] {
            // Cuisine counts double: it is the coarsest and most reliable
            // thing the profile knows.
            scores.append(affinity)
            scores.append(affinity)
        }

        let known = recipe.coreIngredients.compactMap { profile.ingredientAffinity[$0] }
        if !known.isEmpty {
            scores.append(known.reduce(0, +) / Double(known.count))
        }

        let techniques = recipe.techniques.compactMap { profile.techniqueComfort[$0] }
        if !techniques.isEmpty {
            scores.append(techniques.reduce(0, +) / Double(techniques.count))
        }

        guard !scores.isEmpty else { return 0.5 }

        // Affinities run −1…1; the score runs 0…1.
        let mean = scores.reduce(0, +) / Double(scores.count)
        return (mean + 1) / 2
    }

    /// Does it fit in the time available.
    nonisolated static func effortFit(
        _ recipe: CandidateRecipe,
        in context: RecommendationContext
    ) -> Double {
        guard let minutes = recipe.totalMinutes else { return 0.5 }
        let budget = Double(max(1, context.effortBudgetMinutes))
        let ratio = Double(minutes) / budget

        // Comfortably inside the budget is ideal. Well under is fine but not
        // better than fine — a 5-minute answer to "what shall I cook on a
        // Sunday" is not what was wanted.
        return switch ratio {
        case ..<0.4: 0.75
        case ..<1.05: 1.0
        case ..<1.5: 0.6
        case ..<2.0: 0.3
        default: 0.05
        }
    }

    /// Rewards or punishes repetition depending on what they want.
    nonisolated static func noveltyBalance(
        _ recipe: CandidateRecipe,
        in context: RecommendationContext
    ) -> Double {
        let appetite = min(1, max(0, context.profile.noveltyAppetite))
        let isNew = recipe.cookCount == 0

        // A novelty-seeker gets points for the untried; someone with a
        // rotation gets points for the familiar. Halfway, it barely matters.
        return isNew ? appetite : 1 - appetite
    }

    /// Penalises anything cooked in the last few days.
    nonisolated static func recencyScore(
        _ recipe: CandidateRecipe,
        in context: RecommendationContext
    ) -> Double {
        guard let lastCookedAt = recipe.lastCookedAt else { return 1 }

        let days = context.date.timeIntervalSince(lastCookedAt) / 86_400
        guard days < recencyWindowDays else { return 1 }
        guard days > 0 else { return 0 }

        return days / recencyWindowDays
    }

    /// Their own stars, if they gave any.
    nonisolated static func ratingScore(_ recipe: CandidateRecipe) -> Double {
        guard let rating = recipe.rating else { return 0.6 }
        return Double(rating - 1) / 4
    }

    // MARK: Explore and exploit

    /// Is this outside their usual, in a way they might still enjoy?
    ///
    /// Two kinds of stretch, and both are deliberately *small*. A cuisine
    /// they have not settled into, or one technique above what they have
    /// done. Jumping from stir-frying to fermenting is not a stretch, it is a
    /// different hobby, and suggesting it reads as the app not paying
    /// attention.
    nonisolated static func isStretch(
        _ recipe: CandidateRecipe,
        in context: RecommendationContext
    ) -> Bool {
        let profile = context.profile

        if let cuisine = recipe.cuisine {
            let affinity = profile.cuisineAffinity[cuisine]
            if affinity == nil || (affinity ?? 0) < 0.25 {
                return true
            }
        }

        let comfortCeiling = profile
            .comfortableTechniques(99)
            .map { TechniqueClassifier.demand(of: $0.name) }
            .max() ?? 2

        return recipe.techniques.contains { technique in
            profile.techniqueComfort[technique] == nil
                && TechniqueClassifier.demand(of: technique) == comfortCeiling + 1
        }
    }

    /// Mixes safe picks with stretches, and labels each honestly.
    ///
    /// Without this the list collapses onto whatever scored highest last week
    /// and stays there. The share of stretches follows their appetite for
    /// them, but it is never zero: someone with a rotation still deserves to
    /// be shown something once in a while.
    nonisolated static func balance(
        _ scored: [ScoredRecipe],
        context: RecommendationContext,
        limit: Int
    ) -> [ScoredRecipe] {
        guard limit > 0 else { return [] }

        // Sorted by score, then by title, then by id: a stable order matters
        // more than which of two equal recipes wins, and "stable" has to hold
        // across launches, so it cannot lean on the input order.
        func rank(_ lhs: ScoredRecipe, _ rhs: ScoredRecipe) -> Bool {
            if abs(lhs.total - rhs.total) > 0.000_001 { return lhs.total > rhs.total }
            if lhs.recipe.title != rhs.recipe.title { return lhs.recipe.title < rhs.recipe.title }
            return lhs.recipe.id.uuidString < rhs.recipe.id.uuidString
        }

        var safe: [ScoredRecipe] = []
        var stretches: [ScoredRecipe] = []

        for var candidate in scored {
            if isStretch(candidate.recipe, in: context) {
                candidate.reason = .stretch
                stretches.append(candidate)
            } else {
                candidate.reason = candidate.breakdown.pantryMatch >= 0.85 && candidate.hasEverything
                    ? .pantry
                    : .safePick
                safe.append(candidate)
            }
        }

        safe.sort(by: rank)
        stretches.sort(by: rank)

        let wantedStretches = min(
            stretches.count,
            Int((Double(limit) * stretchShare(noveltyAppetite: context.profile.noveltyAppetite)).rounded())
        )
        let wantedSafe = limit - wantedStretches

        var result = Array(safe.prefix(wantedSafe))
        result.append(contentsOf: stretches.prefix(wantedStretches))

        // Backfill from whichever side had more to give, so a limit of ten
        // returns ten whenever ten exist.
        if result.count < limit {
            let used = Set(result.map(\.id))
            let remainder = (safe + stretches)
                .filter { !used.contains($0.id) }
                .sorted(by: rank)
            result.append(contentsOf: remainder.prefix(limit - result.count))
        }

        return result.sorted(by: rank)
    }
}
