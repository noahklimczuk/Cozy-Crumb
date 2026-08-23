//
//  TasteProfileBuilderTests.swift
//  Cozy CrumbTests
//
//  S3. The derivation, against a fixed fixture.
//
//  §12 asks for a snapshot of the output that is asserted for stability, and
//  the reason is worth stating: a derivation bug does not crash. It produces
//  a number that is merely wrong, the recommendations get slightly worse, and
//  nobody can point at when it started. Pinning the fixture output means a
//  change to the weights has to be deliberate.
//
//  The archetype suite at the bottom is the simulation harness from §12 —
//  three synthetic cooks with six months of behaviour each, run through the
//  builder to check the derived profile actually looks like the archetype.
//  That catches the class of bug unit tests do not: everything individually
//  correct, the whole thing describing the wrong person.
//

import Foundation
import Testing

@testable import Cozy_Crumb

// MARK: - Fixtures

@MainActor
private enum Fixture {

    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func daysAgo(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 86_400)
    }

    static let thaiID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001")!
    static let carbonaraID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000002")!
    static let croissantID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000003")!

    static let thai = ProfileInput.RecipeFacts(
        id: thaiID,
        title: "Thai basil chicken",
        cuisine: "thai",
        ingredients: ["chicken", "basil", "fish sauce", "chili", "garlic", "salt"],
        techniques: ["stir-frying"],
        equipmentMentioned: ["wok"],
        totalMinutes: 25,
        servings: 2,
        rating: 5
    )

    static let carbonara = ProfileInput.RecipeFacts(
        id: carbonaraID,
        title: "Carbonara",
        cuisine: "italian",
        ingredients: ["pasta", "egg", "parmesan", "pancetta", "black pepper"],
        techniques: ["boiling"],
        totalMinutes: 20,
        servings: 2
    )

    static let croissant = ProfileInput.RecipeFacts(
        id: croissantID,
        title: "Croissants",
        cuisine: "french",
        ingredients: ["flour", "butter", "yeast"],
        techniques: ["laminating", "proving"],
        totalMinutes: 720,
        servings: 8
    )

    /// A cook who makes Thai food often, made carbonara once, and has been
    /// admiring croissants for four months without making any.
    static func input() -> ProfileInput {
        var signals: [ProfileInput.SignalFacts] = []

        // Four Thai cooks, three of them repeats, on Tuesdays at 18:00.
        let tuesdayEvening = SignalContext(weekday: 3, hour: 18, season: .summer)
        signals.append(.init(kind: .cooked, recipeID: thaiID, timestamp: daysAgo(80), context: tuesdayEvening))
        for day in [60.0, 40.0, 12.0] {
            signals.append(.init(kind: .cookedRepeat, recipeID: thaiID, timestamp: daysAgo(day), context: tuesdayEvening))
        }
        signals.append(.init(kind: .ratedHigh, recipeID: thaiID, timestamp: daysAgo(12), context: tuesdayEvening))

        // One carbonara, on a Sunday.
        signals.append(.init(
            kind: .cooked,
            recipeID: carbonaraID,
            timestamp: daysAgo(50),
            context: SignalContext(weekday: 1, hour: 19, season: .summer)
        ))

        // Croissants: looked at, never made.
        signals.append(.init(kind: .imported, recipeID: croissantID, timestamp: daysAgo(120)))
        signals.append(.init(kind: .viewed, recipeID: croissantID, timestamp: daysAgo(100)))
        signals.append(.init(kind: .viewedLong, recipeID: croissantID, timestamp: daysAgo(30)))

        // A loose dislike.
        signals.append(.init(kind: .explicitlyDisliked, ingredientName: "cilantro", timestamp: daysAgo(200)))

        return ProfileInput(
            recipes: [thai, carbonara, croissant],
            signals: signals,
            now: now
        )
    }
}

// MARK: - Derivation

@Suite("Profile derivation")
@MainActor
struct TasteProfileBuilderTests {

    private let profile = TasteProfileBuilder.build(from: Fixture.input())

    @Test("The cuisine they actually cook comes out on top")
    func cuisineAffinity() throws {
        let thai = try #require(profile.cuisineAffinity["thai"])
        let italian = try #require(profile.cuisineAffinity["italian"])
        let french = try #require(profile.cuisineAffinity["french"])

        #expect(thai > italian)
        #expect(italian > french)
        #expect(thai > 0.7, "four cooks, three of them repeats, should read as a strong preference")
        #expect(french < 0.2, "looking at croissants is not cooking French food")
    }

