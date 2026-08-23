//
//  ContextDigestTests.swift
//  Cozy CrumbTests
//
//  S5. The payload, and the budget it has to live inside.
//
//  §12 asks specifically for the digest to be tested against a large fixture
//  library, and §10 explains why: token cost grows with the library, and the
//  thing to fix when it stops fitting is the relevance pre-filter, not the
//  budget. So there is a five-hundred-recipe test, and it asserts both that
//  the digest fits and that what survived is the relevant part.
//

import Foundation
import Testing

@testable import Cozy_Crumb

@MainActor
private enum DigestFixture {

    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func recipe(
        _ title: String,
        cuisine: String? = nil,
        tags: [String] = [],
        minutes: Int? = 30,
        rating: Int? = nil,
        cookCount: Int = 0,
        cookedDaysAgo: Double? = nil,
        ingredients: Set<String> = []
    ) -> DigestRecipe {
        DigestRecipe(
            id: UUID(),
            title: title,
            tags: tags,
            cuisine: cuisine,
            minutes: minutes,
            rating: rating,
            cookCount: cookCount,
            lastCookedAt: cookedDaysAgo.map { now.addingTimeInterval(-$0 * 86_400) },
            ingredients: ingredients
        )
    }

    /// A cook the app knows well.
    static var profile: TasteProfileSnapshot {
        TasteProfileSnapshot(
            cuisineAffinity: ["thai": 0.84, "italian": 0.71, "mexican": 0.63, "french": -0.2, "indian": -0.35],
            ingredientAffinity: ["garlic": 0.8, "chili": 0.7, "lime": 0.65, "cilantro": -0.9, "blue cheese": -0.7],
            techniqueComfort: ["braising": 0.6, "stir-frying": 0.8, "roasting": 0.5],
            effortMinutesByWeekday: [1: 90, 3: 30, 5: 30, 7: 75],
            cookHoursByWeekday: [1: [11], 3: [18], 5: [18, 19]],
            spiceTolerance: 0.9,
            inferredHouseholdSize: 2,
            noveltyAppetite: 0.55,
            inferredEquipment: ["air fryer", "dutch oven", "stand mixer"],
            signalCount: 84,
            lastRebuiltAt: now
        )
    }

    /// The spec's own worked example, near enough.
    static var facts: [DigestFact] {
        [
            DigestFact(statement: "Partner doesn't eat mushrooms", provenance: "user-stated"),
            DigestFact(statement: "Lactose intolerant — hard cheeses are fine", provenance: "user-stated", isCritical: true),
            DigestFact(statement: "Prefers one-pan meals on weeknights", provenance: "inferred, 0.7"),
            DigestFact(statement: "No dishwasher", provenance: "user-stated")
        ]
    }

    /// A library big enough to be a problem. §10 says test with 500.
    static func largeLibrary() -> [DigestRecipe] {
        let cuisines = ["thai", "italian", "mexican", "indian", "japanese", "french", "greek", nil]
        let foods = ["chicken", "beef", "salmon", "tofu", "chickpea", "pasta", "rice", "egg"]

        return (0..<500).map { index in
            recipe(
                "Recipe number \(index) with a reasonably long title",
                cuisine: cuisines[index % cuisines.count],
                tags: ["weeknight", "one-pan", "family"],
                minutes: 20 + (index % 8) * 15,
                rating: index % 5 == 0 ? 5 : nil,
                cookCount: index % 7,
                ingredients: [foods[index % foods.count], "garlic", "onion"]
            )
        }
    }
}

@Suite("Digest budgeting")
@MainActor
struct DigestBudgetTests {

