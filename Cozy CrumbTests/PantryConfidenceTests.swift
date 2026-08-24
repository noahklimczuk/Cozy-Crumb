//
//  PantryConfidenceTests.swift
//  Cozy CrumbTests
//
//  P2: the decay engine, the bands, and archival.
//
//  The point of these is that confidence is a pure function of stored evidence
//  and a date you pass in. That is what lets three months of a kitchen's life
//  run in a millisecond, and §14 asks for exactly that — a seeded pantry that
//  decays correctly over simulated time, checked at the band boundaries rather
//  than only in the middle where everything is obviously fine.
//

import Foundation
import SwiftData
import Testing

@testable import Cozy_Crumb

// MARK: - Shared fixtures

private let epoch = Date(timeIntervalSince1970: 1_800_000_000)

private func days(_ count: Double, after start: Date = epoch) -> Date {
    start.addingTimeInterval(count * 86_400)
}

private func evidence(
    _ name: String,
    category: GroceryCategory = .other,
    strength: Double = 1.0,
    confirmedDaysAgo: Double = 0,
    expiresAt: Date? = nil,
    neverDecays: Bool = false
) -> PantryEvidence {
    PantryEvidence(
        canonicalName: IngredientCanonicalizer.canonical(name),
        category: category,
        strength: strength,
        confirmedAt: days(-confirmedDaysAgo),
        expiresAt: expiresAt,
        neverDecays: neverDecays
    )
}

// MARK: - The maths

@Suite("Confidence decays by half-life")
struct PantryDecayMathTests {

    @Test("One half-life halves it, two quarters it")
    func halvesOnSchedule() {
        // Pantry goods: 90-day half-life.
        let fresh = evidence("rice", category: .pantry, confirmedDaysAgo: 0)
        let oneHalfLife = evidence("rice", category: .pantry, confirmedDaysAgo: 90)
        let twoHalfLives = evidence("rice", category: .pantry, confirmedDaysAgo: 180)

        #expect(abs(PantryConfidence.confidence(of: fresh, at: epoch) - 1.0) < 0.001)
        #expect(abs(PantryConfidence.confidence(of: oneHalfLife, at: epoch) - 0.5) < 0.001)
        #expect(abs(PantryConfidence.confidence(of: twoHalfLives, at: epoch) - 0.25) < 0.001)
    }

    @Test("Weaker evidence starts lower and stays proportionally lower")
    func strengthScales() {
        let photo = evidence("rice", category: .pantry, strength: 0.85, confirmedDaysAgo: 90)
        let typed = evidence("rice", category: .pantry, strength: 1.0, confirmedDaysAgo: 90)

        #expect(abs(PantryConfidence.confidence(of: photo, at: epoch) - 0.425) < 0.001)
        #expect(PantryConfidence.confidence(of: photo, at: epoch)
                < PantryConfidence.confidence(of: typed, at: epoch))
    }

    @Test("Nothing ever goes below zero or above one")
    func staysInRange() {
        let ancient = evidence("cilantro", category: .produce, confirmedDaysAgo: 3650)
        let impossible = evidence("rice", category: .pantry, strength: 5)

        #expect(PantryConfidence.confidence(of: ancient, at: epoch) >= 0)
        #expect(PantryConfidence.confidence(of: impossible, at: epoch) <= 1)
    }

    @Test("A confirmation dated in the future doesn't inflate anything")
    func futureConfirmationIsClamped() {
        // Clock skew, or a backdated import gone wrong. Days elapsed floors at
        // zero rather than going negative and pushing confidence above its
        // strength.
        let ahead = evidence("rice", category: .pantry, strength: 0.9, confirmedDaysAgo: -30)
        #expect(PantryConfidence.confidence(of: ahead, at: epoch) <= 0.9)
    }

    @Test("Staples and pinned rows do not decay at all")
    func staplesNeverDecay() {
        let salt = evidence("salt", category: .condiment, confirmedDaysAgo: 3650, neverDecays: true)

        #expect(PantryConfidence.confidence(of: salt, at: epoch) == 1)
        #expect(PantryConfidence.band(of: salt, at: epoch) == .confident)
        // Nobody should ever be asked whether they still have salt.
        #expect(PantryConfidence.date(whenConfidenceFallsBelow: 0.5, for: salt) == nil)
    }
}

