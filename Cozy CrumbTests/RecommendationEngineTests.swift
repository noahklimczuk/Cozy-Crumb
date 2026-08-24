//
//  RecommendationEngineTests.swift
//  Cozy CrumbTests
//
//  S4. The scoring engine, which contains no AI and must never need any.
//
//  The suite that matters most is "Hard filters". §12 singles out the
//  allergen test as the one that actually counts for safety, so it is written
//  to be hostile: it tries to get an allergen recipe into the output by
//  giving it a perfect pantry match, a perfect taste match, five stars, and
//  then by rewriting the weights underneath the engine. None of it should
//  work, because the filter runs before scoring exists.
//

import Foundation
import Testing

@testable import Cozy_Crumb

// MARK: - Shared fixtures

@MainActor
private enum Kitchen {

    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Toronto") ?? .gmt
        return cal
    }()

    /// Tuesday, 4 February 2025 — a winter weeknight.
    static let tuesday: Date = {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2025, month: 2, day: 4, hour: 18
        )
        return components.date ?? Date(timeIntervalSince1970: 1_738_710_000)
    }()

    static func recipe(
        _ title: String,
        cuisine: String? = nil,
        ingredients: Set<String>,
        raw: String? = nil,
        techniques: Set<String> = [],
        minutes: Int? = 30,
        rating: Int? = nil,
        cookCount: Int = 0,
        lastCookedAt: Date? = nil
    ) -> CandidateRecipe {
        CandidateRecipe(
            id: UUID(uuidString: stableID(for: title)) ?? UUID(),
            title: title,
            cuisine: cuisine,
            ingredients: ingredients,
            rawIngredientText: raw ?? ingredients.sorted().joined(separator: ", "),
            techniques: techniques,
            totalMinutes: minutes,
            rating: rating,
            cookCount: cookCount,
            lastCookedAt: lastCookedAt
        )
    }

    /// A UUID derived from the title, so fixtures are stable run to run and
    /// the determinism tests mean something.
    private static func stableID(for title: String) -> String {
        var hash: UInt64 = 5381
        for byte in title.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        let hex = String(format: "%016llx", hash)
        return "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-4000-8000-\(hex.prefix(12))"
    }

    static func pantry(_ names: [String], daysOld: Double = 1, category: GroceryCategory = .pantry) -> [PantryEntry] {
        names.map {
            PantryEntry(
                name: $0,
                category: category,
                lastConfirmedAt: tuesday.addingTimeInterval(-daysOld * 86_400)
            )
        }
    }

    /// A profile with enough behind it to be past the cold-start gate.
    static func establishedProfile(
        cuisines: [String: Double] = [:],
        ingredients: [String: Double] = [:],
        techniques: [String: Double] = [:],
        novelty: Double = 0.5,
        disliked: Set<String> = [],
        weekdayMinutes: [Int: Int] = [:]
    ) -> TasteProfileSnapshot {
        TasteProfileSnapshot(
            cuisineAffinity: cuisines,
            ingredientAffinity: ingredients,
            techniqueComfort: techniques,
            effortMinutesByWeekday: weekdayMinutes,
            noveltyAppetite: novelty,
            explicitlyDisliked: disliked,
            signalCount: 90,
            lastRebuiltAt: tuesday
        )
    }
}

// MARK: - Hard filters

@Suite("Hard filters")
@MainActor
struct HardFilterTests {

    private let peanutStirFry = Kitchen.recipe(
        "Peanut noodles",
        cuisine: "thai",
        ingredients: ["noodle", "peanut butter", "soy sauce", "lime", "chicken"],
        raw: "rice noodles, 3 tbsp peanut butter, soy sauce, lime, chicken thighs",
        rating: 5
    )

    private let safeStirFry = Kitchen.recipe(
        "Ginger chicken",
        cuisine: "thai",
        ingredients: ["chicken", "ginger", "soy sauce", "rice"],
        raw: "chicken thighs, ginger, soy sauce, jasmine rice"
    )

