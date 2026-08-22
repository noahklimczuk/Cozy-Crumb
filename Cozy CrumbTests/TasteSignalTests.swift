//
//  TasteSignalTests.swift
//  Cozy CrumbTests
//
//  S1 of the Sous Chef spec: the raw learning log.
//
//  The weight table is asserted value by value rather than by some property
//  like "positive signals are positive". Those numbers are the tuning of the
//  whole system, and the point of pinning them is that changing one should be
//  a deliberate act with a failing test attached, not something that drifts.
//

import Foundation
import SwiftData
import Testing

@testable import Cozy_Crumb

@Suite("Signal weights")
struct SignalWeightTests {

    @Test("The table matches the spec, kind by kind")
    func weightTable() {
        #expect(SignalKind.cookedRepeat.baseWeight == 3.0)
        #expect(SignalKind.cooked.baseWeight == 2.0)
        #expect(SignalKind.ratedHigh.baseWeight == 1.8)
        #expect(SignalKind.addedToCollection.baseWeight == 1.2)
        #expect(SignalKind.groceryPurchased.baseWeight == 1.0)
        #expect(SignalKind.favorited.baseWeight == 0.8)
        #expect(SignalKind.imported.baseWeight == 0.5)
        #expect(SignalKind.viewedLong.baseWeight == 0.4)
        #expect(SignalKind.viewed.baseWeight == 0.1)

        #expect(SignalKind.savedButNeverCooked.baseWeight == -0.6)
        #expect(SignalKind.dismissedRecommendation.baseWeight == -1.0)
        #expect(SignalKind.abandonedMidCook.baseWeight == -1.2)
        #expect(SignalKind.ingredientRemovedFromGrocery.baseWeight == -1.5)
        #expect(SignalKind.ratedLow.baseWeight == -2.0)
        #expect(SignalKind.explicitlyDisliked.baseWeight == -4.0)
    }

    @Test("Cooking something twice outranks every other positive")
    func repeatCookIsStrongest() {
        let others = SignalKind.allCases
            .filter { $0 != .cookedRepeat }
            .map(\.baseWeight)

        #expect(SignalKind.cookedRepeat.baseWeight > others.max()!)
    }

    @Test("Saying you hate something outranks every other negative")
    func dislikeIsStrongest() {
        let others = SignalKind.allCases
            .filter { $0 != .explicitlyDisliked }
            .map(\.baseWeight)

        #expect(SignalKind.explicitlyDisliked.baseWeight < others.min()!)
    }

    @Test("Only browsing counts as incidental")
    func incidentalKinds() {
        let incidental = SignalKind.allCases.filter(\.isIncidental)
        #expect(Set(incidental) == Set([.viewed, .searched]))
    }

    @Test("A signal freezes the weight of its kind at logging time")
    func weightIsFrozenFromKind() {
        let signal = TasteSignal(kind: .cooked)
        #expect(signal.weight == 2.0)

        // An explicit weight wins, which is what lets a seeded fixture or a
        // future retune write history deliberately.
        let overridden = TasteSignal(kind: .cooked, weight: 1.25)
        #expect(overridden.weight == 1.25)
    }
}

@Suite("Signal decay")
struct SignalDecayTests {

    private let epsilon = 0.000_001

    @Test("Nothing has faded today")
    func freshIsFull() {
        #expect(SignalDecay.factor(daysAgo: 0) == 1)
    }

    @Test("The half-life halves it, and keeps halving")
    func halvesEveryHalfLife() {
        #expect(abs(SignalDecay.factor(daysAgo: 180) - 0.5) < epsilon)
        #expect(abs(SignalDecay.factor(daysAgo: 360) - 0.25) < epsilon)
        #expect(abs(SignalDecay.factor(daysAgo: 540) - 0.125) < epsilon)
    }

    @Test("A future timestamp is treated as fresh, never amplified")
    func futureIsClamped() {
        // A restored backup or a clock change can produce one of these. The
        // failure to guard against would be silent: pow(0.5, negative) is
        // greater than 1, so one bad row could outweigh a year of real ones.
        #expect(SignalDecay.factor(daysAgo: -400) == 1)
    }

    @Test("Weight decays with age")
    func effectiveWeightFalls() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sixMonthsAgo = now.addingTimeInterval(-180 * 86_400)

        let signal = TasteSignal(kind: .cooked, timestamp: sixMonthsAgo)

        #expect(abs(signal.effectiveWeight(at: now) - 1.0) < epsilon)
    }

    @Test("A stated dislike never fades")
    func dislikeDoesNotDecay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let twoYearsAgo = now.addingTimeInterval(-730 * 86_400)

        let signal = TasteSignal(kind: .explicitlyDisliked, timestamp: twoYearsAgo)

        #expect(signal.effectiveWeight(at: now) == -4.0)
        #expect(!SignalKind.explicitlyDisliked.decays)
    }

    @Test("Everything else does fade")
    func everythingElseDecays() {
        let decaying = SignalKind.allCases.filter(\.decays)
        #expect(decaying.count == SignalKind.allCases.count - 1)
    }
}

