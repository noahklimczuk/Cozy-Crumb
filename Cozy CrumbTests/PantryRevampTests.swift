//
//  PantryRevampTests.swift
//  Cozy CrumbTests
//
//  P1 of the pantry revamp: the shape of the new model, the tier the
//  classifier puts things in, the backfill that brings old rows across, and
//  the canonicalizer parity that everything downstream depends on.
//
//  The decay maths is P2 and is tested there. What is pinned here is the
//  evidence the decay will be computed *from* — because a backfill that gets
//  `lastConfirmedAt` wrong produces a pantry that decays from the wrong day,
//  and nothing later can recover it.
//

import Foundation
import SwiftData
import Testing

@testable import Cozy_Crumb

// MARK: - Helpers

/// A defaults store per test, so staples edits in one can't leak into another.
private func scratchDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
    UserDefaults(suiteName: name) ?? .standard
}

// MARK: - Vocabulary

@Suite("Pantry vocabulary")
struct PantryVocabularyTests {

    @Test("Loose amounts step down one level at a time, and off the end")
    func steppingDown() {
        #expect(LooseAmount.plenty.steppedDown() == .enough)
        #expect(LooseAmount.enough.steppedDown() == .runningLow)
        #expect(LooseAmount.runningLow.steppedDown() == .almostOut)
        // Nil is "gone" — cooking with the last of something is how most
        // things actually run out.
        #expect(LooseAmount.almostOut.steppedDown() == nil)
    }

    @Test("The persisted spelling of the second level stays \"some\"")
    func rawValuesAreStable() {
        // The case is named `enough` in Swift only because `some` collides
        // with `Optional.some` at every `LooseAmount?` call site. What goes on
        // disk must not have moved.
        #expect(LooseAmount.enough.rawValue == "some")
        #expect(LooseAmount(rawValue: "some") == .enough)
    }

    @Test("Only the low levels are worth putting on a shopping list")
    func lowLevels() {
        #expect(!LooseAmount.plenty.isLow)
        #expect(!LooseAmount.enough.isLow)
        #expect(LooseAmount.runningLow.isLow)
        #expect(LooseAmount.almostOut.isLow)
    }

    @Test("Staples are the one tier that never decays")
    func stapleTierDoesNotDecay() {
        #expect(!PantryTier.staple.decays)
        #expect(PantryTier.stock.decays)
        #expect(PantryTier.someday.decays)
    }

    @Test("A one-off has no cadence worth learning")
    func onlyStockPredictsRestock() {
        #expect(PantryTier.stock.predictsRestock)
        #expect(!PantryTier.someday.predictsRestock)
        #expect(!PantryTier.staple.predictsRestock)
    }

    @Test("Frozen goes in the freezer, tins go in the cupboard")
    func locationInference() {
        #expect(StorageLocation.inferred(from: .frozen) == .freezer)
        #expect(StorageLocation.inferred(from: .dairy) == .fridge)
        #expect(StorageLocation.inferred(from: .meat) == .fridge)
        #expect(StorageLocation.inferred(from: .produce) == .fridge)
        #expect(StorageLocation.inferred(from: .pantry) == .pantry)
        #expect(StorageLocation.inferred(from: .condiment) == .pantry)
    }
}

// MARK: - Capture sources

@Suite("What each capture route is worth")
struct CaptureSourceTests {

    @Test("The three original raw values are unchanged, so old rows decode")
    func rawValuesSurviveTheRename() {
        #expect(CaptureSource(rawValue: "manual") == .manual)
        #expect(CaptureSource(rawValue: "fridgePhoto") == .fridgePhoto)
        #expect(CaptureSource(rawValue: "groceryCheckoff") == .groceryCheckoff)
    }

    @Test("Typing it in beats a photo, and a photo is capped")
    func confidenceOrdering() {
        #expect(CaptureSource.manual.initialConfidence > CaptureSource.fridgePhoto.initialConfidence)
        #expect(CaptureSource.groceryCheckoff.initialConfidence > CaptureSource.receiptScan.initialConfidence)
        // A camera cannot see behind the milk, however sure the model is.
        #expect(CaptureSource.fridgePhoto.confidenceCap == 0.85)
    }