// MARK: - Half-lives

@Suite("How long each food stays believable")
struct PantryHalfLifeTests {

    @Test("The spec's category table is what's in force")
    func categoryTable() {
        #expect(PantryConfidence.halfLifeDays(for: .produce) == 10)
        #expect(PantryConfidence.halfLifeDays(for: .dairy) == 8)
        #expect(PantryConfidence.halfLifeDays(for: .meat) == 8)
        #expect(PantryConfidence.halfLifeDays(for: .bakery) == 6)
        #expect(PantryConfidence.halfLifeDays(for: .frozen) == 60)
        #expect(PantryConfidence.halfLifeDays(for: .pantry) == 90)
        #expect(PantryConfidence.halfLifeDays(for: .condiment) == 90)
    }

    @Test("Herbs and leaves go faster than the aisle they came from")
    func herbsBeatTheirCategory() {
        // Both produce. One is a puddle in five days, the other is fine in a
        // month, and a single category constant cannot say that.
        let herbs = PantryConfidence.halfLifeDays(forCanonical: "cilantro", category: .produce)
        let roots = PantryConfidence.halfLifeDays(forCanonical: "onion", category: .produce)

        #expect(herbs == 5)
        #expect(roots == 30)
        #expect(herbs < PantryConfidence.halfLifeDays(for: .produce))
        #expect(roots > PantryConfidence.halfLifeDays(for: .produce))
    }

    @Test("Every override is keyed by a canonical name, not a display one")
    func overridesAreCanonical() {
        // A key the canonicalizer would never produce is a key that never
        // matches, and it would fail silently as "this food uses its category".
        for key in PantryConfidence.overrides.keys {
            #expect(
                IngredientCanonicalizer.canonical(key) == key,
                "override key \"\(key)\" is not canonical — it would never be hit"
            )
        }
    }

    @Test("An unknown food falls back to its aisle")
    func unknownFallsBack() {
        let unknown = PantryConfidence.halfLifeDays(forCanonical: "zzzznotafood", category: .bakery)
        #expect(unknown == PantryConfidence.halfLifeDays(for: .bakery))
    }
}

// MARK: - Bands

@Suite("What a confidence figure means")
struct PantryBandTests {

    @Test("The four bands sit where the spec puts them")
    func thresholds() {
        #expect(PantryConfidence.band(for: 1.0) == .confident)
        #expect(PantryConfidence.band(for: 0.8) == .confident)
        #expect(PantryConfidence.band(for: 0.79) == .probable)
        #expect(PantryConfidence.band(for: 0.5) == .probable)
        #expect(PantryConfidence.band(for: 0.49) == .doubtful)
        #expect(PantryConfidence.band(for: 0.25) == .doubtful)
        #expect(PantryConfidence.band(for: 0.24) == .lapsed)
        #expect(PantryConfidence.band(for: 0) == .lapsed)
    }

    @Test("Only confident and probable get planned around")
    func whatCountsForRecipes() {
        #expect(PantryConfidenceBand.confident.countsTowardsRecipes)
        #expect(PantryConfidenceBand.probable.countsTowardsRecipes)
        #expect(!PantryConfidenceBand.doubtful.countsTowardsRecipes)
        #expect(!PantryConfidenceBand.lapsed.countsTowardsRecipes)
    }

    @Test("Bands order from least sure to most")
    func ordering() {
        #expect(PantryConfidenceBand.lapsed < .doubtful)
        #expect(PantryConfidenceBand.doubtful < .probable)
        #expect(PantryConfidenceBand.probable < .confident)
    }

    @Test("Every band says itself in words, for VoiceOver")
    func spokenDescriptions() {
        // §9: confidence is conveyed by opacity AND a ring AND words. Never
        // the visual alone.
        for band in PantryConfidenceBand.allCases {
            #expect(!band.spokenDescription.isEmpty)
            #expect(!band.digestHeading.isEmpty)
        }
    }
}