@Suite("Signal context")
struct SignalContextTests {

    @Test("Months map to northern-hemisphere seasons")
    func seasons() {
        #expect(SignalContext.season(forMonth: 12) == .winter)
        #expect(SignalContext.season(forMonth: 1) == .winter)
        #expect(SignalContext.season(forMonth: 2) == .winter)
        #expect(SignalContext.season(forMonth: 3) == .spring)
        #expect(SignalContext.season(forMonth: 5) == .spring)
        #expect(SignalContext.season(forMonth: 6) == .summer)
        #expect(SignalContext.season(forMonth: 8) == .summer)
        #expect(SignalContext.season(forMonth: 9) == .autumn)
        #expect(SignalContext.season(forMonth: 11) == .autumn)
    }

    @Test("Every month lands somewhere")
    func everyMonthCovered() {
        for month in 1...12 {
            _ = SignalContext.season(forMonth: month)
        }
    }

    @Test("A date is read as weekday, hour and season")
    func stampsADate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Toronto"))

        // Tuesday 4 February 2025, 18:30 local.
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2025, month: 2, day: 4, hour: 18, minute: 30
        )
        let date = try #require(components.date)

        let context = SignalContext(date: date, calendar: calendar)

        #expect(context.weekday == 3)         // 1 = Sunday, so 3 = Tuesday
        #expect(context.weekdayName == "Tue")
        #expect(context.hour == 18)
        #expect(context.season == .winter)
    }

    @Test("An out-of-range weekday does not crash the label")
    func weekdayNameIsSafe() {
        let context = SignalContext(weekday: 0, hour: 9, season: .spring)
        #expect(context.weekdayName == "?")
    }
}

// MARK: - Store-backed

@Suite("Signal logging")
@MainActor
struct SignalLogTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A throwaway in-memory store holding the real schema, so the logger is
    /// exercised against the same model graph the app opens.
    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CozyCrumbCurrentSchema.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func signals(in context: ModelContext) throws -> [TasteSignal] {
        try context.fetch(FetchDescriptor<TasteSignal>())
    }

    private func makeRecipe(in context: ModelContext, title: String = "Thai basil chicken") -> Recipe {
        let recipe = Recipe(title: title)
        context.insert(recipe)
        return recipe
    }

    @Test("A first cook is a cook; a second is a repeat")
    func cookedThenRepeated() throws {
        let context = try makeContext()
        let recipe = makeRecipe(in: context)

        SignalLog.cooked(recipe, priorCookCount: 0, rating: nil, in: context, now: now)
        SignalLog.cooked(recipe, priorCookCount: 1, rating: nil, in: context, now: now)

        let kinds = try signals(in: context).map(\.kind)
        #expect(kinds.contains(.cooked))
        #expect(kinds.contains(.cookedRepeat))
        #expect(kinds.count == 2)
    }

    @Test("Ratings become their own signal, but only at the ends of the scale")
    func ratingSignals() throws {
        let context = try makeContext()
        let recipe = makeRecipe(in: context)

        SignalLog.cooked(recipe, priorCookCount: 0, rating: 5, in: context, now: now)
        SignalLog.cooked(recipe, priorCookCount: 1, rating: 3, in: context, now: now)
        SignalLog.cooked(recipe, priorCookCount: 2, rating: 1, in: context, now: now)

        let kinds = try signals(in: context).map(\.kind)
        #expect(kinds.filter { $0 == .ratedHigh }.count == 1)
        #expect(kinds.filter { $0 == .ratedLow }.count == 1)
        // The 3 is a shrug and writes nothing beyond the cook itself.
        #expect(kinds.filter { $0 == .cooked || $0 == .cookedRepeat }.count == 3)
        #expect(kinds.count == 5)
    }

    @Test("Un-favouriting is housekeeping, not a rejection")
    func unfavouritingIsSilent() throws {
        let context = try makeContext()
        let recipe = makeRecipe(in: context)

        SignalLog.favorited(recipe, isNowFavorite: true, in: context)
        SignalLog.favorited(recipe, isNowFavorite: false, in: context)

        let kinds = try signals(in: context).map(\.kind)
        #expect(kinds == [.favorited])
    }

    @Test("Opening the same recipe again within the hour logs once")
    func incidentalSignalsCoalesce() throws {
        let context = try makeContext()
        let recipe = makeRecipe(in: context)

        SignalLog.log(.viewed, recipeID: recipe.id, in: context, now: now)
        SignalLog.log(.viewed, recipeID: recipe.id, in: context, now: now.addingTimeInterval(60))
        SignalLog.log(.viewed, recipeID: recipe.id, in: context, now: now.addingTimeInterval(1_800))

        #expect(try signals(in: context).count == 1)
    }

    @Test("Past the window it counts as fresh interest again")
    func coalescingExpires() throws {
        let context = try makeContext()
        let recipe = makeRecipe(in: context)

        SignalLog.log(.viewed, recipeID: recipe.id, in: context, now: now)
        SignalLog.log(
            .viewed,
            recipeID: recipe.id,
            in: context,
            now: now.addingTimeInterval(SignalLog.coalescingWindow + 1)
        )

        #expect(try signals(in: context).count == 2)
    }

    @Test("Different recipes never coalesce into each other")
    func coalescingIsPerTarget() throws {
        let context = try makeContext()
        let first = makeRecipe(in: context, title: "Carbonara")
        let second = makeRecipe(in: context, title: "Sheet pan salmon")

        SignalLog.log(.viewed, recipeID: first.id, in: context, now: now)
        SignalLog.log(.viewed, recipeID: second.id, in: context, now: now)

        #expect(try signals(in: context).count == 2)
    }

    @Test("Cooking twice in an hour is two cooks, not one")
    func deliberateSignalsNeverCoalesce() throws {
        let context = try makeContext()
        let recipe = makeRecipe(in: context)

        SignalLog.log(.cooked, recipeID: recipe.id, in: context, now: now)
        SignalLog.log(.cooked, recipeID: recipe.id, in: context, now: now.addingTimeInterval(60))

        #expect(try signals(in: context).count == 2)
    }

    @Test("Ingredient names are lowercased and trimmed on the way in")
    func normalisesIngredientNames() throws {
        let context = try makeContext()

        let signal = SignalLog.log(
            .groceryPurchased,
            ingredientName: "  Fish Sauce  ",
            in: context,
            now: now
        )

        #expect(signal?.ingredientName == "fish sauce")
    }

    @Test("Every signal is stamped with when it happened")
    func stampsContext() throws {
        let context = try makeContext()
        let recipe = makeRecipe(in: context)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Toronto"))

        let signal = try #require(
            SignalLog.log(.cooked, recipeID: recipe.id, in: context, now: now, calendar: calendar)
        )

        let stamped = try #require(signal.context)
        #expect(stamped == SignalContext(date: now, calendar: calendar))
    }

    @Test("Too short a search is not a search")
    func shortSearchesAreIgnored() throws {
        let context = try makeContext()

        SignalLog.searched("ch", in: context)
        SignalLog.searched("  ", in: context)
        SignalLog.searched("harissa", in: context)

        let logged = try signals(in: context)
        #expect(logged.count == 1)
        #expect(logged.first?.ingredientName == "harissa")
    }
}