    @Test("A 500-recipe library still fits the budget")
    func largeLibraryFits() {
        let digest = ContextDigestBuilder.build(
            query: "what can I make tonight",
            profile: DigestFixture.profile,
            facts: DigestFixture.facts,
            recipes: DigestFixture.largeLibrary(),
            pantry: ["chicken thighs", "jasmine rice", "eggs", "lime", "garlic", "fish sauce"],
            now: DigestFixture.now
        )

        #expect(digest.estimatedTokens <= ContextDigestBuilder.tokenBudget,
                "digest came to \(digest.estimatedTokens) tokens")
        #expect(digest.totalRecipeCount == 500)
        #expect(digest.includedRecipeCount > 0)
        #expect(digest.includedRecipeCount <= ContextDigestBuilder.cookbookLimit)
    }

    @Test("It says what it left out")
    func admitsTruncation() {
        let digest = ContextDigestBuilder.build(
            query: "dinner",
            profile: DigestFixture.profile,
            facts: [],
            recipes: DigestFixture.largeLibrary(),
            pantry: [],
            now: DigestFixture.now
        )

        // Without this the model treats the slice as the whole cookbook and
        // tells someone they don't own a recipe they do.
        #expect(digest.text.contains("more not listed"))
    }

    @Test("A small library is sent whole")
    func smallLibraryIsComplete() {
        let recipes = (0..<12).map { DigestFixture.recipe("Dish \($0)", cuisine: "thai") }

        let digest = ContextDigestBuilder.build(
            query: "dinner",
            profile: DigestFixture.profile,
            facts: [],
            recipes: recipes,
            pantry: [],
            now: DigestFixture.now
        )

        #expect(digest.includedRecipeCount == 12)
        #expect(!digest.text.contains("more not listed"))
    }

    @Test("The estimate is roughly four characters a token")
    func tokenEstimate() {
        let text = String(repeating: "a", count: 380)
        #expect(TokenBudget.estimate(text) == 100)
        #expect(TokenBudget.estimate("") == 0)
    }
}

@Suite("Digest relevance")
@MainActor
struct DigestRelevanceTests {

    @Test("The question decides which recipes are sent")
    func relevanceBeatsAlphabet() {
        // §6: sending a random sixty spends the whole budget saying nothing.
        var recipes = (0..<200).map { DigestFixture.recipe("Filler \($0)", cuisine: "french") }
        recipes.append(DigestFixture.recipe(
            "Salmon traybake",
            cuisine: "british",
            ingredients: ["salmon", "potato"]
        ))

        let ranked = ContextDigestBuilder.rankByRelevance(
            recipes,
            to: "what can I do with salmon",
            profile: DigestFixture.profile
        )

        #expect(ranked.first?.title == "Salmon traybake")
    }

    @Test("Question scaffolding is not matched on")
    func stopWordsAreDropped() {
        let terms = ContextDigestBuilder.searchTerms(in: "what can I make for dinner tonight with chicken")

        #expect(terms.contains("chicken"))
        #expect(!terms.contains("make"))
        #expect(!terms.contains("dinner"))
        #expect(!terms.contains("what"))
    }

    @Test("Plurals in the question match singulars in the cookbook")
    func termsAreSingularised() {
        let terms = ContextDigestBuilder.searchTerms(in: "something with tomatoes")
        #expect(terms.contains("tomato"))
    }

    @Test("A question with nothing in it falls back to taste")
    func emptyQueryRanksByAffinity() {
        let recipes = [
            DigestFixture.recipe("A french thing", cuisine: "french"),
            DigestFixture.recipe("A thai thing", cuisine: "thai"),
            DigestFixture.recipe("An indian thing", cuisine: "indian")
        ]

        let ranked = ContextDigestBuilder.rankByRelevance(
            recipes,
            to: "what should I cook tonight",
            profile: DigestFixture.profile
        )

        #expect(ranked.first?.cuisine == "thai")
        #expect(ranked.last?.cuisine == "indian")
    }
}

@Suite("Digest content")
@MainActor
struct DigestContentTests {