// MARK: - The user's own date

@Suite("A date off the package outranks the estimate")
struct PantryExpiryConfidenceTests {

    @Test("Past its date, the app stops counting on it")
    func pastDate() {
        let yogurt = evidence(
            "yogurt",
            category: .dairy,
            confirmedDaysAgo: 1,
            expiresAt: days(-1)
        )

        // One day old dairy would otherwise be ~0.93.
        #expect(PantryConfidence.confidence(of: yogurt, at: epoch) <= PantryConfidence.doubtfulFloor)
    }

    @Test("It drops to doubtful, not to gone")
    func expiryDoesNotDelete() {
        let yogurt = evidence("yogurt", category: .dairy, confirmedDaysAgo: 1, expiresAt: days(-1))

        // The app describes and estimates; it never decides food is bad. The
        // sweep asks, the user answers.
        #expect(PantryConfidence.band(of: yogurt, at: epoch) == .doubtful)
    }

    @Test("A date still in the future changes nothing")
    func futureDateIsInert() {
        let withDate = evidence("yogurt", category: .dairy, confirmedDaysAgo: 1, expiresAt: days(5))
        let without = evidence("yogurt", category: .dairy, confirmedDaysAgo: 1)

        #expect(PantryConfidence.confidence(of: withDate, at: epoch)
                == PantryConfidence.confidence(of: without, at: epoch))
    }
}

// MARK: - Simulated time

@Suite("A pantry decaying over three months")
struct PantrySimulatedTimeTests {

    @Test("Each food crosses the bands in the right order and at the right time")
    func bandCrossings() {
        // Confirmed once, then left alone. This is the whole failure mode the
        // feature exists for: week one you enter everything, week five the app
        // is confidently planning around food that is long gone.
        let cases: [(name: String, category: GroceryCategory, stillProbableAt: Double, lapsedBy: Double)] = [
            ("cilantro", .produce, 4, 15),
            ("chicken", .meat, 7, 24),
            ("bread", .bakery, 5, 18),
            ("peas", .frozen, 50, 180),
            ("rice", .pantry, 80, 270)
        ]

        for item in cases {
            let e = evidence(item.name, category: item.category)

            let early = PantryConfidence.band(of: e, at: days(item.stillProbableAt))
            #expect(
                early.countsTowardsRecipes,
                "\(item.name) should still be worth planning around at day \(item.stillProbableAt)"
            )

            let late = PantryConfidence.band(of: e, at: days(item.lapsedBy))
            #expect(
                late == .lapsed,
                "\(item.name) should have lapsed by day \(item.lapsedBy)"
            )
        }
    }

    @Test("Confidence only ever falls, until something confirms it")
    func monotonicUntilConfirmed() {
        let e = evidence("chicken", category: .meat)

        var previous = 1.1
        for day in stride(from: 0.0, through: 90.0, by: 3.0) {
            let value = PantryConfidence.confidence(of: e, at: days(day))
            #expect(value <= previous, "confidence rose on its own at day \(day)")
            previous = value
        }
    }

    @Test("The engine can say when something will need asking about")
    func predictsCrossings() {
        let e = evidence("rice", category: .pantry)

        let crossing = PantryConfidence.date(whenConfidenceFallsBelow: 0.5, for: e)
        let expected = days(90)

        // One half-life, to the hour.
        #expect(crossing != nil)
        #expect(abs((crossing ?? epoch).timeIntervalSince(expected)) < 3600)
    }
}

// MARK: - Archival