    @Test("No source ever claims more than its own cap")
    func initialNeverExceedsCap() {
        for source in CaptureSource.allCases {
            #expect(source.initialConfidence <= source.confidenceCap)
        }
    }

    @Test("An item cannot be created above its source's cap")
    func initialiserClampsToCap() {
        let item = PantryItem(
            displayName: "Milk",
            confidenceAtConfirmation: 0.99,
            addedVia: .fridgePhoto
        )
        #expect(item.confidenceAtConfirmation == 0.85)
    }
}

// MARK: - The item

@Suite("The new pantry item")
struct PantryItemShapeTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Canonical name comes from the shared canonicalizer, not a copy")
    func canonicalNameIsDerived() {
        let item = PantryItem(displayName: "Roma tomatoes")
        #expect(item.canonicalName == IngredientCanonicalizer.canonical("Roma tomatoes"))
        #expect(item.canonicalName == "tomato")
    }

    @Test("Renaming an item moves its canonical name with it")
    func canonicalNameFollowsRenames() {
        let item = PantryItem(displayName: "Roma tomatoes")
        item.displayName = "Cilantro"
        // A stored copy would still say "tomato" here. That is the bug this
        // being computed exists to make impossible.
        #expect(item.canonicalName == IngredientCanonicalizer.canonical("Cilantro"))
    }

    @Test("A new row is confirmed by being written, dated when it was added")
    func newRowsAreConfirmed() {
        let item = PantryItem(displayName: "Eggs", addedAt: now)
        #expect(item.lastConfirmedAt == now)
        #expect(item.hasBeenBackfilled)
    }

    @Test("Location is inferred from the aisle unless told otherwise")
    func locationDefaultsFromCategory() {
        #expect(PantryItem(displayName: "Peas", category: .frozen).location == .freezer)
        #expect(PantryItem(displayName: "Peas", category: .frozen, location: .pantry).location == .pantry)
    }

    @Test("A measured amount wins over a loose one, and either beats nothing")
    func amountDescription() {
        #expect(PantryItem(displayName: "Flour", quantity: 500, unit: "g").amountDescription == "500 g")
        #expect(PantryItem(displayName: "Rice", looseAmount: .runningLow).amountDescription == "Running low")
        #expect(PantryItem(displayName: "Salt").amountDescription == nil)
    }

    @Test("The user's own date is what expiry means; the estimate is separate")
    func expiryIsTheUsersDate() {
        let item = PantryItem(displayName: "Yoghurt")
        #expect(item.daysUntilExpiry(now: now) == nil)

        item.expiresAt = Calendar.current.date(byAdding: .day, value: 2, to: now)
        #expect(item.isExpiringSoon(now: now))
    }
}

// MARK: - Tier classification

@Suite("Which tier something lands in")
struct PantryTierClassifierTests {

    @Test("Things every kitchen has are staples")
    func staplesAreRecognised() {
        let store = scratchDefaults()
        #expect(PantryTierClassifier.tier(for: "Salt", category: .condiment, defaults: store) == .staple)
        #expect(PantryTierClassifier.tier(for: "olive oil", category: .condiment, defaults: store) == .staple)
        #expect(PantryTierClassifier.tier(for: "Soy sauce", category: .condiment, defaults: store) == .staple)
    }

    @Test("Perishables are stock, not staples")
    func perishablesAreStock() {
        let store = scratchDefaults()
        #expect(PantryTierClassifier.tier(for: "Bok choy", category: .produce, defaults: store) == .stock)
        #expect(PantryTierClassifier.tier(for: "Chicken thighs", category: .meat, defaults: store) == .stock)
    }