    private func digest(
        query: String = "what should I cook",
        profile: TasteProfileSnapshot? = nil,
        facts: [DigestFact]? = nil,
        recipes: [DigestRecipe] = []
    ) -> ContextDigest {
        ContextDigestBuilder.build(
            query: query,
            profile: profile ?? DigestFixture.profile,
            facts: facts ?? DigestFixture.facts,
            recipes: recipes,
            pantry: ["chicken thighs", "jasmine rice", "lime"],
            now: DigestFixture.now
        )
    }

    @Test("What to avoid is in there, not just what to reach for")
    func negativesAreIncluded() {
        // The most common omission, and the reason people get recommended
        // coriander for the fifth time.
        let text = digest().text

        #expect(text.contains("Avoids:"))
        #expect(text.contains("cilantro"))
        #expect(text.contains("Cooler on:"))
        #expect(text.contains("indian"))
    }

    @Test("The good stuff is in there too")
    func positivesAreIncluded() {
        let text = digest().text

        #expect(text.contains("Leans toward:"))
        #expect(text.contains("thai"))
        #expect(text.contains("Loves:"))
        #expect(text.contains("garlic"))
        #expect(text.contains("Comfortable with:"))
        #expect(text.contains("Hasn't tried:"))
        #expect(text.contains("Equipment seen:"))
        #expect(text.contains("air fryer"))
    }

    @Test("Facts carry where they came from")
    func factProvenance() {
        let text = digest().text

        #expect(text.contains("[user-stated] Partner doesn't eat mushrooms"))
        #expect(text.contains("[inferred, 0.7] Prefers one-pan meals"))
    }

    @Test("The allergy line leads the facts")
    func criticalFactsComeFirst() {
        let section = ContextDigestBuilder.factsSection(DigestFixture.facts)
        let lines = section.components(separatedBy: "\n")

        #expect(lines.count > 1)
        #expect(lines[1].contains("Lactose intolerant"))
    }

    @Test("A cook the app barely knows is described as one")
    func lowConfidenceIsDeclared() {
        let barelyKnown = TasteProfileSnapshot(
            cuisineAffinity: ["thai": 0.9],
            signalCount: 6,
            lastRebuiltAt: DigestFixture.now
        )

        let text = digest(profile: barelyKnown).text

        // §7.1 tells the model not to claim it knows their taste below 0.4,
        // but leaving it to infer that from a decimal is asking for trouble.
        #expect(text.contains("Do not claim to know their taste"))
    }

    @Test("A brand new cook gets an honest blank rather than a fabrication")
    func emptyProfile() {
        let text = digest(profile: TasteProfileSnapshot(), facts: []).text

        #expect(text.contains("Brand new"))
        #expect(!text.contains("Leans toward:"))
    }

    @Test("Recently cooked keeps them off the same dinner twice")
    func recentlyCooked() {
        let recipes = [
            DigestFixture.recipe("Thai basil chicken", cuisine: "thai", cookCount: 4, cookedDaysAgo: 2),
            DigestFixture.recipe("Ancient stew", cookCount: 1, cookedDaysAgo: 200)
        ]

        // Asserted on the section rather than the whole digest: the old stew
        // is still in the cookbook listing, as it should be — it is only the
        // "don't repeat this" list it stays off.
        let section = ContextDigestBuilder.recentlyCooked(recipes, now: DigestFixture.now)

        #expect(section.contains("RECENTLY COOKED"))
        #expect(section.contains("Thai basil chicken (4×)"))
        #expect(!section.contains("Ancient stew"))
        #expect(digest(recipes: recipes).text.contains("RECENTLY COOKED"))
    }

    @Test("The aspiration gap is described as a genre, not a roll-call")
    func aspirationsAreSummarised() {
        let croissants = DigestFixture.recipe("Croissants", cuisine: "french", minutes: 720)
        let sourdough = DigestFixture.recipe("Sourdough", cuisine: "french", minutes: 1440)

        var profile = DigestFixture.profile
        profile.aspirationalRecipeIDs = [croissants.id, sourdough.id]

        let text = digest(profile: profile, recipes: [croissants, sourdough]).text

        #expect(text.contains("SAVED BUT NEVER COOKED"))
        #expect(text.contains("deprioritise this genre"))
        #expect(text.contains("mostly long ones"))
    }