    @Test("A stated dislike lands near the floor and stays there")
    func explicitDislike() throws {
        let cilantro = try #require(profile.ingredientAffinity["cilantro"])

        // Logged 200 days ago — past the half-life — and still absolute,
        // because dislikes neither decay nor go through the sigmoid.
        #expect(cilantro <= TasteProfileBuilder.statedDislikeFloor)
        #expect(profile.explicitlyDisliked.contains("cilantro"))
    }

    @Test("Staples are left out of ingredient affinity")
    func staplesExcluded() {
        // Salt is in the Thai recipe and black pepper in the carbonara. Both
        // would otherwise rank near the top and say nothing.
        #expect(profile.ingredientAffinity["salt"] == nil)
        #expect(profile.ingredientAffinity["black pepper"] == nil)
        #expect(profile.ingredientAffinity["fish sauce"] != nil)
    }

    @Test("Ingredients from cooked recipes outrank ones only looked at")
    func ingredientAffinityFollowsCooking() throws {
        let fishSauce = try #require(profile.ingredientAffinity["fish sauce"])
        let yeast = try #require(profile.ingredientAffinity["yeast"])

        #expect(fishSauce > yeast)
    }

    @Test("Technique comfort follows what they've made")
    func techniqueComfort() throws {
        let stirFrying = try #require(profile.techniqueComfort["stir-frying"])
        #expect(stirFrying > 0.5)

        // Laminating was imported and admired, never done. It scores, but
        // barely, and it is not what "comfortable with" means.
        let laminating = profile.techniqueComfort["laminating"] ?? 0
        #expect(laminating < 0.3)
        #expect(!profile.comfortableTechniques().map(\.name).contains("laminating"))
    }

    @Test("Confidence reflects how much there is to go on")
    func confidence() {
        #expect(profile.signalCount == 10)
        #expect(abs(profile.confidence - 10.0 / 60.0) < 0.001)
        #expect(!profile.isUsable, "ten signals is not enough to claim to know someone")
        #expect(profile.confidenceDescription == "Starting to get a feel for it")
    }

    @Test("A single cook on a day does not become a pattern")
    func effortFallsBackToTheAverage() {
        // Tuesday has four cooks of a 25-minute recipe. Sunday has one
        // 20-minute cook, which is not enough, so Sunday inherits the global
        // average rather than claiming Sundays are 20-minute days.
        #expect(profile.effortMinutesByWeekday[3] == 25)

        let sunday = profile.effortMinutesByWeekday[1]
        #expect(sunday == 24, "one cook is not a pattern, so Sunday takes the overall average")
    }

    @Test("Equipment needs repeated use before it is assumed")
    func equipmentNeedsRepetition() {
        // The wok has been used four times, which is enough.
        #expect(profile.inferredEquipment.contains("wok"))
    }

    @Test("Every inference carries its evidence")
    func evidenceIsBuilt() throws {
        let thai = try #require(profile.evidence[ProfileKey.cuisine("thai")])

        #expect(thai.summary.contains("thai"))
        #expect(thai.summary.contains("more than once"))
        #expect(thai.recipeTitles.contains("Thai basil chicken"))
        #expect(thai.signalCount > 0)

        // §8 requires every visible claim to be explainable, so nothing in
        // the profile is allowed to appear without a sentence behind it.
        for cuisine in profile.cuisineAffinity.keys {
            #expect(profile.evidence[ProfileKey.cuisine(cuisine)] != nil, "no evidence for \(cuisine)")
        }
        for ingredient in profile.ingredientAffinity.keys {
            #expect(profile.evidence[ProfileKey.ingredient(ingredient)] != nil, "no evidence for \(ingredient)")
        }
    }

    @Test("Sentences never read '1 recipes'")
    func evidenceGrammar() {
        #expect(TasteProfileBuilder.countPhrase(1, "recipe") == "1 recipe")
        #expect(TasteProfileBuilder.countPhrase(0, "recipe") == "0 recipes")
        #expect(TasteProfileBuilder.countPhrase(6, "recipe") == "6 recipes")
    }

    @Test("The same input always builds the same profile")
    func deterministic() {
        let first = TasteProfileBuilder.build(from: Fixture.input())
        let second = TasteProfileBuilder.build(from: Fixture.input())

        #expect(first == second)
    }

    @Test("An empty history produces an empty profile, not a confident one")
    func emptyInput() {
        let empty = TasteProfileBuilder.build(from: ProfileInput(now: Fixture.now))

        #expect(empty.isEmpty)
        #expect(empty.confidence == 0)
        #expect(empty.cuisineAffinity.isEmpty)
        #expect(empty.spiceTolerance == nil, "a guess about heat is very noticeable when wrong")
        #expect(empty.inferredHouseholdSize == nil)
        #expect(empty.noveltyAppetite == 0.5)
        #expect(empty.confidenceDescription == "Still getting to know you")
    }
}