    /// §12: "write an explicit test that an allergen recipe never appears in
    /// output, under any scoring configuration."
    @Test("An allergen recipe never appears, however well it scores")
    func allergenIsNeverReturned() {
        // Everything is stacked in the peanut recipe's favour: every
        // ingredient in the pantry, the cuisine they love most, five stars.
        let context = RecommendationContext(
            pantry: Kitchen.pantry(["noodle", "peanut butter", "soy sauce", "lime", "chicken"]),
            profile: Kitchen.establishedProfile(
                cuisines: ["thai": 1.0],
                ingredients: ["peanut butter": 1.0, "noodle": 1.0]
            ),
            date: Kitchen.tuesday,
            calendar: Kitchen.calendar,
            allergens: ["peanut"]
        )

        let results = RecommendationEngine.recommend(
            from: [peanutStirFry, safeStirFry],
            context: context,
            limit: 10
        )

        #expect(!results.contains { $0.recipe.id == peanutStirFry.id })
        #expect(results.contains { $0.recipe.id == safeStirFry.id })
    }

    @Test("No scoring configuration can let one back in")
    func allergenSurvivesEveryWeighting() {
        // The filter runs before scoring, so no arrangement of weights can
        // reach it. This walks a spread of them to prove that ordering is the
        // safety property rather than a lucky default.
        let weightings: [Double] = [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]

        for confidence in weightings {
            let context = RecommendationContext(
                pantry: Kitchen.pantry(["noodle", "peanut butter", "soy sauce", "lime", "chicken"]),
                profile: TasteProfileSnapshot(
                    cuisineAffinity: ["thai": 1.0],
                    ingredientAffinity: ["peanut butter": 1.0],
                    noveltyAppetite: confidence,
                    signalCount: Int(confidence * 200),
                    lastRebuiltAt: Kitchen.tuesday
                ),
                date: Kitchen.tuesday,
                calendar: Kitchen.calendar,
                allergens: ["peanut"]
            )

            let results = RecommendationEngine.recommend(
                from: [peanutStirFry],
                context: context,
                limit: 10
            )

            #expect(results.isEmpty, "a peanut recipe surfaced at confidence \(confidence)")
        }
    }

    @Test("Allergies expand to the whole group without being spelled out")
    func allergenGroupsExpand() {
        let almondCake = Kitchen.recipe(
            "Almond cake",
            ingredients: ["almond", "egg", "sugar"],
            raw: "200g ground almonds, 3 eggs, caster sugar"
        )

        let context = RecommendationContext(
            date: Kitchen.tuesday,
            calendar: Kitchen.calendar,
            allergens: ["nuts"]
        )

        #expect(!RecommendationEngine.isAllowed(almondCake, in: context))
    }

    @Test("An egg allergy does not take away the aubergine")
    func noSubstringFalsePositives() {
        // A plain substring search finds "egg" inside "eggplant". Someone
        // avoiding eggs can eat aubergine, and quietly removing it is a real
        // cost paid for a sloppy match.
        let babaGanoush = Kitchen.recipe(
            "Baba ganoush",
            ingredients: ["eggplant", "tahini", "lemon", "garlic"],
            raw: "2 large eggplants, tahini, lemon, garlic"
        )

        let context = RecommendationContext(
            date: Kitchen.tuesday,
            calendar: Kitchen.calendar,
            allergens: ["egg"]
        )

        #expect(RecommendationEngine.isAllowed(babaGanoush, in: context))
    }

    @Test("A dairy allergy does not take away the coconut milk")
    func compoundsAreNotTheirHeadNoun() {
        // The other half of the same problem, and the more consequential one:
        // dairy-free curries are exactly what a lactose-intolerant cook wants
        // suggested.
        let curry = Kitchen.recipe(
            "Thai green curry",
            cuisine: "thai",
            ingredients: ["coconut milk", "chicken", "curry paste", "bell pepper"],
            raw: "400ml full-fat coconut milk, chicken thighs, green curry paste, bell peppers"
        )

        let context = RecommendationContext(
            date: Kitchen.tuesday,
            calendar: Kitchen.calendar,
            allergens: ["dairy"]
        )

        #expect(RecommendationEngine.isAllowed(curry, in: context))
    }

    @Test("But real dairy is still caught")
    func realDairyIsCaught() {
        let carbonara = Kitchen.recipe(
            "Carbonara",
            cuisine: "italian",
            ingredients: ["pasta", "egg", "parmesan", "pancetta"],
            raw: "spaghetti, eggs, grated parmesan, pancetta"
        )

        let context = RecommendationContext(
            date: Kitchen.tuesday,
            calendar: Kitchen.calendar,
            allergens: ["dairy"]
        )

        #expect(!RecommendationEngine.isAllowed(carbonara, in: context))
    }