@Suite("Lapsed rows are put away, never deleted")
@MainActor
struct PantryArchivalTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CozyCrumbCurrentSchema.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Inserts and saves. The save matters: everything in `PantryDecay` reads
    /// through a `#Predicate` fetch, and a predicate is the one fetch shape
    /// that shouldn't be asked to reason about rows which only exist as
    /// pending inserts.
    @discardableResult
    private func item(
        _ name: String,
        category: GroceryCategory = .produce,
        confirmedDaysAgo: Double,
        tier: PantryTier = .stock,
        in context: ModelContext
    ) throws -> PantryItem {
        let row = PantryItem(
            displayName: name,
            category: category,
            tier: tier,
            lastConfirmedAt: days(-confirmedDaysAgo),
            addedAt: days(-confirmedDaysAgo),
            addedVia: .manual
        )
        context.insert(row)
        try context.save()
        return row
    }

    @Test("Something long past is archived rather than removed")
    func archivesRatherThanDeletes() throws {
        let context = try makeContext()
        let cilantro = try item("Cilantro", confirmedDaysAgo: 60, in: context)

        let archived = PantryDecay.archiveLapsed(in: context, now: epoch)

        #expect(archived == 1)
        #expect(cilantro.isArchived)

        // The row is still there. Deleting it would take its history with it,
        // and that history is what restock prediction is built on.
        let all = try context.fetch(FetchDescriptor<PantryItem>())
        #expect(all.count == 1)
    }

    @Test("An archived row is recoverable, with its evidence intact")
    func restorable() throws {
        let context = try makeContext()
        let cilantro = try item("Cilantro", confirmedDaysAgo: 60, in: context)
        PantryDecay.archiveLapsed(in: context, now: epoch)

        PantryDecay.restore(cilantro, at: epoch, in: context)

        #expect(!cilantro.isArchived)
        #expect(cilantro.lastConfirmedAt == epoch)
        #expect(cilantro.band(at: epoch) == .confident)
    }

    @Test("Active reads exclude the archive; archived reads find it")
    func activeExcludesArchived() throws {
        let context = try makeContext()
        try item("Cilantro", confirmedDaysAgo: 60, in: context)
        try item("Rice", category: .pantry, confirmedDaysAgo: 3, in: context)

        PantryDecay.archiveLapsed(in: context, now: epoch)

        let active = PantryDecay.activeItems(in: context)
        let archived = PantryDecay.archivedItems(in: context)

        #expect(active.map(\.displayName) == ["Rice"])
        #expect(archived.map(\.displayName) == ["Cilantro"])
    }

    @Test("Staples are never swept away, however long it's been")
    func staplesSurvive() throws {
        let context = try makeContext()
        let salt = try item("Salt", category: .condiment, confirmedDaysAgo: 900, tier: .staple, in: context)

        let archived = PantryDecay.archiveLapsed(in: context, now: epoch)

        #expect(archived == 0)
        #expect(!salt.isArchived)
    }

    @Test("A pinned row survives too, whatever its tier")
    func pinnedSurvives() throws {
        let context = try makeContext()
        let gochujang = try item("Gochujang", category: .condiment, confirmedDaysAgo: 900, in: context)
        gochujang.isPinned = true

        PantryDecay.archiveLapsed(in: context, now: epoch)

        #expect(!gochujang.isArchived)
    }

    @Test("Sweeping twice archives nothing the second time")
    func idempotent() throws {
        let context = try makeContext()
        try item("Cilantro", confirmedDaysAgo: 60, in: context)

        let first = PantryDecay.archiveLapsed(in: context, now: epoch)
        let second = PantryDecay.archiveLapsed(in: context, now: epoch)

        #expect(first == 1)
        #expect(second == 0)
    }

    @Test("Archiving writes one event, so the history says why it went")
    func archivalIsLogged() throws {
        let context = try makeContext()
        try item("Cilantro", confirmedDaysAgo: 60, in: context)

        PantryDecay.archiveLapsed(in: context, now: epoch)

        let events = try context.fetch(FetchDescriptor<PantryEvent>())
        #expect(events.count == 1)
        // An item that vanished either got cooked, got ticked off, got swept
        // away, or decayed out — four different bugs, and this is how you tell.
        #expect(events.first?.kind == .expired)
    }

    @Test("The sweep asks about doubtful rows, least sure first, capped")
    func reconciliationQueue() throws {
        let context = try makeContext()
        // Doubtful for produce (10-day half-life) is roughly days 10 to 20.
        try item("Peppers", confirmedDaysAgo: 12, in: context)
        try item("Courgette", confirmedDaysAgo: 18, in: context)
        try item("Rice", category: .pantry, confirmedDaysAgo: 2, in: context)

        let queue = PantryDecay.needingReconciliation(in: context, now: epoch, limit: 12)

        #expect(queue.allSatisfy { $0.band(at: epoch) == .doubtful })
        #expect(!queue.contains { $0.displayName == "Rice" }, "a confident row has nothing to ask about")
        if queue.count > 1 {
            #expect(queue[0].confidence(at: epoch) <= queue[1].confidence(at: epoch))
        }
    }

    @Test("Confirming puts it back to full and resets the clock")
    func confirming() throws {
        let context = try makeContext()
        let peppers = try item("Peppers", confirmedDaysAgo: 12, in: context)
        #expect(peppers.band(at: epoch) == .doubtful)

        PantryDecay.confirm(peppers, at: epoch, in: context)

        #expect(peppers.confidence(at: epoch) == 1)
        #expect(peppers.band(at: epoch) == .confident)
    }

    @Test("A weak signal can't talk down a strong one")
    func confirmationTakesTheStronger() throws {
        let context = try makeContext()
        let milk = try item("Milk", category: .dairy, confirmedDaysAgo: 0, in: context)

        // Typed in this morning; then a fridge photo half-sees it.
        milk.confirm(at: epoch, strength: CaptureSource.fridgePhoto.initialConfidence)

        #expect(milk.confidenceAtConfirmation == 1.0)
    }

    @Test("Used-up archives rather than deletes")
    func useUpArchives() throws {
        let context = try makeContext()
        let tahini = try item("Tahini", category: .condiment, confirmedDaysAgo: 1, in: context)

        PantryDecay.markGone(tahini, at: epoch, in: context)

        #expect(tahini.isArchived)
        let all = try context.fetch(FetchDescriptor<PantryItem>())
        #expect(all.count == 1)

        let events = try context.fetch(FetchDescriptor<PantryEvent>())
        #expect(events.first?.kind == .depleted)
    }
}