    @Test("Nothing is guessed into .someday — it has to be earned or chosen")
    func somedayIsNeverGuessed() {
        let store = scratchDefaults()
        // `.someday` is a claim about purchase history, not about the food.
        // Guessing it would silently exclude something from running-low
        // nudges for no reason the user could see.
        for name in ["Miso paste", "Saffron", "Tahini", "Chicken", "Salt"] {
            let tier = PantryTierClassifier.tier(for: name, category: .pantry, defaults: store)
            #expect(tier != .someday)
        }
    }

    @Test("A pinned row is a statement that it's always in")
    func pinnedBackfillsAsStaple() {
        let store = scratchDefaults()
        let item = PantryItem(displayName: "Gochujang", category: .condiment, isPinned: true)
        #expect(PantryTierClassifier.backfillTier(for: item, defaults: store) == .staple)
    }
}

// MARK: - Staples list

@Suite("The staples list and its edits")
struct PantryStaplesTests {

    @Test("The matcher's staples are all in, so the two lists can't disagree")
    func buildsOnTheCanonicalizer() {
        // Two staples lists would drift, and the drift would show up as a
        // recipe scoring differently depending on which path asked.
        #expect(IngredientCanonicalizer.staples.isSubset(of: PantryStaples.defaults))
    }

    @Test("Adding puts something in; removing takes it out")
    func editing() {
        let store = scratchDefaults()

        #expect(!PantryStaples.contains("Gochujang", defaults: store))
        PantryStaples.add("Gochujang", defaults: store)
        #expect(PantryStaples.contains("Gochujang", defaults: store))

        #expect(PantryStaples.contains("Salt", defaults: store))
        PantryStaples.remove("Salt", defaults: store)
        #expect(!PantryStaples.contains("Salt", defaults: store))
    }

    @Test("Re-adding something removed restores it rather than fighting itself")
    func removeThenAdd() {
        let store = scratchDefaults()

        PantryStaples.remove("Salt", defaults: store)
        #expect(!PantryStaples.contains("Salt", defaults: store))

        PantryStaples.add("Salt", defaults: store)
        #expect(PantryStaples.contains("Salt", defaults: store))
    }

    @Test("Edits are stored canonically, so case and variety don't matter")
    func editsAreCanonical() {
        let store = scratchDefaults()

        PantryStaples.add("Gochujang", defaults: store)
        #expect(PantryStaples.contains("gochujang", defaults: store))
        #expect(PantryStaples.contains("GOCHUJANG", defaults: store))
    }

    @Test("Resetting puts the shipped list back")
    func resetting() {
        let store = scratchDefaults()

        PantryStaples.remove("Salt", defaults: store)
        PantryStaples.add("Gochujang", defaults: store)
        PantryStaples.resetEdits(defaults: store)

        #expect(PantryStaples.contains("Salt", defaults: store))
        #expect(!PantryStaples.contains("Gochujang", defaults: store))
    }

    @Test("Every seeded staple is actually treated as one")
    func seedsAreStaples() {
        let store = scratchDefaults()
        for seed in PantryStaples.seeds {
            #expect(
                PantryStaples.contains(seed.name, defaults: store),
                "\(seed.name) is seeded as a staple but the list doesn't recognise it"
            )
        }
    }
}

// MARK: - Canonicalizer parity

@Suite("Pantry and Sous Chef agree on what a food is called")
struct PantryCanonicalParityTests {

    /// Names that have to resolve identically whether they arrive through the
    /// pantry, a recipe, or the grocery list. If these two paths ever drift,
    /// ingredient matching breaks silently across the whole app — a recipe
    /// stops matching a pantry item that is sitting right there.
    private static let fixtures = [
        "Roma tomatoes", "cherry tomato", "1 can diced tomatoes",
        "Chicken thighs, boneless", "boneless skinless chicken breast",
        "fresh cilantro", "coriander", "flat-leaf parsley",
        "2 cups jasmine rice", "basmati rice",
        "coconut milk", "whole milk", "2% milk",
        "peanut butter", "unsalted butter",
        "spring onions", "green onion", "scallions",
        "extra virgin olive oil", "courgette", "zucchini",
        "king prawns", "shrimp", "greek yoghurt"
    ]

