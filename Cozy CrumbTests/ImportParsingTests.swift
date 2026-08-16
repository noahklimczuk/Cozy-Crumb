//
//  ImportParsingTests.swift
//  Cozy CrumbTests
//
//  The small parsers the cascade is built on.
//

import Testing

@testable import Cozy_Crumb

@Suite("Quantity parsing")
struct QuantityParserTests {

    @Test("Plain numbers")
    func plainNumbers() {
        #expect(QuantityParser.parse("2") == 2)
        #expect(QuantityParser.parse("1.5") == 1.5)
        #expect(QuantityParser.parse("0.25") == 0.25)
    }

    @Test("Slash fractions")
    func slashFractions() {
        #expect(QuantityParser.parse("1/2") == 0.5)
        #expect(QuantityParser.parse("3/4") == 0.75)
        #expect(QuantityParser.parse("1/0") == nil)
    }

    @Test("Unicode fractions, alone and mixed")
    func unicodeFractions() throws {
        let half = try #require(QuantityParser.parse("½"))
        #expect(abs(half - 0.5) < 0.0001)

        let mixed = try #require(QuantityParser.parse("1½"))
        #expect(abs(mixed - 1.5) < 0.0001)

        let third = try #require(QuantityParser.parse("⅓"))
        #expect(abs(third - 1.0 / 3.0) < 0.0001)
    }

    @Test("Decimal commas are understood")
    func decimalComma() {
        #expect(QuantityParser.parse("1,5") == 1.5)
    }

    @Test("Leading quantity is split from the rest of the line")
    func leadingQuantity() throws {
        let simple = try #require(QuantityParser.leadingQuantity(in: "2 cups flour"))
        #expect(simple.value == 2)
        #expect(simple.remainder == "cups flour")

        let mixed = try #require(QuantityParser.leadingQuantity(in: "1 1/2 cups flour"))
        #expect(abs(mixed.value - 1.5) < 0.0001)
        #expect(mixed.remainder == "cups flour")

        let unicodeMixed = try #require(QuantityParser.leadingQuantity(in: "1 ½ cups flour"))
        #expect(abs(unicodeMixed.value - 1.5) < 0.0001)
    }

    @Test("Ranges take the lower bound")
    func ranges() throws {
        // Cooking up is easier than cooking down.
        let dashed = try #require(QuantityParser.leadingQuantity(in: "1-2 onions"))
        #expect(dashed.value == 1)

        let worded = try #require(QuantityParser.leadingQuantity(in: "1 to 2 onions"))
        #expect(worded.value == 1)
        #expect(worded.remainder == "onions")
    }

    @Test("Lines with no number return nil")
    func noQuantity() {
        #expect(QuantityParser.leadingQuantity(in: "salt to taste") == nil)
        #expect(QuantityParser.leadingQuantity(in: "") == nil)
    }
}

@Suite("Duration parsing")
struct DurationParserTests {

    @Test("ISO 8601 durations")
    func iso8601() {
        #expect(DurationParser.seconds(fromISO8601: "PT20M") == 1200)
        #expect(DurationParser.seconds(fromISO8601: "PT1H") == 3600)
        #expect(DurationParser.seconds(fromISO8601: "PT1H30M") == 5400)
        #expect(DurationParser.seconds(fromISO8601: "PT45S") == 45)
        #expect(DurationParser.seconds(fromISO8601: "P1DT2H") == 93_600)
    }

    @Test("Minutes helper divides down")
    func minutes() {
        #expect(DurationParser.minutes(fromISO8601: "PT1H30M") == 90)
        #expect(DurationParser.minutes(fromISO8601: "PT20M") == 20)
    }

    @Test("M before T is months, not minutes")
    func monthsAreNotMinutes() {
        // The classic ISO 8601 trap. P1M is one month and means nothing to a
        // recipe, so it must not come back as 60 seconds.
        #expect(DurationParser.seconds(fromISO8601: "P1M") == nil)
        #expect(DurationParser.seconds(fromISO8601: "PT1M") == 60)
    }