    @Test("Cookbook lines carry the id the model has to quote back")
    func cookbookLinesCarryIDs() {
        let recipe = DigestFixture.recipe("Thai basil chicken", cuisine: "thai", minutes: 25, rating: 5, cookCount: 4)
        let line = ContextDigestBuilder.describe(recipe, now: DigestFixture.now)

        #expect(line.hasPrefix(recipe.id.uuidString))
        #expect(line.contains("Thai basil chicken"))
        #expect(line.contains("25min"))
        #expect(line.contains("★5"))
        #expect(line.contains("cooked 4×"))
    }
}

@Suite("Ranked candidates block")
@MainActor
struct RankedCandidatesBlockTests {

    private func scored(
        _ title: String,
        total: Double,
        reason: RecommendationReason,
        missing: [MissingIngredient] = [],
        have: [String] = ["chicken", "rice"]
    ) -> ScoredRecipe {
        ScoredRecipe(
            recipe: CandidateRecipe(
                id: UUID(),
                title: title,
                cuisine: "thai",
                totalMinutes: 25,
                cookCount: 4,
                lastCookedAt: DigestFixture.now.addingTimeInterval(-18 * 86_400)
            ),
            breakdown: ScoreBreakdown(
                pantryMatch: total, tasteAffinity: total, effortFit: total,
                noveltyBalance: total, seasonality: total, recency: total,
                rating: total, weights: .established
            ),
            reason: reason,
            have: have,
            missing: missing
        )
    }

    @Test("Each line carries its reason code")
    func reasonCodes() {
        let text = RankedCandidatesBlock.render([
            scored("Thai basil chicken", total: 0.91, reason: .safePick),
            scored("Ginger pork bowls", total: 0.78, reason: .pantry),
            scored("Braised chickpeas", total: 0.64, reason: .stretch)
        ], now: DigestFixture.now)

        #expect(text.contains("safe pick"))
        #expect(text.contains("pantry"))
        #expect(text.contains("stretch"))
    }

    @Test("Substitutes are offered where one genuinely exists")
    func substitutesAreNamed() {
        let text = RankedCandidatesBlock.render([
            scored(
                "Ginger pork bowls",
                total: 0.78,
                reason: .pantry,
                missing: [
                    MissingIngredient(name: "mirin", severity: 0.35, substitute: "rice vinegar with a pinch of sugar"),
                    MissingIngredient(name: "spring onion", severity: 0.7, substitute: nil)
                ]
            )
        ], now: DigestFixture.now)

        #expect(text.contains("sub: rice vinegar with a pinch of sugar"))
        #expect(text.contains("have: 2/4"))
    }

    @Test("Having everything is stated plainly")
    func nothingMissing() {
        let text = RankedCandidatesBlock.render([scored("Thai basil chicken", total: 0.91, reason: .safePick)],
                                                now: DigestFixture.now)
        #expect(text.contains("missing: none"))
    }

    @Test("An empty list tells the model to say so rather than invent")
    func emptyCandidates() {
        let text = RankedCandidatesBlock.render([], now: DigestFixture.now)

        #expect(text.contains("none"))
        #expect(text.contains("offer to come up with something new"))
    }

    @Test("A stretch explains itself so the model can be honest")
    func stretchIsExplained() {
        var candidate = scored("Braised chickpeas", total: 0.64, reason: .stretch)
        candidate.recipe.cuisine = "moroccan"
        candidate.recipe.techniques = ["braising"]

        let text = RankedCandidatesBlock.render([candidate], now: DigestFixture.now)

        #expect(text.contains("moroccan, which isn't their usual"))
        #expect(text.contains("needs braising"))
    }
}