    @Test("Diets are absolute too")
    func dietsAreEnforced() {
        let beefStew = Kitchen.recipe("Beef stew", ingredients: ["beef", "carrot", "potato"])
        let lentilStew = Kitchen.recipe("Lentil stew", ingredients: ["lentil", "carrot", "potato"])

        let context = RecommendationContext(
            date: Kitchen.tuesday,
            calendar: Kitchen.calendar,
            diets: [.vegetarian]
        )

        let results = RecommendationEngine.recommend(from: [beefStew, lentilStew], context: context)

        #expect(results.map(\.recipe.title) == ["Lentil stew"])
    }

    @Test("Vegan rules out more than vegetarian")
    func veganIsStricter() {
        let omelette = Kitchen.recipe("Omelette", ingredients: ["egg", "cheese", "chive"])

        let vegetarian = RecommendationContext(
            date: Kitchen.tuesday, calendar: Kitchen.calendar, diets: [.vegetarian]
        )
        let vegan = RecommendationContext(
            date: Kitchen.tuesday, calendar: Kitchen.calendar, diets: [.vegan]
        )

        #expect(RecommendationEngine.isAllowed(omelette, in: vegetarian))
        #expect(!RecommendationEngine.isAllowed(omelette, in: vegan))
    }

    @Test("A stated dislike removes the recipe rather than docking it")
    func statedDislikesAreAFilter() {
        let salsa = Kitchen.recipe("Salsa verde", ingredients: ["cilantro", "lime", "tomatillo"])

        let context = RecommendationContext(
            profile: Kitchen.establishedProfile(disliked: ["cilantro"]),
            date: Kitchen.tuesday,
            calendar: Kitchen.calendar
        )

        #expect(!RecommendationEngine.isAllowed(salsa, in: context))
    }

    @Test("Something ruled out in conversation stays out for that turn")
    func conversationalConstraints() {
        let mushroomRisotto = Kitchen.recipe("Mushroom risotto", ingredients: ["mushroom", "rice", "parmesan"])

        let context = RecommendationContext(
            date: Kitchen.tuesday,
            calendar: Kitchen.calendar,
            excludedIngredients: ["mushroom"]
        )

        #expect(!RecommendationEngine.isAllowed(mushroomRisotto, in: context))
    }

    @Test("Asking for something specific rules out everything without it")
    func requiredIngredients() {
        let withChicken = Kitchen.recipe("Roast chicken", ingredients: ["chicken", "lemon", "potato"])
        let without = Kitchen.recipe("Tomato soup", ingredients: ["tomato", "onion"])

        let context = RecommendationContext(
            date: Kitchen.tuesday,
            calendar: Kitchen.calendar,
            requiredIngredients: ["chicken"]
        )

        let results = RecommendationEngine.recommend(from: [withChicken, without], context: context)
        #expect(results.map(\.recipe.title) == ["Roast chicken"])
    }
}

// MARK: - Scoring

@Suite("Scoring")
@MainActor
struct ScoringTests {

