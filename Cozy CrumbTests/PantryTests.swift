//
//  PantryTests.swift
//  Cozy CrumbTests
//
//  Two things worth pinning down: what a fridge photo is allowed to turn into,
//  and the expiry maths the "use me soon" section is built on.
//

import Foundation
import Testing

@testable import Cozy_Crumb

@Suite("Reading a fridge photo")
struct FridgePhotoReaderTests {

    private func spotted(_ items: [(String, Double?, Double)]) -> AISpottedPantry {
        AISpottedPantry(items: items.map { name, quantity, confidence in
            AISpottedItem(name: name, quantity: quantity, unit: nil, confidence: confidence)
        })
    }

    @Test("Items come back sorted with the surest first")
    func sortsByConfidence() {
        let items = FridgePhotoReader.convert(spotted([
            ("mustard", nil, 0.3),
            ("milk", 1, 0.95),
            ("peppers", 3, 0.7)
        ]))

        #expect(items.map(\.displayName) == ["milk", "peppers", "mustard"])
    }

    @Test("The unsure ones are kept, flagged rather than dropped")
    func keepsLowConfidence() throws {
        let items = FridgePhotoReader.convert(spotted([("mustard", nil, 0.34)]))

        let item = try #require(items.first)
        #expect(!item.isConfident)
        #expect(item.name == "mustard")
    }

    @Test("The same thing seen twice becomes one row")
    func foldsDuplicates() throws {
        let items = FridgePhotoReader.convert(spotted([
            ("carrots", 3, 0.8),
            ("carrot", 2, 0.6)
        ]))

        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.quantity == 5)
        // The surer sighting sets the confidence.
        #expect(item.confidence == 0.8)
    }

    @Test("Nameless rows are thrown away rather than shown as blanks")
    func dropsEmptyNames() {
        let items = FridgePhotoReader.convert(spotted([("", 1, 0.9), ("   ", nil, 0.9)]))
        #expect(items.isEmpty)
    }

    @Test("Aisles are worked out here, not asked of the model")
    func guessesCategory() throws {
        let items = FridgePhotoReader.convert(spotted([("milk", 1, 0.9)]))
        #expect(try #require(items.first).category == .dairy)
    }

    @Test("Confidence outside 0–1 is clamped rather than trusted")
    func clampsConfidence() throws {
        let items = FridgePhotoReader.convert(spotted([("milk", nil, 4.2), ("eggs", nil, -1)]))

        #expect(items.allSatisfy { (0...1).contains($0.confidence) })
        #expect(try #require(items.first).confidence == 1)
    }

    @Test("An empty photo yields an empty pantry, not a plausible one")
    func handlesNothingSeen() {
        #expect(FridgePhotoReader.convert(AISpottedPantry(items: [])).isEmpty)
    }
}

@Suite("Use-by dates")
struct PantryExpiryTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(name: String, expiringInDays days: Int?) -> PantryItem {
        PantryItem(
            displayName: name,
            expiresAt: days.map { Calendar.current.date(byAdding: .day, value: $0, to: now) ?? now }
        )
    }

    @Test("Three days out or less counts as soon")
    func expiringSoon() {
        #expect(item(name: "Yoghurt", expiringInDays: 1).isExpiringSoon(now: now))
        #expect(item(name: "Cream", expiringInDays: 3).isExpiringSoon(now: now))
        #expect(!item(name: "Cheese", expiringInDays: 9).isExpiringSoon(now: now))
    }

    @Test("Something already off is still shown, not hidden")
    func expired() {
        let old = item(name: "Milk", expiringInDays: -2)

        #expect(old.isExpired(now: now))
        // Expired implies expiring-soon, so it surfaces in the same section
        // rather than being quietly filed under dairy.
        #expect(old.isExpiringSoon(now: now))
    }

    @Test("No date means no fuss")
    func noDate() {
        let tin = item(name: "Chickpeas", expiringInDays: nil)

        #expect(tin.daysUntilExpiry(now: now) == nil)
        #expect(!tin.isExpiringSoon(now: now))
        #expect(!tin.isExpired(now: now))
    }
}

@Suite("Pantry sections")
@MainActor
struct PantryGroupingTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ name: String, _ category: GroceryCategory, expiringInDays days: Int? = nil) -> PantryItem {
        PantryItem(
            displayName: name,
            category: category,
            expiresAt: days.map { Calendar.current.date(byAdding: .day, value: $0, to: now) ?? now }
        )
    }

    @Test("Anything going off leads, whatever aisle it's from")
    func expiringComesFirst() throws {
        let model = PantryViewModel()

        let groups = model.groups(
            from: [
                item("Chickpeas", .pantry),
                item("Yoghurt", .dairy, expiringInDays: 1)
            ],
            now: now
        )

        #expect(groups.first?.section == .expiring)
        #expect(try #require(groups.first).items.map(\.displayName) == ["Yoghurt"])
    }

    @Test("An expiring item isn't also listed under its aisle")
    func noDoubleCounting() {
        let model = PantryViewModel()

        let groups = model.groups(
            from: [item("Yoghurt", .dairy, expiringInDays: 1)],
            now: now
        )

        #expect(groups.count == 1)
        #expect(groups.first?.section == .expiring)
    }

    @Test("The rest walk the shop in aisle order")
    func aisleOrder() {
        let model = PantryViewModel()

        let groups = model.groups(
            from: [item("Bread", .bakery), item("Carrots", .produce), item("Milk", .dairy)],
            now: now
        )

        let orders = groups.compactMap { group -> Int? in
            guard case .category(let category) = group.section else { return nil }
            return category.sortOrder
        }

        #expect(orders == orders.sorted())
    }

    @Test("Soonest to go off is at the top of the pile")
    func soonestFirst() {
        let model = PantryViewModel()

        let groups = model.groups(
            from: [
                item("Cream", .dairy, expiringInDays: 3),
                item("Milk", .dairy, expiringInDays: -1),
                item("Yoghurt", .dairy, expiringInDays: 1)
            ],
            now: now
        )

        #expect(groups.first?.items.map(\.displayName) == ["Milk", "Yoghurt", "Cream"])
    }
}