    @Test("Malformed durations return nil rather than zero")
    func malformed() {
        #expect(DurationParser.seconds(fromISO8601: "") == nil)
        #expect(DurationParser.seconds(fromISO8601: "20 minutes") == nil)
        #expect(DurationParser.seconds(fromISO8601: "PT") == nil)
    }

    @Test("Plain English times inside a step")
    func stepText() {
        #expect(DurationParser.seconds(inStepText: "Simmer for 20 minutes.") == 1200)
        #expect(DurationParser.seconds(inStepText: "Bake for 1 hour 30 minutes") == 5400)
        #expect(DurationParser.seconds(inStepText: "Rest 45 seconds") == 45)
        #expect(DurationParser.seconds(inStepText: "Cook for 2 hrs") == 7200)
    }

    @Test("Steps with no stated time get no timer")
    func noStatedTime() {
        // A guessed timer is worse than no timer.
        #expect(DurationParser.seconds(inStepText: "Season to taste and serve.") == nil)
        #expect(DurationParser.seconds(inStepText: "Heat the oven to 180 degrees.") == nil)
    }

    @Test("Only the first stated time is taken")
    func firstTimeWins() {
        // Not 20 minutes — the step opens with a 5 minute action.
        #expect(DurationParser.seconds(inStepText: "Rest 5 minutes, then bake 15 minutes") == 300)
    }

    @Test("Servings are read out of a yield string")
    func servings() {
        #expect(DurationParser.servings(from: "4 servings") == 4)
        #expect(DurationParser.servings(from: "Serves 6") == 6)
        #expect(DurationParser.servings(from: "makes 12 cookies") == 12)
        #expect(DurationParser.servings(from: "a loaf") == nil)
    }

    @Test("Duration display formatting")
    func display() {
        #expect(DurationParser.display(seconds: 1200) == "20 min")
        #expect(DurationParser.display(seconds: 3600) == "1 hr")
        #expect(DurationParser.display(seconds: 5400) == "1 hr 30 min")
        #expect(DurationParser.display(seconds: 45) == "45 sec")
        #expect(DurationParser.display(seconds: nil) == nil)
        #expect(DurationParser.display(seconds: 0) == nil)
    }
}

@Suite("Ingredient line parsing")
struct IngredientLineParserTests {

    @Test("Amount, unit and name are separated")
    func basicLine() {
        let result = IngredientLineParser.parse("115 g unsalted butter", order: 0)
        #expect(result.quantity == 115)
        #expect(result.unit == "g")
        #expect(result.name == "unsalted butter")
        #expect(result.rawText == "115 g unsalted butter")
    }

    @Test("The original line is always preserved verbatim")
    func rawTextPreserved() {
        let line = "1 ½ cups (200 g) plain flour, sifted"
        let result = IngredientLineParser.parse(line, order: 0)
        #expect(result.rawText == line)
    }

    @Test("Unit spellings are normalised")
    func unitAliases() {
        #expect(IngredientLineParser.parse("2 tablespoons olive oil", order: 0).unit == "tbsp")
        #expect(IngredientLineParser.parse("1 teaspoon salt", order: 0).unit == "tsp")
        #expect(IngredientLineParser.parse("500 grams beef", order: 0).unit == "g")
        #expect(IngredientLineParser.parse("2 cloves garlic", order: 0).unit == "clove")
        #expect(IngredientLineParser.parse("1 tin tomatoes", order: 0).unit == "can")
    }

    @Test("Notes are split off the name")
    func notes() {
        let comma = IngredientLineParser.parse("3 bananas, very ripe", order: 0)
        #expect(comma.name == "bananas")
        #expect(comma.note == "very ripe")

        let parens = IngredientLineParser.parse("200 g flour (plain)", order: 0)
        #expect(parens.name == "flour")
        #expect(parens.note == "plain")
    }