@Suite("Signal retention")
@MainActor
struct SignalRetentionTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CozyCrumbCurrentSchema.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func insert(
        _ kind: SignalKind,
        daysAgo: Double,
        into context: ModelContext
    ) {
        context.insert(
            TasteSignal(kind: kind, timestamp: now.addingTimeInterval(-daysAgo * 86_400))
        )
    }

    @Test("Spent browsing is dropped")
    func dropsOldIncidental() throws {
        let context = try makeContext()
        insert(.viewed, daysAgo: 200, into: context)
        insert(.searched, daysAgo: 400, into: context)

        #expect(SignalRetention.prune(in: context, now: now) == 2)
        #expect(try context.fetch(FetchDescriptor<TasteSignal>()).isEmpty)
    }

    @Test("Recent browsing is kept")
    func keepsRecentIncidental() throws {
        let context = try makeContext()
        insert(.viewed, daysAgo: 10, into: context)

        #expect(SignalRetention.prune(in: context, now: now) == 0)
        #expect(try context.fetch(FetchDescriptor<TasteSignal>()).count == 1)
    }

    @Test("An old cook is still an old cook, and stays")
    func neverDropsDeliberateSignals() throws {
        let context = try makeContext()
        insert(.cooked, daysAgo: 900, into: context)
        insert(.ratedHigh, daysAgo: 900, into: context)
        insert(.explicitlyDisliked, daysAgo: 900, into: context)
        insert(.ratedLow, daysAgo: 900, into: context)

        #expect(SignalRetention.prune(in: context, now: now) == 0)
        #expect(try context.fetch(FetchDescriptor<TasteSignal>()).count == 4)
    }

    @Test("Pruning runs once a day at most")
    func runsAtMostDaily() throws {
        let context = try makeContext()
        let defaults = try #require(UserDefaults(suiteName: "retention.\(UUID().uuidString)"))
        defer { defaults.removeObject(forKey: CozyDefaultsKey.lastSignalPruneAt) }

        insert(.viewed, daysAgo: 400, into: context)
        #expect(SignalRetention.runIfDue(in: context, defaults: defaults, now: now) == 1)

        insert(.viewed, daysAgo: 400, into: context)
        #expect(SignalRetention.runIfDue(in: context, defaults: defaults, now: now) == 0)

        // A day later it is due again.
        let tomorrow = now.addingTimeInterval(SignalRetention.minimumInterval + 1)
        #expect(SignalRetention.runIfDue(in: context, defaults: defaults, now: tomorrow) == 1)
    }
}