    @Test("The same inputs always produce the same ranking")
    func deterministic() {
        let recipes = [
            Kitchen.recipe("A", cuisine: "thai", ingredients: ["chicken", "lime"]),
            Kitchen.recipe("B", cuisine: "italian", ingredients: ["pasta", "tomato"]),
            Kitchen.recipe("C", cuisine: "mexican", ingredients: ["black bean", "tortilla"]),
            Kitchen.recipe("D", ingredients: ["egg", "potato"])
        ]

        let context = RecommendationContext(
            pantry: Kitchen.pantry(["chicken", "lime", "pasta"]),
            profile: Kitchen.establishedProfile(cuisines: ["thai": 0.8, "italian": 0.3]),
            date: Kitchen.tuesday,
            calendar: Kitchen.calendar
        )

        let first = RecommendationEngine.recommend(from: recipes, context: context)
        let second = RecommendationEngine.recommend(from: recipes.reversed(), context: context)

        #expect(first.map(\.recipe.title) == second.map(\.recipe.title),
                "ranking must not depend on the order the candidates arrived in")
    }

    @Test("Missing the chicken is worse than missing the mirin")
    func missingIngredientsAreNotEqual() {
        // Both are one ingredient short of the same count. Only one of them
        // is still dinner.
        let missingMirin = Kitchen.recipe(
            "Teriyaki salmon",
            ingredients: ["salmon", "soy sauce", "mirin", "ginger"]
        )
        let missingProtein = Kitchen.recipe(
            "Teriyaki chicken",
            ingredients: ["chicken", "soy sauce", "ginger", "rice"]
        )

        let context = RecommendationContext(
            pantry: Kitchen.pantry(["salmon", "soy sauce", "ginger", "rice"]),
            profile: Kitchen.establishedProfile(),
            date: Kitchen.tuesday,
            calendar: Kitchen.calendar
        )

        let results = RecommendationEngine.recommend(from: [missingMirin, missingProtein], context: context)
        let mirin = results.first { $0.recipe.title == "Teriyaki salmon" }
        let chicken = results.first { $0.recipe.title == "Teriyaki chicken" }

        let mirinSeverity = mirin?.mostSeriousMissing?.severity ?? 0
        let chickenSeverity = chicken?.mostSeriousMissing?.severity ?? 0

        #expect(mirinSeverity < chickenSeverity)
        #expect(mirin?.mostSeriousMissing?.substitute != nil, "mirin has a substitute worth naming")
        #expect(chicken?.mostSeriousMissing?.substitute == nil, "nothing substitutes for the chicken")
    }

    @Test("Missing the salt is not missing anything")
    func staplesAreAssumed() {
        let recipe = Kitchen.recipe("Scrambled eggs", ingredients: ["egg", "butter", "salt", "black pepper"])

        let context = RecommendationContext(
            pantry: Kitchen.pantry(["egg"]),
            profile: Kitchen.establishedProfile(),
            date: Kitchen.tuesday,
            calendar: Kitchen.calendar
        )

        let result = RecommendationEngine.recommend(from: [recipe], context: context).first

        #expect(result?.hasEverything == true, "nobody adds salt to their pantry screen")
        #expect((result?.breakdown.pantryMatch ?? 0) > 0.9)
    }

    @Test("Three-week-old spinach counts for less than three-week-old rice")
    func pantryAges() {
        let spinach = PantryEntry(
            name: "spinach",
            category: .produce,
            lastConfirmedAt: Kitchen.tuesday.addingTimeInterval(-21 * 86_400)
        )
        let rice = PantryEntry(
            name: "rice",
            category: .pantry,
            lastConfirmedAt: Kitchen.tuesday.addingTimeInterval(-21 * 86_400)
        )

        // The engine no longer owns this maths — `PantryConfidence` does, and
        // the pantry screen reads the same function. That is the point of the
        // unification, and it moved the numbers: the old table gave cupboard
        // goods a 365-day half-life, the pantry's gives them 90, so rice at
        // three weeks is 0.85 rather than 0.96. Still comfortably believed.
        let spinachConfidence = spinach.confidence(at: Kitchen.tuesday)
        let riceConfidence = rice.confidence(at: Kitchen.tuesday)

        #expect(spinachConfidence < riceConfidence)
        #expect(riceConfidence > 0.8, "rice does not go off in three weeks")
        #expect(spinachConfidence < 0.2, "three-week-old leaves are not dinner")
    }

    @Test("Something expired is not counted on")
    func expiredIsDiscounted() {
        let yogurt = PantryEntry(
            name: "yogurt",
            category: .dairy,
            lastConfirmedAt: Kitchen.tuesday.addingTimeInterval(-5 * 86_400),
            expiresAt: Kitchen.tuesday.addingTimeInterval(-1 * 86_400)
        )

        // Past the user's own date the app stops counting on it, but does not
        // decide the food is bad and does not remove it — it drops to the top
        // of the doubtful band, where the sweep will ask about it.
        #expect(yogurt.confidence(at: Kitchen.tuesday) <= PantryConfidence.doubtfulFloor)
        #expect(yogurt.confidence(at: Kitchen.tuesday) < 0.3)
    }

    @Test("A recipe cooked two days ago is pushed down")
    func recencyPenalty() {
        let justCooked = Kitchen.recipe(
            "Carbonara",
            ingredients: ["pasta", "egg"],
            lastCookedAt: Kitchen.tuesday.addingTimeInterval(-2 * 86_400)
        )
        let notRecent = Kitchen.recipe(
            "Carbonara but older",
            ingredients: ["pasta", "egg"],
            lastCookedAt: Kitchen.tuesday.addingTimeInterval(-60 * 86_400)
        )

        let context = RecommendationContext(
            profile: Kitchen.establishedProfile(), date: Kitchen.tuesday, calendar: Kitchen.calendar
        )

        #expect(RecommendationEngine.recencyScore(justCooked, in: context)
            < RecommendationEngine.recencyScore(notRecent, in: context))
        #expect(RecommendationEngine.recencyScore(notRecent, in: context) == 1)
    }

    @Test("A three-hour project is a poor answer to a Tuesday")
    func effortFit() {
        let quick = Kitchen.recipe("Stir fry", ingredients: ["chicken"], minutes: 25)
        let project = Kitchen.recipe("Cassoulet", ingredients: ["bean"], minutes: 240)

        let context = RecommendationContext(
            profile: Kitchen.establishedProfile(weekdayMinutes: [3: 30]),
            date: Kitchen.tuesday,
            calendar: Kitchen.calendar
        )

        #expect(RecommendationEngine.effortFit(quick, in: context) > RecommendationEngine.effortFit(project, in: context))
        #expect(RecommendationEngine.effortFit(project, in: context) < 0.2)
    }

    @Test("A stated time limit beats the usual pattern")
    func statedTimeWins() {
        let recipe = Kitchen.recipe("Slow braise", ingredients: ["beef"], minutes: 180)

        let unhurried = RecommendationContext(
            profile: Kitchen.establishedProfile(weekdayMinutes: [3: 200]),
            date: Kitchen.tuesday,
            calendar: Kitchen.calendar
        )
        let inAHurry = RecommendationContext(
            profile: Kitchen.establishedProfile(weekdayMinutes: [3: 200]),
            statedMinutes: 20,
            date: Kitchen.tuesday,
            calendar: Kitchen.calendar
        )

        #expect(RecommendationEngine.effortFit(recipe, in: unhurried) == 1.0)
        #expect(RecommendationEngine.effortFit(recipe, in: inAHurry) < 0.1)
    }

    @Test("Out-of-season produce scores below in-season, and seasonless is neutral")
    func seasonality() {
        let februaryTomatoes = Seasonality.score(ingredients: ["tomato", "basil"], month: 2)
        let augustTomatoes = Seasonality.score(ingredients: ["tomato", "basil"], month: 8)
        let seasonless = Seasonality.score(ingredients: ["chicken", "soy sauce"], month: 2)

        #expect(februaryTomatoes < augustTomatoes)
        #expect(seasonless == Seasonality.neutral, "a curry is not out of season")
    }

    @Test("Every component is available separately for 'Why this?'")
    func breakdownIsExplainable() {
        let recipe = Kitchen.recipe("Thai basil chicken", cuisine: "thai", ingredients: ["chicken", "basil"], minutes: 25)

        let context = RecommendationContext(
            pantry: Kitchen.pantry(["chicken", "basil"]),
            profile: Kitchen.establishedProfile(cuisines: ["thai": 0.9], weekdayMinutes: [3: 30]),
            date: Kitchen.tuesday,
            calendar: Kitchen.calendar
        )

        let result = RecommendationEngine.recommend(from: [recipe], context: context).first
        let breakdown = result?.breakdown

        #expect(breakdown != nil)
        #expect((breakdown?.contributions.count ?? 0) == 7)
        #expect(breakdown?.contributions.first?.name == "what you have in")

        // The total has to be the sum of the parts, or the explanation is a
        // story rather than the reasoning.
        let summed = (breakdown?.contributions.reduce(0) { $0 + $1.value }) ?? 0
        #expect(abs(summed - (breakdown?.total ?? 0)) < 0.000_001)
    }
}