// MARK: - Corrections

@Suite("Profile corrections")
@MainActor
struct TasteProfileCorrectionTests {

    @Test("A hand-set value wins over the derived one")
    func overrideWins() throws {
        var input = Fixture.input()
        input.overrides = [ProfileKey.cuisine("thai"): -0.5]

        let profile = TasteProfileBuilder.build(from: input)

        #expect(profile.cuisineAffinity["thai"] == -0.5)
    }

    @Test("An override with no history behind it still counts")
    func overrideWithoutSignals() throws {
        // This is how a cold-start answer gets in: they picked Korean off a
        // list of chips before cooking anything at all.
        var input = ProfileInput(now: Fixture.now)
        input.overrides = [ProfileKey.cuisine("korean"): 0.6]

        let profile = TasteProfileBuilder.build(from: input)

        #expect(profile.cuisineAffinity["korean"] == 0.6)
    }

    @Test("Forgetting something removes it rather than zeroing it")
    func dismissRemoves() {
        var input = Fixture.input()
        input.dismissed = [ProfileKey.cuisine("thai")]

        let profile = TasteProfileBuilder.build(from: input)

        // Absence, not a zero. Zero would be a finding — "neutral on Thai" —
        // and the user said to forget it, not that they feel nothing.
        #expect(profile.cuisineAffinity["thai"] == nil)
        #expect(profile.cuisineAffinity["italian"] != nil)
    }

    @Test("Overrides are clamped to the scale")
    func overridesAreClamped() {
        var input = Fixture.input()
        input.overrides = [ProfileKey.cuisine("thai"): 47]

        let profile = TasteProfileBuilder.build(from: input)

        #expect(profile.cuisineAffinity["thai"] == 1)
    }
}

// MARK: - The aspiration gap

@Suite("The aspiration gap")
@MainActor
struct AspirationGapTests {

    private let now = Fixture.now

    private func candidate(_ id: UUID, savedDaysAgo: Double, cooked: Bool = false) -> AspirationGapDetector.Candidate {
        AspirationGapDetector.Candidate(
            id: id,
            createdAt: now.addingTimeInterval(-savedDaysAgo * 86_400),
            hasBeenCooked: cooked
        )
    }

    @Test("Old, admired, never made")
    func findsTheGap() {
        let id = UUID()
        let found = AspirationGapDetector.identify(
            recipes: [candidate(id, savedDaysAgo: 120)],
            viewsByRecipe: [id: 3],
            now: now
        )

        #expect(found == [id])
    }

    @Test("Saved and forgotten is not the same as saved and wanted")
    func ignoresUnviewed() {
        // Nobody has looked at it since importing. That is clutter, not an
        // aspiration, and reading a preference out of silence would be
        // inventing one.
        let id = UUID()
        let found = AspirationGapDetector.identify(
            recipes: [candidate(id, savedDaysAgo: 120)],
            viewsByRecipe: [id: 1],
            now: now
        )

        #expect(found.isEmpty)
    }

    @Test("Something cooked is not an aspiration, however long ago it was saved")
    func ignoresCooked() {
        let id = UUID()
        let found = AspirationGapDetector.identify(
            recipes: [candidate(id, savedDaysAgo: 300, cooked: true)],
            viewsByRecipe: [id: 9],
            now: now
        )

        #expect(found.isEmpty)
    }

    @Test("A recent save has not had its chance yet")
    func ignoresRecentSaves() {
        let id = UUID()
        let found = AspirationGapDetector.identify(
            recipes: [candidate(id, savedDaysAgo: 30)],
            viewsByRecipe: [id: 5],
            now: now
        )

        #expect(found.isEmpty)
    }
}

// MARK: - The simulation harness (§12)

@Suite("Archetype simulation")
@MainActor
struct ProfileArchetypeTests {

    private let now = Fixture.now

    /// Six months of synthetic cooking, generated deterministically.
    private func history(
        recipes: [ProfileInput.RecipeFacts],
        cooksPerRecipe: [UUID: Int],
        weekday: Int,
        hour: Int,
        overDays: Double = 180
    ) -> ProfileInput {
        var signals: [ProfileInput.SignalFacts] = []
        let context = SignalContext(weekday: weekday, hour: hour, season: .spring)

        for recipe in recipes {
            let count = cooksPerRecipe[recipe.id] ?? 0
            guard count > 0 else { continue }

            for index in 0..<count {
                // Spread evenly back through the window, oldest first, so the
                // first cook is never dated after its own repeats.
                let age = overDays * Double(count - index) / Double(count + 1)
                signals.append(.init(
                    kind: index == 0 ? .cooked : .cookedRepeat,
                    recipeID: recipe.id,
                    timestamp: now.addingTimeInterval(-age * 86_400),
                    context: context
                ))
            }
        }

        return ProfileInput(recipes: recipes, signals: signals, now: now)
    }

