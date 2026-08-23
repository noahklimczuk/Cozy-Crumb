//
//  ContextDigestBuilder.swift
//  Cozy Crumb
//
//  The thing that actually gets sent.
//
//  Gemini learns nothing between requests, so every turn has to carry who
//  this cook is. It cannot carry all of it — a five-hundred-recipe library
//  and six months of history would swamp the question being asked and cost a
//  fortune — so it carries a digest: a deliberately compressed account of
//  someone, built to a budget.
//
//  §6 sets that budget at about 2,500 tokens. Three things follow:
//
//  1. The cookbook slice is chosen by relevance to *this* question, not
//     alphabetically and not by recency. Sixty random recipes spends the
//     entire budget saying nothing; sixty relevant ones is the difference
//     between "here's a recipe" and "here's the one of yours that fits".
//
//  2. The negatives go in. Most implementations send only what someone
//     likes, which is why they keep suggesting coriander to people who hate
//     coriander. What to avoid is at least as valuable as what to reach for,
//     and it is cheaper to state.
//
//  3. Sections are trimmed in a fixed order when the budget bites, and the
//     cookbook goes first. Losing a few recipes degrades an answer; losing
//     the allergy line is a different kind of problem.
//
//  The token count here is an estimate. Gemini's tokenizer is not available
//  on device, so this uses the standard four-characters-per-token
//  approximation with a margin held back. It is used to decide what to cut,
//  never reported to anyone as fact.
//

import Foundation

// MARK: - Inputs

/// A durable fact about the cook, flattened for the prompt. `CookFact` maps
/// onto this; the digest does not need the storage type.
nonisolated struct DigestFact: Sendable, Equatable {
    var statement: String
    /// "user-stated" or "inferred, 0.7".
    var provenance: String
    /// Allergies and dietary rules are never trimmed, whatever the budget.
    var isCritical: Bool

    nonisolated init(statement: String, provenance: String, isCritical: Bool = false) {
        self.statement = statement
        self.provenance = provenance
        self.isCritical = isCritical
    }
}

/// One line of the cookbook listing.
nonisolated struct DigestRecipe: Sendable, Equatable {
    var id: UUID
    var title: String
    var tags: [String]
    var cuisine: String?
    var minutes: Int?
    var rating: Int?
    var cookCount: Int
    var lastCookedAt: Date?
    var ingredients: Set<String>

    nonisolated init(
        id: UUID,
        title: String,
        tags: [String] = [],
        cuisine: String? = nil,
        minutes: Int? = nil,
        rating: Int? = nil,
        cookCount: Int = 0,
        lastCookedAt: Date? = nil,
        ingredients: Set<String> = []
    ) {
        self.id = id
        self.title = title
        self.tags = tags
        self.cuisine = cuisine
        self.minutes = minutes
        self.rating = rating
        self.cookCount = cookCount
        self.lastCookedAt = lastCookedAt
        self.ingredients = ingredients
    }
}

// MARK: - Output

nonisolated struct ContextDigest: Sendable, Equatable {
    var text: String
    var estimatedTokens: Int
    var includedRecipeCount: Int
    var totalRecipeCount: Int
}

// MARK: - Token budgeting

nonisolated enum TokenBudget {

    /// Characters per token. The usual English approximation; deliberately
    /// slightly pessimistic, since overshooting the budget costs money and
    /// undershooting costs a couple of recipe lines.
    nonisolated static let charactersPerToken = 3.8

    nonisolated static func estimate(_ text: String) -> Int {
        Int((Double(text.count) / charactersPerToken).rounded(.up))
    }
}

// MARK: - The builder