// MARK: - Cold start

@Suite("Cold start weighting")
@MainActor
struct ColdStartTests {

    @Test("A new cook is scored on their fridge, not on a profile of four signals")
    func coldStartLeansOnPantry() {
        let cold = ScoreWeights.forConfidence(0)
        let warm = ScoreWeights.forConfidence(1)

        #expect(cold.pantryMatch > warm.pantryMatch)
        #expect(cold.tasteAffinity < warm.tasteAffinity)
        #expect(cold.rating > warm.rating)
    }

    @Test("The weights slide rather than jumping")
    func weightsInterpolate() {
        let halfway = ScoreWeights.forConfidence(TasteProfileSnapshot.usableConfidence / 2)

        #expect(halfway.tasteAffinity > ScoreWeights.coldStart.tasteAffinity)
        #expect(halfway.tasteAffinity < ScoreWeights.established.tasteAffinity)
    }

    @Test("Past the usable threshold the spec's table is in force")
    func settlesOnTheSpecTable() {
        let established = ScoreWeights.forConfidence(TasteProfileSnapshot.usableConfidence)

        #expect(abs(established.pantryMatch - 0.30) < 0.000_001)
        #expect(abs(established.tasteAffinity - 0.25) < 0.000_001)
        #expect(abs(established.effortFit - 0.15) < 0.000_001)
    }