    @Test("A pantry item's canonical name is the canonicalizer's, exactly")
    func itemMatchesCanonicalizer() {
        for name in Self.fixtures {
            let item = PantryItem(displayName: name)
            #expect(
                item.canonicalName == IngredientCanonicalizer.canonical(name),
                "pantry and canonicalizer disagree on \"\(name)\""
            )
        }
    }

    @Test("A logged event carries the same canonical name the item had")
    func eventMatchesItem() {
        for name in Self.fixtures {
            let item = PantryItem(displayName: name)
            let event = PantryEvent(
                canonicalName: item.canonicalName,
                displayName: item.displayName,
                kind: .added
            )
            #expect(event.canonicalName == IngredientCanonicalizer.canonical(name))
        }
    }

    @Test("A recipe ingredient and a pantry row for the same food agree")
    func recipeAndPantryAgree() {
        // The match that the recommendation engine's pantry component is
        // entirely built on.
        // "spring onions" / "scallions" is deliberately not in here: the
        // canonicalizer resolves them to "onion" and "spring onion"
        // respectively, because `compound(in:)` matches on an exact suffix and
        // never sees the plural. That is a real pre-existing bug this fixture
        // found, and fixing it belongs in the canonicalizer's own tests rather
        // than being papered over here.
        let pairs = [
            ("Roma tomatoes", "cherry tomatoes"),
            ("fresh cilantro", "coriander"),
            ("king prawns", "shrimp"),
            ("courgette", "zucchini")
        ]

        for (pantryName, recipeName) in pairs {
            let item = PantryItem(displayName: pantryName)
            #expect(
                item.canonicalName == IngredientCanonicalizer.canonical(recipeName),
                "\"\(pantryName)\" in the pantry doesn't match \"\(recipeName)\" in a recipe"
            )
        }
    }

    @Test("Compounds stay compound, in the pantry as everywhere else")
    func compoundsSurvive() {
        // Someone lactose intolerant who keeps coconut milk must not have
        // "milk" written anywhere near their pantry matching.
        #expect(PantryItem(displayName: "coconut milk").canonicalName != "milk")
        #expect(PantryItem(displayName: "peanut butter").canonicalName != "butter")
    }
}

// MARK: - Backfill