    @Test("Trailing prep words become notes")
    func trailingPrepWords() {
        let result = IngredientLineParser.parse("115 g butter softened", order: 0)
        #expect(result.name == "butter")
        #expect(result.note == "softened")
    }

    @Test("'of' after a unit is dropped")
    func ofIsDropped() {
        let result = IngredientLineParser.parse("2 cups of flour", order: 0)
        #expect(result.name == "flour")
    }

    @Test("Section headers are marked, not shopped")
    func sectionHeaders() {
        let header = IngredientLineParser.parse("For the sauce:", order: 0)
        #expect(header.isSectionHeader)
        #expect(header.quantity == nil)

        let notHeader = IngredientLineParser.parse("2 eggs", order: 0)
        #expect(notHeader.isSectionHeader == false)
    }

    @Test("Lines with no amount keep a nil quantity")
    func noAmount() {
        let result = IngredientLineParser.parse("Salt and pepper to taste", order: 0)
        #expect(result.quantity == nil)
        #expect(result.unit == nil)
    }

    @Test("Categories are guessed for the grocery list")
    func categoryGuessing() {
        #expect(IngredientLineParser.parse("2 onions", order: 0).groceryCategory == .produce)
        #expect(IngredientLineParser.parse("250 ml milk", order: 0).groceryCategory == .dairy)
        #expect(IngredientLineParser.parse("500 g chicken thighs", order: 0).groceryCategory == .meat)
        #expect(IngredientLineParser.parse("200 g plain flour", order: 0).groceryCategory == .pantry)
        #expect(IngredientLineParser.parse("2 tbsp soy sauce", order: 0).groceryCategory == .condiment)
    }

    @Test("Coconut milk is pantry, not dairy")
    func specificBeatsGeneric() {
        // The obvious trap in keyword matching.
        #expect(IngredientLineParser.parse("200 ml coconut milk", order: 0).groceryCategory == .pantry)
    }
}

@Suite("Caption-style ingredient lines")
struct CaptionIngredientTests {

    @Test("Bulleted lines still yield a quantity")
    func bulletedLines() {
        // This is what broke servings scaling on social imports: a leading
        // bullet made the parser return no quantity, so there was nothing to
        // scale or convert.
        let bullet = IngredientLineParser.parse("• 2 eggs", order: 0)
        #expect(bullet.quantity == 2)
        #expect(bullet.name == "eggs")

        let dash = IngredientLineParser.parse("- 100 g butter", order: 0)
        #expect(dash.quantity == 100)
        #expect(dash.unit == "g")

        let asterisk = IngredientLineParser.parse("* 1 onion", order: 0)
        #expect(asterisk.quantity == 1)
    }

    @Test("Emoji decoration is ignored")
    func emojiLines() {
        let leading = IngredientLineParser.parse("🧈 100 g butter", order: 0)
        #expect(leading.quantity == 100)
        #expect(leading.unit == "g")

        let trailing = IngredientLineParser.parse("2 eggs 🥚", order: 0)
        #expect(trailing.quantity == 2)
        #expect(trailing.name == "eggs")
    }

    @Test("Decoration never touches rawText")
    func rawTextIsUntouched() {
        // The poster's own wording is what the user sees, so it is preserved
        // exactly even when the parser reads past the decoration.
        let line = "• 2 eggs 🥚"
        #expect(IngredientLineParser.parse(line, order: 0).rawText == line)
    }

    @Test("A leading unicode fraction survives stripping")
    func fractionsSurvive() throws {
        // The strip must stop at a fraction character rather than eating it.
        let result = IngredientLineParser.parse("½ cup sugar", order: 0)
        let quantity = try #require(result.quantity)
        #expect(abs(quantity - 0.5) < 0.0001)
        #expect(result.unit == "cup")
    }

    @Test("Bulleted section headers are still headers")
    func decoratedHeaders() {
        #expect(IngredientLineParser.parse("• For the sauce:", order: 0).isSectionHeader)
    }
}
