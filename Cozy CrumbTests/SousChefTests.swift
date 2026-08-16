//
//  SousChefTests.swift
//  Cozy CrumbTests
//
//  The parts of the Sous Chef that can be wrong without anyone noticing: the
//  digest it reasons from, and the reading of the arguments it sends back.
//

import Foundation
import Testing

@testable import Cozy_Crumb

@Suite("Function arguments")
struct JSONValueTests {

    private func decode(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    @Test("An object of mixed types decodes")
    func decodesMixedObject() throws {
        let value = try decode(#"{"name":"butter","quantity":250,"unit":"g","urgent":true}"#)

        #expect(value["name"]?.stringValue == "butter")
        #expect(value["quantity"]?.doubleValue == 250)
        #expect(value["unit"]?.stringValue == "g")
        #expect(value["urgent"] == .bool(true))
    }

    @Test("Nested arrays of objects decode, which is the shape every tool uses")
    func decodesNestedItems() throws {
        let value = try decode(#"{"items":[{"name":"eggs","quantity":6},{"name":"milk"}]}"#)

        let items = try #require(value["items"]?.arrayValue)
        #expect(items.count == 2)
        #expect(items[0]["name"]?.stringValue == "eggs")
        #expect(items[0]["quantity"]?.intValue == 6)
        #expect(items[1]["quantity"] == nil)
    }

    @Test("A number sent as a string is still read as a number")
    func readsLooseNumbers() throws {
        let value = try decode(#"{"quantity":"1.5","days":"2"}"#)

        #expect(value["quantity"]?.doubleValue == 1.5)
        #expect(value["days"]?.intValue == 2)
    }

    @Test("A whole number read as text loses the decimal point")
    func wholeNumbersReadCleanly() throws {
        let value = try decode(#"{"servings":4}"#)
        #expect(value["servings"]?.stringValue == "4")
    }

    @Test("Null and missing keys are both simply absent")
    func handlesNull() throws {
        let value = try decode(#"{"unit":null}"#)

        #expect(value["unit"] == JSONValue.null)
        #expect(value["unit"]?.stringValue == nil)
        #expect(value["nothing"] == nil)
    }

    @Test("A round trip through encoding keeps the shape")
    func roundTrips() throws {
        let original = try decode(#"{"items":[{"name":"eggs","quantity":6}]}"#)
        let data = try JSONEncoder().encode(original)
        let again = try JSONDecoder().decode(JSONValue.self, from: data)

        #expect(original == again)
    }
}

@Suite("Cookbook digest")
struct SousChefContextTests {

    private func digest(
        _ title: String,
        minutes: Int? = nil,
        tags: [String] = [],
        cookedDaysAgo: Int? = nil,
        ingredients: [String] = []
    ) -> SousChefContext.RecipeDigest {
        SousChefContext.RecipeDigest(
            title: title,
            minutes: minutes,
            servings: 4,
            tags: tags,
            lastCookedAt: cookedDaysAgo.map { Date.now.addingTimeInterval(-Double($0) * 86_400) },
            isFavorite: false,
            keyIngredients: ingredients
        )
    }

    @Test("A recipe line carries what a suggestion would need")
    func describesARecipe() {
        let context = SousChefContext(
            recipes: [digest("Miso Salmon", minutes: 25, tags: ["fish"], cookedDaysAgo: 3, ingredients: ["salmon", "miso"])],
            totalRecipeCount: 1
        )

        let text = context.promptText
        #expect(text.contains("Miso Salmon"))
        #expect(text.contains("25 min"))
        #expect(text.contains("serves 4"))
        #expect(text.contains("fish"))
        #expect(text.contains("last cooked 3d ago"))
        #expect(text.contains("uses salmon, miso"))
    }

    @Test("A never-cooked recipe says so rather than leaving a gap")
    func marksNeverCooked() {
        let context = SousChefContext(recipes: [digest("Banana Bread")], totalRecipeCount: 1)
        #expect(context.promptText.contains("never cooked"))
    }

    @Test("An empty kitchen is described, not omitted")
    func describesEmptyState() {
        let text = SousChefContext().promptText

        #expect(text.contains("They haven't saved anything yet"))
        #expect(text.contains("nothing recorded"))
        #expect(text.contains("nothing yet"))
        #expect(text.contains("nothing planned"))
    }

    @Test("A trimmed cookbook admits what it left out")
    func admitsTruncation() {
        let context = SousChefContext(
            recipes: (1...5).map { digest("Recipe \($0)") },
            totalRecipeCount: 120
        )

        let text = context.promptText
        #expect(text.contains("120 recipes saved"))
        #expect(text.contains("115 more not listed here"))
        #expect(text.contains("find_recipes"))
    }

    @Test("Pantry, list and plan all reach the prompt")
    func includesTheRestOfTheKitchen() {
        let context = SousChefContext(
            pantry: ["2 eggs", "milk"],
            groceries: ["butter"],
            plan: [SousChefContext.PlannedDigest(day: "Tue", slot: "Dinner", title: "Chickpea Curry")],
            units: .metric
        )

        let text = context.promptText
        #expect(text.contains("2 eggs, milk"))
        #expect(text.contains("butter"))
        #expect(text.contains("Tue Dinner: Chickpea Curry"))
        #expect(text.contains("Metric"))
    }
}

@Suite("Tool declarations")
struct SousChefToolTests {

    @Test("Every declared tool has a name the runner answers to")
    func declarationsMatchTheRunner() {
        let names = Set(SousChefTools.declarations.map(\.name))

        #expect(names == [
            SousChefTools.findRecipes,
            SousChefTools.addToGroceryList,
            SousChefTools.planMeal
        ])
    }

    @Test("Nothing destructive is on the table")
    func nothingDestructive() {
        let names = SousChefTools.declarations.map(\.name).joined(separator: " ")

        #expect(!names.contains("delete"))
        #expect(!names.contains("remove"))
        #expect(!names.contains("clear"))
    }

    @Test("Meal names arrive as words, and are read as words")
    func readsMealNames() {
        #expect(MealSlot.named("dinner") == .dinner)
        #expect(MealSlot.named("Breakfast") == .breakfast)
        #expect(MealSlot.named(" lunch ") == .lunch)
        #expect(MealSlot.named("elevenses") == nil)
        #expect(MealSlot.named(nil) == nil)
    }
}