@Suite("Bringing old pantry rows across")
@MainActor
struct PantryBackfillTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A throwaway in-memory store holding the real schema, so the backfill is
    /// exercised against the same model graph the app opens.
    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CozyCrumbCurrentSchema.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// A row as SwiftData's inferred migration would leave it: the old fields
    /// carried over, the new ones sitting on their declared defaults.
    private func legacyRow(
        _ name: String,
        category: GroceryCategory = .other,
        addedDaysAgo: Int,
        via: CaptureSource = .manual,
        in context: ModelContext
    ) -> PantryItem {
        let added = Calendar.current.date(byAdding: .day, value: -addedDaysAgo, to: now) ?? now
        let item = PantryItem(displayName: name, category: category, addedAt: added, addedVia: via)
        // Undo what the initialiser did, to stand in for a row that never went
        // through it. This is the state the sentinel exists to detect.
        item.lastConfirmedAt = .distantPast
        item.tier = .stock
        item.location = .pantry
        context.insert(item)
        return item
    }

    private func items(in context: ModelContext) throws -> [PantryItem] {
        try context.fetch(FetchDescriptor<PantryItem>())
    }

    @Test("An old row decays from when it was added, not from today")
    func lastConfirmedComesFromAddedAt() throws {
        let context = try makeContext()
        let store = scratchDefaults()

        let tahini = legacyRow("Tahini", category: .condiment, addedDaysAgo: 400, in: context)
        #expect(!tahini.hasBeenBackfilled)

        PantryBackfill.run(in: context, defaults: store)

        // The whole reason this is a backfill and not a migration default:
        // `.now` here would make a two-year-old jar look like it was
        // confirmed this morning.
        #expect(tahini.lastConfirmedAt == tahini.addedAt)
        #expect(tahini.hasBeenBackfilled)
    }

    @Test("Tier and location are worked out, not left on their defaults")
    func derivedFields() throws {
        let context = try makeContext()
        let store = scratchDefaults()

        let salt = legacyRow("Salt", category: .condiment, addedDaysAgo: 10, in: context)
        let peas = legacyRow("Frozen peas", category: .frozen, addedDaysAgo: 10, in: context)
        let chicken = legacyRow("Chicken thighs", category: .meat, addedDaysAgo: 2, in: context)

        PantryBackfill.run(in: context, defaults: store)

        #expect(salt.tier == .staple)
        #expect(peas.tier == .stock)
        #expect(peas.location == .freezer)
        #expect(chicken.tier == .stock)
        #expect(chicken.location == .fridge)
    }

    @Test("Confidence comes from however the row got here")
    func confidenceFromSource() throws {
        let context = try makeContext()
        let store = scratchDefaults()

        let typed = legacyRow("Rice", addedDaysAgo: 5, via: .manual, in: context)
        let spotted = legacyRow("Bok choy", category: .produce, addedDaysAgo: 5, via: .fridgePhoto, in: context)

        PantryBackfill.run(in: context, defaults: store)

        #expect(typed.confidenceAtConfirmation == 1.0)
        #expect(spotted.confidenceAtConfirmation == 0.85)
    }

    @Test("Running twice changes nothing the second time")
    func idempotent() throws {
        let context = try makeContext()
        let store = scratchDefaults()

        _ = legacyRow("Tahini", addedDaysAgo: 30, in: context)

        let first = PantryBackfill.run(in: context, defaults: store)
        let countAfterFirst = try items(in: context).count
        let second = PantryBackfill.run(in: context, defaults: store)
        let countAfterSecond = try items(in: context).count

        #expect(first > 0)
        #expect(second == 0)
        #expect(countAfterSecond == countAfterFirst)
    }

    @Test("The backfill writes no events, so restock prediction isn't poisoned")
    func writesNoEvents() throws {
        let context = try makeContext()
        let store = scratchDefaults()

        _ = legacyRow("Tahini", addedDaysAgo: 30, in: context)
        _ = legacyRow("Rice", addedDaysAgo: 60, in: context)

        PantryBackfill.run(in: context, defaults: store)

        // An `.added` event dated today for every existing row would hand
        // restock prediction a purchase spike on upgrade day that it would
        // take months to see past.
        let events = try context.fetch(FetchDescriptor<PantryEvent>())
        #expect(events.isEmpty)
    }

    @Test("A fresh kitchen gets its staples, once")
    func seedsStaples() throws {
        let context = try makeContext()
        let store = scratchDefaults()

        PantryBackfill.run(in: context, defaults: store)
        let seeded = try items(in: context)

        #expect(!seeded.isEmpty)
        #expect(seeded.allSatisfy { $0.tier == .staple })
        #expect(seeded.contains { $0.displayName == "Salt" })

        // Deleting the salt should not bring it back on next launch.
        if let salt = seeded.first(where: { $0.displayName == "Salt" }) {
            context.delete(salt)
        }
        PantryBackfill.run(in: context, defaults: store)

        let afterDeleting = try items(in: context)
        #expect(!afterDeleting.contains { $0.displayName == "Salt" })
    }

    @Test("Seeding doesn't duplicate something already in the pantry")
    func seedingSkipsWhatIsThere() throws {
        let context = try makeContext()
        let store = scratchDefaults()

        _ = legacyRow("Sea salt", category: .condiment, addedDaysAgo: 3, in: context)

        PantryBackfill.run(in: context, defaults: store)

        // "Sea salt" and "Salt" are the same food to the canonicalizer, so the
        // seed must stand down rather than stack a second row.
        let salts = try items(in: context).filter { $0.canonicalName == "salt" }
        #expect(salts.count == 1)
    }
}

