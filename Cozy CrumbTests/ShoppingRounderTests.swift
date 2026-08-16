//
//  ShoppingRounderTests.swift
//  Cozy CrumbTests
//
//  Rounding a shopping amount the wrong way sends someone home short, so the
//  ladder and the always-up rule are pinned down here.
//

import Testing

@testable import Cozy_Crumb

@Suite("Shopping quantities")
struct ShoppingRounderTests {

    private func expectClose(
        _ actual: Double?,
        _ expected: Double,
        tolerance: Double = 0.001,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let actual else {
            Issue.record("expected \(expected), got nil", sourceLocation: sourceLocation)
            return
        }
        #expect(abs(actual - expected) < tolerance, sourceLocation: sourceLocation)
    }

    // MARK: - Counts

    @Test("You can't buy a fraction of an onion")
    func wholeCounts() {
        let rounded = ShoppingRounder.round(quantity: 1.4, unit: nil)
        expectClose(rounded.quantity, 2)
        #expect(rounded.unit == nil)
        #expect(rounded.wasRounded)
    }

    @Test("Count units round up too")
    func countUnits() {
        expectClose(ShoppingRounder.round(quantity: 2.5, unit: "clove").quantity, 3)
        expectClose(ShoppingRounder.round(quantity: 1.1, unit: "can").quantity, 2)
        expectClose(ShoppingRounder.round(quantity: 0.5, unit: "bunch").quantity, 1)
    }

    @Test("A whole count is left alone and not flagged as rounded")
    func alreadyWhole() {
        let rounded = ShoppingRounder.round(quantity: 3, unit: nil)
        expectClose(rounded.quantity, 3)
        #expect(!rounded.wasRounded)
    }

    // MARK: - Mass

    @Test("375 g of flour is a 400 g bag")
    func flour() {
        let rounded = ShoppingRounder.round(quantity: 375, unit: "g")
        expectClose(rounded.quantity, 400)
        #expect(rounded.unit == "g")
        #expect(rounded.wasRounded)
    }

    @Test("Amounts land on sizes shops actually sell")
    func packLadder() {
        expectClose(ShoppingRounder.round(quantity: 8, unit: "g").quantity, 10)
        expectClose(ShoppingRounder.round(quantity: 110, unit: "g").quantity, 125)
        expectClose(ShoppingRounder.round(quantity: 260, unit: "g").quantity, 300)
        expectClose(ShoppingRounder.round(quantity: 520, unit: "g").quantity, 600)
        expectClose(ShoppingRounder.round(quantity: 700, unit: "g").quantity, 750)
    }

    @Test("A kilo's worth is shown as a kilo, not a thousand grams")
    func promotesAtAKilo() {
        let rounded = ShoppingRounder.round(quantity: 900, unit: "g")
        expectClose(rounded.quantity, 1)
        #expect(rounded.unit == "kg")
    }

    @Test("An amount already on the ladder doesn't move")
    func exactPackSize() {
        let rounded = ShoppingRounder.round(quantity: 500, unit: "g")
        expectClose(rounded.quantity, 500)
        #expect(!rounded.wasRounded)
    }

    @Test("Past a kilo it switches to kilos in quarter steps")
    func kilos() {
        let rounded = ShoppingRounder.round(quantity: 1100, unit: "g")
        expectClose(rounded.quantity, 1.25)
        #expect(rounded.unit == "kg")
    }

    @Test("Kilogram input stays in kilograms")
    func kilogramInput() {
        let rounded = ShoppingRounder.round(quantity: 1.1, unit: "kg")
        expectClose(rounded.quantity, 1.25)
        #expect(rounded.unit == "kg")
    }

    // MARK: - Volume

    @Test("Millilitres use the same ladder")
    func millilitres() {
        expectClose(ShoppingRounder.round(quantity: 300, unit: "ml").quantity, 300)
        expectClose(ShoppingRounder.round(quantity: 320, unit: "ml").quantity, 400)
    }

    @Test("Past a litre it switches to litres")
    func litres() {
        let rounded = ShoppingRounder.round(quantity: 1200, unit: "ml")
        expectClose(rounded.quantity, 1.25)
        #expect(rounded.unit == "l")
    }

    // MARK: - Left alone

    @Test("Spoons are measured out of a jar, not bought by the spoonful")
    func measuringUnits() {
        let rounded = ShoppingRounder.round(quantity: 1.5, unit: "tbsp")
        expectClose(rounded.quantity, 1.5)
        #expect(!rounded.wasRounded)
    }

    @Test("Cups round to a quarter")
    func cups() {
        expectClose(ShoppingRounder.round(quantity: 1.1, unit: "cup").quantity, 1.25)
    }

    @Test("Imperial mass rounds on its own steps")
    func imperial() {
        expectClose(ShoppingRounder.round(quantity: 3.2, unit: "oz").quantity, 4)
        expectClose(ShoppingRounder.round(quantity: 1.1, unit: "lb").quantity, 1.25)
    }

    @Test("Nothing to round when there's no amount")
    func noQuantity() {
        let rounded = ShoppingRounder.round(quantity: nil, unit: nil)
        #expect(rounded.quantity == nil)
        #expect(!rounded.wasRounded)
    }

    @Test("An unrecognised unit passes straight through")
    func unknownUnit() {
        let rounded = ShoppingRounder.round(quantity: 1.3, unit: "sprig")
        expectClose(rounded.quantity, 1.3)
        #expect(rounded.unit == "sprig")
        #expect(!rounded.wasRounded)
    }

    // MARK: - Whole lists

    @Test("Rounding a list keeps every other field intact")
    func roundedList() {
        let lines = [
            GroceryLineItem(name: "flour", quantity: 375, unit: "g", category: .pantry, sourceRecipeTitles: ["Bread"])
        ]

        let rounded = ShoppingRounder.rounded(lines)

        #expect(rounded.count == 1)
        expectClose(rounded[0].quantity, 400)
        #expect(rounded[0].name == "flour")
        #expect(rounded[0].category == .pantry)
        #expect(rounded[0].sourceRecipeTitles == ["Bread"])
    }

    @Test("Rounding never happens before merging")
    func mergeThenRound() {
        // Two 60 g additions are 120 g of flour, not two 75 g bags.
        let merged = GroceryMerge.folded([
            GroceryLineItem(name: "flour", quantity: 60, unit: "g"),
            GroceryLineItem(name: "flour", quantity: 60, unit: "g")
        ])

        expectClose(merged[0].quantity, 120)
        expectClose(ShoppingRounder.rounded(merged)[0].quantity, 125)
    }
}