nonisolated enum ContextDigestBuilder {

    /// §6's ceiling.
    nonisolated static let tokenBudget = 2_500

    /// What the builder aims for, leaving room for the estimate to be wrong
    /// in the expensive direction.
    nonisolated static let targetTokens = 2_300

    /// §6's cookbook slice.
    nonisolated static let cookbookLimit = 60

    nonisolated static let recentlyCookedWindowDays: Double = 14

    // MARK: Entry point

    nonisolated static func build(
        query: String,
        profile: TasteProfileSnapshot,
        facts: [DigestFact],
        recipes: [DigestRecipe],
        pantry: [String],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ContextDigest {
        let aboutSection = about(profile: profile, now: now, calendar: calendar)
        let factsSection = self.factsSection(facts)
        let recentSection = recentlyCooked(recipes, now: now)
        let aspirationSection = aspirations(recipes, profile: profile)
        let pantrySection = pantrySection(pantry)

        let fixed = [aboutSection, factsSection, recentSection, aspirationSection, pantrySection]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        let ranked = rankByRelevance(recipes, to: query, profile: profile)

        // Everything but the cookbook is small and load-bearing, so the
        // cookbook takes whatever is left.
        let remaining = targetTokens - TokenBudget.estimate(fixed) - 40
        let (cookbookSection, included) = cookbook(ranked, tokenAllowance: max(0, remaining), now: now)

        let text = ([fixed, cookbookSection].filter { !$0.isEmpty }).joined(separator: "\n\n")

        return ContextDigest(
            text: text,
            estimatedTokens: TokenBudget.estimate(text),
            includedRecipeCount: included,
            totalRecipeCount: recipes.count
        )
    }

    // MARK: Relevance

    /// Orders the cookbook by how much it has to do with what was just asked.
    ///
    /// Cheap and keyword-shaped on purpose — this decides what the model gets
    /// to see, so it runs before the request rather than inside it. Where the
    /// question says nothing useful ("what should I cook?"), it falls back to
    /// what they like, which is the right answer to a question with no
    /// content.
    nonisolated static func rankByRelevance(
        _ recipes: [DigestRecipe],
        to query: String,
        profile: TasteProfileSnapshot
    ) -> [DigestRecipe] {
        let terms = searchTerms(in: query)

        return recipes
            .map { recipe in (recipe: recipe, score: relevance(of: recipe, terms: terms, profile: profile)) }
            .sorted { lhs, rhs in
                if abs(lhs.score - rhs.score) > 0.000_001 { return lhs.score > rhs.score }
                return lhs.recipe.title < rhs.recipe.title
            }
            .map(\.recipe)
    }

    /// Words worth matching on. Drops the scaffolding of a question so
    /// "what can I make for dinner" does not match every recipe on "make".
    nonisolated static func searchTerms(in query: String) -> Set<String> {
        let stopWords: Set<String> = [
            "what", "can", "i", "make", "with", "for", "the", "a", "an", "of",
            "should", "cook", "tonight", "dinner", "lunch", "breakfast", "me",
            "something", "have", "got", "some", "and", "or", "to", "do", "is",
            "my", "in", "on", "it", "that", "this", "any", "you", "please",
            "would", "could", "want", "need", "recipe", "recipes", "up", "am",
            "how", "about", "there", "anything", "good", "quick", "easy"
        ]

        return Set(
            query
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !stopWords.contains($0) }
                .map(IngredientCanonicalizer.singularised)
        )
    }

    nonisolated static func relevance(
        of recipe: DigestRecipe,
        terms: Set<String>,
        profile: TasteProfileSnapshot
    ) -> Double {
        var score = 0.0

        if !terms.isEmpty {
            let title = Set(
                recipe.title
                    .lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { !$0.isEmpty }
                    .map(IngredientCanonicalizer.singularised)
            )

            score += Double(title.intersection(terms).count) * 3.0
            score += Double(recipe.ingredients.intersection(terms).count) * 2.0
            score += Double(Set(recipe.tags.map { $0.lowercased() }).intersection(terms).count) * 1.5

            if let cuisine = recipe.cuisine, terms.contains(cuisine) {
                score += 3.0
            }
        }

        // Taste is the tie-breaker, and the whole ranking when the question
        // carried no terms of its own.
        if let cuisine = recipe.cuisine, let affinity = profile.cuisineAffinity[cuisine] {
            score += affinity
        }
        if recipe.cookCount > 0 {
            score += 0.5
        }
        if let rating = recipe.rating {
            score += Double(rating) / 10
        }

        return score
    }

    // MARK: Sections

    nonisolated static func about(
        profile: TasteProfileSnapshot,
        now: Date,
        calendar: Calendar
    ) -> String {
        var lines = ["=== ABOUT THIS COOK ==="]

        if profile.isEmpty {
            lines.append("Brand new. Nothing has been cooked or saved yet — ask rather than assume.")
            return lines.joined(separator: "\n")
        }

        lines.append(String(
            format: "Confidence: %.2f (based on %d signals)",
            profile.confidence,
            profile.signalCount
        ))

        if !profile.isUsable {
            // The model is told plainly rather than left to infer it from a
            // number, because the failure mode is it confidently describing
            // someone it does not know.
            lines.append("This is below the point where the profile means much. Do not claim to know their taste — ask.")
        }

        let busiest = profile.busiestCookingDays.prefix(3)
        if !busiest.isEmpty {
            let names = busiest.map { SignalContext(weekday: $0, hour: 12, season: .spring).weekdayName }
            lines.append("Cooks most: " + names.joined(separator: ", "))
        }

        let weeknight = [2, 3, 4, 5, 6].compactMap { profile.effortMinutesByWeekday[$0] }
        if !weeknight.isEmpty {
            lines.append("Typical weeknight effort: about \(weeknight.reduce(0, +) / weeknight.count) min")
        }
        let weekend = [1, 7].compactMap { profile.effortMinutesByWeekday[$0] }
        if !weekend.isEmpty {
            lines.append("Typical weekend effort: up to \(weekend.max() ?? 0) min")
        }

        if let household = profile.inferredHouseholdSize {
            lines.append("Household: appears to cook for \(household)")
        }

        let leans = profile.topCuisines()
        if !leans.isEmpty {
            lines.append("Leans toward: " + leans.map { format($0) }.joined(separator: ", "))
        }

        let cooler = profile.coolerCuisines()
        if !cooler.isEmpty {
            lines.append("Cooler on: " + cooler.map { format($0) }.joined(separator: ", "))
        }

        let loves = profile.lovedIngredients()
        if !loves.isEmpty {
            lines.append("Loves: " + loves.map(\.name).joined(separator: ", "))
        }

        // The half everyone forgets. Without it the model recommends
        // coriander for the fifth time.
        let avoids = profile.avoidedIngredients()
        if !avoids.isEmpty {
            lines.append("Avoids: " + avoids.map { format($0) }.joined(separator: ", "))
        }

        let comfortable = profile.comfortableTechniques()
        if !comfortable.isEmpty {
            lines.append("Comfortable with: " + comfortable.map(\.name).joined(separator: ", "))
        }

        let untried = profile.untriedTechniques()
        if !untried.isEmpty {
            lines.append("Hasn't tried: " + untried.joined(separator: ", "))
        }

        if let spice = profile.spiceDescription {
            lines.append("Spice tolerance: \(spice)")
        }

        lines.append(String(format: "Novelty appetite: %.2f — %@", profile.noveltyAppetite, profile.noveltyDescription))

        if !profile.inferredEquipment.isEmpty {
            lines.append("Equipment seen: " + profile.inferredEquipment.sorted().joined(separator: ", "))
        }

        return lines.joined(separator: "\n")
    }

    private nonisolated static func format(_ entry: (name: String, score: Double)) -> String {
        String(format: "%@ (%.2f)", entry.name, entry.score)
    }

    nonisolated static func factsSection(_ facts: [DigestFact]) -> String {
        guard !facts.isEmpty else { return "" }

        // Critical facts lead, so if anything is ever truncated it is not the
        // allergy line.
        let ordered = facts.sorted { lhs, rhs in
            lhs.isCritical && !rhs.isCritical
        }

        return (["=== FACTS ==="] + ordered.map { "[\($0.provenance)] \($0.statement)" })
            .joined(separator: "\n")
    }

    nonisolated static func recentlyCooked(_ recipes: [DigestRecipe], now: Date) -> String {
        let cutoff = now.addingTimeInterval(-recentlyCookedWindowDays * 86_400)

        let recent = recipes
            .filter { ($0.lastCookedAt ?? .distantPast) >= cutoff }
            .sorted { ($0.lastCookedAt ?? .distantPast) > ($1.lastCookedAt ?? .distantPast) }
            .prefix(8)
            .map { recipe -> String in
                recipe.cookCount > 1 ? "\(recipe.title) (\(recipe.cookCount)×)" : recipe.title
            }

        guard !recent.isEmpty else { return "" }

        return "=== RECENTLY COOKED (last 14 days) ===\n" + recent.joined(separator: ", ")
    }

    nonisolated static func aspirations(_ recipes: [DigestRecipe], profile: TasteProfileSnapshot) -> String {
        let aspirational = recipes.filter { profile.aspirationalRecipeIDs.contains($0.id) }
        guard !aspirational.isEmpty else { return "" }

        // Named as a genre rather than listed. The useful instruction is
        // "stop suggesting this kind of thing", not a roll-call of things
        // they failed to make.
        let genres = Set(aspirational.compactMap(\.cuisine)).sorted()
        var line = "=== SAVED BUT NEVER COOKED (90+ days) ===\n"
        line += "\(aspirational.count) recipes"

        if !genres.isEmpty {
            line += ", mostly \(genres.joined(separator: "/"))"
        }

        let longOnes = aspirational.filter { ($0.minutes ?? 0) >= 90 }
        if longOnes.count >= max(2, aspirational.count / 2) {
            line += ", mostly long ones"
        }

        line += " — deprioritise this genre."
        return line
    }

    nonisolated static func pantrySection(_ pantry: [String]) -> String {
        guard !pantry.isEmpty else { return "=== PANTRY RIGHT NOW ===\nnothing recorded" }
        return "=== PANTRY RIGHT NOW ===\n" + pantry.joined(separator: ", ")
    }

    /// The cookbook listing, cut to fit whatever budget is left.
    nonisolated static func cookbook(
        _ ranked: [DigestRecipe],
        tokenAllowance: Int,
        now: Date
    ) -> (text: String, included: Int) {
        guard !ranked.isEmpty else {
            return ("=== COOKBOOK ===\nempty — they haven't saved anything yet.", 0)
        }

        let header = "=== COOKBOOK (most relevant of \(ranked.count)) ==="
        var lines: [String] = []
        var used = TokenBudget.estimate(header)

        for recipe in ranked.prefix(cookbookLimit) {
            let line = describe(recipe, now: now)
            let cost = TokenBudget.estimate(line)
            guard used + cost <= tokenAllowance else { break }

            lines.append(line)
            used += cost
        }

        var text = ([header] + lines).joined(separator: "\n")

        if lines.count < ranked.count {
            // Saying what was left out matters: without it the model treats
            // the slice as the whole cookbook and tells someone they don't
            // own a recipe they do.
            text += "\n…and \(ranked.count - lines.count) more not listed. Don't assume they're missing."
        }

        return (text, lines.count)
    }

    /// One cookbook line. The id leads because §7.1's output contract needs
    /// the model to quote it back.
    nonisolated static func describe(_ recipe: DigestRecipe, now: Date) -> String {
        var parts = ["\(recipe.id.uuidString) | \(recipe.title)"]

        var descriptors = recipe.tags.prefix(3).map { $0 }
        if let cuisine = recipe.cuisine, !descriptors.contains(cuisine) {
            descriptors.insert(cuisine, at: 0)
        }
        if let minutes = recipe.minutes {
            descriptors.append("\(minutes)min")
        }
        if !descriptors.isEmpty {
            parts.append(descriptors.joined(separator: ", "))
        }

        if let rating = recipe.rating {
            parts.append("★\(rating)")
        }

        if recipe.cookCount > 0 {
            parts.append("cooked \(recipe.cookCount)×")
        } else {
            parts.append("never cooked")
        }

        return parts.joined(separator: " | ")
    }
}