    @Test("Weights always sum to one, whatever the confidence")
    func weightsSumToOne() {
        for confidence in stride(from: 0.0, through: 1.0, by: 0.1) {
            let weights = ScoreWeights.forConfidence(confidence)
            #expect(abs(weights.total - 1.0) < 0.000_001, "weights summed to \(weights.total) at \(confidence)")
        }
    }
}

// MARK: - Explore and exploit

@Suite("Explore and exploit")
@MainActor
struct ExploreExploitTests {

    private func library() -> [CandidateRecipe] {
        let familiar = (0..<8).map { index in
            Kitchen.recipe(
                "Thai regular \(index)",
                cuisine: "thai",
                ingredients: ["chicken", "fish sauce", "lime"],
                techniques: ["stir-frying"],
                minutes: 25
            )
        }
        let unfamiliar = (0..<8).map { index in
            Kitchen.recipe(
                "Moroccan new \(index)",
                cuisine: "moroccan",
                ingredients: ["chickpea", "harissa", "couscous"],
                techniques: ["braising"],
                minutes: 45
            )
        }
        return familiar + unfamiliar
    }

    private func context(novelty: Double) -> RecommendationContext {
        RecommendationContext(
            pantry: Kitchen.pantry(["chicken", "fish sauce", "lime", "chickpea", "harissa", "couscous"]),
            profile: Kitchen.establishedProfile(
                cuisines: ["thai": 0.9],
                techniques: ["stir-frying": 0.9],
                novelty: novelty,
                weekdayMinutes: [3: 40]
            ),
            date: Kitchen.tuesday,
            calendar: Kitchen.calendar
        )
    }

    @Test("The list is never all safe picks")
    func alwaysSomeStretch() {
        // §10 names the filter bubble as the default failure of preference
        // systems: without this the app converges on six dinners and stays
        // there. Even a committed creature of habit gets shown something.
        let results = RecommendationEngine.recommend(from: library(), context: context(novelty: 0), limit: 10)

        let stretches = results.filter { $0.reason == .stretch }
        #expect(!stretches.isEmpty)
        #expect(stretches.count < results.count)
    }

    @Test("Wanting variety gets you more of it")
    func noveltyRaisesTheStretchShare() {
        let cautious = RecommendationEngine.recommend(from: library(), context: context(novelty: 0.0), limit: 10)
        let adventurous = RecommendationEngine.recommend(from: library(), context: context(novelty: 1.0), limit: 10)

        let cautiousStretches = cautious.filter { $0.reason == .stretch }.count
        let adventurousStretches = adventurous.filter { $0.reason == .stretch }.count

        #expect(adventurousStretches > cautiousStretches)
    }

    @Test("Roughly three in ten, at a neutral appetite")
    func stretchShareMatchesTheSpec() {
        let share = RecommendationEngine.stretchShare(noveltyAppetite: 0.5)
        #expect(abs(share - 0.30) < 0.01)
    }

    @Test("Stretches are labelled so the model can be honest about them")
    func stretchesAreTagged() {
        let results = RecommendationEngine.recommend(from: library(), context: context(novelty: 0.5), limit: 10)

        for result in results where result.reason == .stretch {
            // A stretch is a cuisine they have not settled into, or one
            // technique above their comfort. Never a wild leap.
            #expect(result.recipe.cuisine == "moroccan")
        }
    }

    @Test("A full pantry match is called what it is")
    func pantryReason() {
        let inTheFridge = Kitchen.recipe("Fridge dinner", cuisine: "thai", ingredients: ["chicken", "lime"], minutes: 20)

        let context = RecommendationContext(
            pantry: Kitchen.pantry(["chicken", "lime"]),
            profile: Kitchen.establishedProfile(cuisines: ["thai": 0.8], weekdayMinutes: [3: 30]),
            date: Kitchen.tuesday,
            calendar: Kitchen.calendar
        )

        let result = RecommendationEngine.recommend(from: [inTheFridge], context: context).first
        #expect(result?.reason == .pantry)
    }

    @Test("Asking for ten gets ten when ten exist")
    func fillsTheLimit() {
        let results = RecommendationEngine.recommend(from: library(), context: context(novelty: 0.5), limit: 10)
        #expect(results.count == 10)
    }

    @Test("An empty cookbook returns nothing rather than inventing something")
    func emptyLibrary() {
        #expect(RecommendationEngine.recommend(from: [], context: context(novelty: 0.5)).isEmpty)
    }
}