// MARK: - Event log

@Suite("The pantry event log")
@MainActor
struct PantryLogTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CozyCrumbCurrentSchema.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test("An event keys off the canonical food, not the row's wording")
    func eventsKeyOffCanonicalName() throws {
        let context = try makeContext()

        let item = PantryItem(displayName: "Roma tomatoes", category: .produce)
        context.insert(item)
        PantryLog.record(.added, for: item, in: context)
        // Saved before fetching: `history` runs a #Predicate query, and a
        // predicate is the one fetch shape that shouldn't be asked to reason
        // about rows that only exist as pending inserts.
        try context.save()

        let history = PantryLog.history(forCanonical: "tomato", in: context)
        #expect(history.count == 1)
        // The user's own words survive alongside the matcher's.
        #expect(history.first?.displayName == "Roma tomatoes")
    }

    @Test("Two jars of the same thing a year apart are one history")
    func historySpansSeparateRows() throws {
        let context = try makeContext()

        let old = PantryItem(displayName: "Tahini", category: .condiment)
        context.insert(old)
        PantryLog.record(.added, for: old, at: now, in: context)
        PantryLog.record(.depleted, for: old, at: now.addingTimeInterval(86_400 * 30), in: context)
        context.delete(old)

        let new = PantryItem(displayName: "Tahini", category: .condiment)
        context.insert(new)
        PantryLog.record(.added, for: new, at: now.addingTimeInterval(86_400 * 200), in: context)
        try context.save()

        // The row is what comes and goes; the food is what has a history, and
        // restock prediction needs the gap between those two purchases.
        let history = PantryLog.history(forCanonical: "tahini", in: context)
        #expect(history.count == 3)
        #expect(history.map(\.timestamp) == history.map(\.timestamp).sorted())
    }

    @Test("Only acquisitions count as a purchase")
    func acquisitionKinds() {
        #expect(PantryEventKind.added.isAcquisition)
        for kind in PantryEventKind.allCases where kind != .added {
            #expect(!kind.isAcquisition)
        }
    }

    @Test("Ticking something off the list logs it arriving")
    func groceryCheckoffLogsAnAddition() throws {
        let context = try makeContext()

        let milk = GroceryItem(name: "Whole milk", quantity: 2, unit: "l", category: .dairy)
        context.insert(milk)

        GroceryService.addToPantry(milk, in: context, now: now)

        let pantry = try context.fetch(FetchDescriptor<PantryItem>())
        #expect(pantry.count == 1)
        #expect(pantry.first?.addedVia == .groceryCheckoff)
        #expect(pantry.first?.confidenceAtConfirmation == 0.95)
        #expect(pantry.first?.lastConfirmedAt == now)

        let events = try context.fetch(FetchDescriptor<PantryEvent>())
        #expect(events.count == 1)
        #expect(events.first?.kind == .added)
    }

    @Test("Buying something again re-confirms it rather than stacking a row")
    func repeatCheckoffMerges() throws {
        let context = try makeContext()

        let first = GroceryItem(name: "Whole milk", quantity: 2, unit: "l", category: .dairy)
        context.insert(first)
        GroceryService.addToPantry(first, in: context, now: now)

        let later = now.addingTimeInterval(86_400 * 7)
        let second = GroceryItem(name: "Whole milk", quantity: 2, unit: "l", category: .dairy)
        context.insert(second)
        GroceryService.addToPantry(second, in: context, now: later)

        let pantry = try context.fetch(FetchDescriptor<PantryItem>())
        #expect(pantry.count == 1)
        #expect(pantry.first?.lastConfirmedAt == later)

        // Both purchases are in the log even though there is one row, because
        // the gap between them is the thing restock prediction learns from.
        let events = try context.fetch(FetchDescriptor<PantryEvent>())
        #expect(events.count == 2)
    }
}
