//
//  GroceryConsolidationTests.swift
//  Cozy CrumbTests
//
//  The rules that decide whether a week of recipes becomes one shop or a list
//  with three onions on it.
//
//  The interesting cases are the ones where merging would be *wrong*: a
//  shopping list with a duplicate row is untidy, but a list that merged
//  ground beef into beef is incorrect, and incorrect is worse.
//

import Foundation
import Testing

@testable import Cozy_Crumb

@Suite("Ingredient names that mean the same shop")
struct GroceryNameNormalisationTests {

    private func key(_ name: String) -> String {
        GroceryMerge.normalizedName(name)
    }

    @Test("Preparation words don't change what you buy")
    func stripsPreparation() {
        #expect(key("chopped onion") == key("onion"))
        #expect(key("finely diced onions") == key("onion"))
        #expect(key("grated parmesan") == key("parmesan"))
        #expect(key("crushed garlic") == key("garlic"))
        #expect(key("peeled potatoes") == key("potato"))
    }

    @Test("Neither does the size of it")
    func stripsSize() {
        #expect(key("large onion") == key("onion"))
        #expect(key("2 medium carrots".replacingOccurrences(of: "2 ", with: "")) == key("carrot"))
        #expect(key("ripe bananas") == key("banana"))
        #expect(key("fresh basil") == key("basil"))
    }

    @Test("Words that change the product are left alone")
    func keepsMeaningfulWords() {
        #expect(key("ground beef") != key("beef"))
        #expect(key("dried basil") != key("basil"))
        #expect(key("smoked paprika") != key("paprika"))
        #expect(key("unsalted butter") != key("butter"))
        #expect(key("whole milk") != key("milk"))
    }

    @Test("A preparation word on its own is still a thing you buy")
    func doesNotEmptyTheName() {
        #expect(key("fresh") == "fresh")
        #expect(!key("chopped").isEmpty)
    }

    @Test("Plurals and articles still normalise as they did")
    func keepsExistingBehaviour() {
        #expect(key("Tomatoes") == key("tomato"))
        #expect(key("the eggs") == key("egg"))
        #expect(key("sweet potatoes") == key("sweet potato"))
        #expect(key("asparagus") == "asparagus")
    }
}

@Suite("Folding a week into one shop")
struct GroceryFoldingTests {

    @Test("The same thing from three recipes becomes one line")
    func addsUpAcrossRecipes() throws {
        let folded = GroceryMerge.folded([
            GroceryLineItem(name: "Olive oil", quantity: 2, unit: "tbsp", sourceRecipeTitles: ["Curry"]),
            GroceryLineItem(name: "olive oil", quantity: 1, unit: "tbsp", sourceRecipeTitles: ["Bolognese"]),
            GroceryLineItem(name: "Olive Oil", quantity: 3, unit: "tbsp", sourceRecipeTitles: ["Salmon"])
        ])

        #expect(folded.count == 1)
        let line = try #require(folded.first)
        #expect(line.quantity == 6)
        #expect(line.unit == "tbsp")
        // Every recipe that wanted it is remembered, so the row can say so.
        #expect(line.sourceRecipeTitles == ["Curry", "Bolognese", "Salmon"])
    }

    @Test("Differently written onions land on one row")
    func mergesPhrasings() throws {
        let folded = GroceryMerge.folded([
            GroceryLineItem(name: "Onion", quantity: 2, unit: nil),
            GroceryLineItem(name: "chopped onions", quantity: 1, unit: nil),
            GroceryLineItem(name: "1 large onion".replacingOccurrences(of: "1 ", with: ""), quantity: 1, unit: nil)
        ])

        #expect(folded.count == 1)
        #expect(folded.first?.quantity == 4)
    }

    @Test("Compatible units are converted before adding")
    func convertsUnits() throws {
        let folded = GroceryMerge.folded([
            GroceryLineItem(name: "Flour", quantity: 500, unit: "g"),
            GroceryLineItem(name: "flour", quantity: 0.5, unit: "kg")
        ])

        let line = try #require(folded.first)
        #expect(folded.count == 1)
        // 1000 g reads better as 1 kg.
        #expect(line.unit == "kg")
        #expect(line.quantity == 1)
    }

    @Test("Mass and volume stay apart rather than being guessed at")
    func doesNotMixDimensions() {
        let folded = GroceryMerge.folded([
            GroceryLineItem(name: "Butter", quantity: 200, unit: "g"),
            GroceryLineItem(name: "butter", quantity: 1, unit: "cup")
        ])

        #expect(folded.count == 2)
    }

    @Test("An amount-less line doesn't wipe out an amount")
    func keepsKnownAmounts() throws {
        let folded = GroceryMerge.folded([
            GroceryLineItem(name: "Salt", quantity: nil, unit: nil),
            GroceryLineItem(name: "salt", quantity: 1, unit: "tsp")
        ])

        #expect(folded.count == 1)
        #expect(try #require(folded.first).quantity == 1)
    }

    @Test("Folding twice changes nothing the second time")
    func isIdempotent() {
        let lines = [
            GroceryLineItem(name: "Eggs", quantity: 6, unit: nil),
            GroceryLineItem(name: "egg", quantity: 2, unit: nil),
            GroceryLineItem(name: "Milk", quantity: 500, unit: "ml")
        ]

        let once = GroceryMerge.folded(lines)
        let twice = GroceryMerge.folded(once)

        #expect(once == twice)
        #expect(once.count == 2)
    }
}