// MARK: - Confidence reaches the recommender

@Suite("A doubtful ingredient doesn't win a recipe")
struct PantryConfidenceInRecommendationsTests {

    private let tuesday = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(_ name: String, category: GroceryCategory, daysOld: Double) -> PantryEntry {
        PantryEntry(
            name: name,
            category: category,
            lastConfirmedAt: tuesday.addingTimeInterval(-daysOld * 86_400)
        )
    }

    @Test("Fresh ingredients score above stale ones for the same recipe")
    func confidenceWeightsTheMatch() {
        // §14: a recipe whose key ingredient is only doubtful must score below
        // one whose ingredients are all confident.
        let ingredients: Set<String> = ["chicken", "spinach"]

        let freshMatch = RecommendationEngine.pantryMatch(
            CandidateRecipe(id: UUID(), title: "Wilted spinach chicken", ingredients: ingredients),
            in: RecommendationContext(
                pantry: [entry("chicken", category: .meat, daysOld: 1),
                         entry("spinach", category: .produce, daysOld: 1)],
                date: tuesday
            )
        )

        let staleMatch = RecommendationEngine.pantryMatch(
            CandidateRecipe(id: UUID(), title: "Wilted spinach chicken", ingredients: ingredients),
            in: RecommendationContext(
                pantry: [entry("chicken", category: .meat, daysOld: 1),
                         entry("spinach", category: .produce, daysOld: 18)],
                date: tuesday
            )
        )

        #expect(freshMatch.score > staleMatch.score)
        #expect(freshMatch.have.contains("spinach"))
        // Below the probable band it stops counting as "have" at all — it is
        // still in the pantry, the sweep will ask, but no meal is planned
        // around it.
        #expect(!staleMatch.have.contains("spinach"))
        #expect(staleMatch.missing.contains { $0.name == "spinach" })
    }
}