    private func quick(_ name: String, _ cuisine: String, minutes: Int) -> ProfileInput.RecipeFacts {
        ProfileInput.RecipeFacts(
            id: UUID(),
            title: name,
            cuisine: cuisine,
            ingredients: ["chicken", "rice", "garlic"],
            techniques: ["stir-frying"],
            totalMinutes: minutes,
            servings: 2
        )
    }

    @Test("The weeknight-quick cook reads as a weeknight-quick cook")
    func weeknightCook() {
        let recipes = (0..<8).map { quick("Quick \($0)", "thai", minutes: 25) }
        let counts = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, 4) })

        let profile = TasteProfileBuilder.build(
            from: history(recipes: recipes, cooksPerRecipe: counts, weekday: 3, hour: 18)
        )

        #expect(profile.typicalMinutes(onWeekday: 3) <= 30)
        #expect(profile.isUsable)
        #expect(profile.cookHoursByWeekday[3]?.contains(18) == true)
        #expect(profile.topCuisines().first?.name == "thai")
    }

    @Test("The ambitious weekend baker reads as one")
    func weekendBaker() {
        let bakes = (0..<6).map { index in
            ProfileInput.RecipeFacts(
                id: UUID(),
                title: "Big bake \(index)",
                cuisine: "french",
                ingredients: ["flour", "butter", "yeast", "chocolate"],
                techniques: ["baking", "proving", "laminating"],
                equipmentMentioned: ["stand mixer"],
                totalMinutes: 240,
                servings: 8
            )
        }
        let counts = Dictionary(uniqueKeysWithValues: bakes.map { ($0.id, 2) })

        let profile = TasteProfileBuilder.build(
            from: history(recipes: bakes, cooksPerRecipe: counts, weekday: 1, hour: 10)
        )

        #expect(profile.typicalMinutes(onWeekday: 1) >= 180)
        #expect(profile.inferredEquipment.contains("stand mixer"))
        #expect(profile.comfortableTechniques().map(\.name).contains("proving"))
        #expect(profile.inferredHouseholdSize == 8)
    }

    @Test("The narrow-rotation cook reads as low novelty, and the varied one high")
    func noveltySeparatesTheTwo() {
        // Same three dishes, over and over.
        let rotation = (0..<3).map { quick("Usual \($0)", "italian", minutes: 30) }
        let rotationCounts = Dictionary(uniqueKeysWithValues: rotation.map { ($0.id, 8) })
        let narrow = TasteProfileBuilder.build(
            from: history(recipes: rotation, cooksPerRecipe: rotationCounts, weekday: 4, hour: 19, overDays: 80)
        )

        // A different cuisine every time, nothing repeated.
        let cuisines = ["thai", "italian", "mexican", "indian", "japanese", "greek", "korean", "french"]
        let varied = cuisines.map { quick("New \($0)", $0, minutes: 40) }
        let variedCounts = Dictionary(uniqueKeysWithValues: varied.map { ($0.id, 1) })
        let broad = TasteProfileBuilder.build(
            from: history(recipes: varied, cooksPerRecipe: variedCounts, weekday: 4, hour: 19, overDays: 80)
        )

        #expect(narrow.noveltyAppetite < 0.4, "eight repeats of three dishes is a rotation")
        #expect(broad.noveltyAppetite > 0.8, "eight cuisines and no repeats is an appetite for variety")
        #expect(narrow.noveltyAppetite < broad.noveltyAppetite)
    }

    @Test("Filter-bubble check: variety in, variety out")
    func varietySurvivesDerivation() {
        // §10 names the filter bubble as the default failure and asks for
        // distinct-cuisines-per-month to be watched. If a varied cook comes
        // out of the builder looking narrow, the recommendations will narrow
        // too, and this is where that shows up first.
        let cuisines = ["thai", "italian", "mexican", "indian", "japanese"]
        let recipes = cuisines.map { quick("Dish \($0)", $0, minutes: 35) }
        let counts = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, 3) })

        let profile = TasteProfileBuilder.build(
            from: history(recipes: recipes, cooksPerRecipe: counts, weekday: 5, hour: 19)
        )

        let liked = profile.cuisineAffinity.filter { $0.value > 0.3 }
        #expect(liked.count == cuisines.count, "all five cuisines should register, not just the alphabetical first")
    }
}
