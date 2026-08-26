//
//  UnitConverterTests.swift
//  Cozy CrumbTests
//

import Testing

@testable import Cozy_Crumb

@Suite("Unit conversion")
struct UnitConverterTests {

    /// Conversions are floating point; compare with a tolerance rather than
    /// exact equality.
    private func expectClose(
        _ actual: Double,
        _ expected: Double,
        tolerance: Double = 0.01,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(actual - expected) < tolerance, sourceLocation: sourceLocation)
    }

    @Test("As-written never converts")
    func asWritten() {
        #expect(UnitConverter.convert(quantity: 100, unit: "g", to: .asWritten) == nil)
        #expect(UnitConverter.convert(quantity: 1, unit: "cup", to: .asWritten) == nil)
    }

    @Test("Counts are never converted")
    func counts() {
        // The "1 onion stays 1 onion" rule.
        #expect(UnitConverter.convert(quantity: 1, unit: "piece", to: .metric) == nil)
        #expect(UnitConverter.convert(quantity: 4, unit: "clove", to: .imperial) == nil)
        #expect(UnitConverter.convert(quantity: 1, unit: "pinch", to: .metric) == nil)
        #expect(UnitConverter.convert(quantity: 2, unit: "can", to: .imperial) == nil)
        #expect(UnitConverter.convert(quantity: 1, unit: "bunch", to: .metric) == nil)
    }

    @Test("Missing or unknown units are left alone")
    func unknownUnits() {
        #expect(UnitConverter.convert(quantity: 1, unit: nil, to: .metric) == nil)
        #expect(UnitConverter.convert(quantity: 1, unit: "", to: .metric) == nil)
        #expect(UnitConverter.convert(quantity: 1, unit: "splash", to: .metric) == nil)
    }

    @Test("Grams convert to ounces, and to pounds once large enough")
    func gramsToImperial() throws {
        let ounces = try #require(UnitConverter.convert(quantity: 100, unit: "g", to: .imperial))
        #expect(ounces.unit == "oz")
        expectClose(ounces.quantity, 3.527)

        let pounds = try #require(UnitConverter.convert(quantity: 500, unit: "g", to: .imperial))
        #expect(pounds.unit == "lb")
        expectClose(pounds.quantity, 1.102)
    }

    @Test("Kilograms convert to pounds")
    func kilogramsToImperial() throws {
        let result = try #require(UnitConverter.convert(quantity: 1, unit: "kg", to: .imperial))
        #expect(result.unit == "lb")
        expectClose(result.quantity, 2.205)
    }

    @Test("Ounces and pounds convert to grams, and stay in grams")
    func imperialMassToMetric() throws {
        let grams = try #require(UnitConverter.convert(quantity: 8, unit: "oz", to: .metric))
        #expect(grams.unit == "g")
        expectClose(grams.quantity, 226.796)

        let fromPound = try #require(UnitConverter.convert(quantity: 1, unit: "lb", to: .metric))
        #expect(fromPound.unit == "g")
        expectClose(fromPound.quantity, 453.592)

        // No kilograms. A scale reads grams, and "1361 g" is easier to weigh
        // than "1.361 kg".
        let large = try #require(UnitConverter.convert(quantity: 3, unit: "lb", to: .metric))
        #expect(large.unit == "g")
        expectClose(large.quantity, 1360.777, tolerance: 0.1)
    }

    @Test("Long and plural spellings of imperial mass are understood")
    func imperialMassSpellings() throws {
        for unit in ["oz", "ounce", "ounces"] {
            let result = try #require(UnitConverter.convert(quantity: 1, unit: unit, to: .metric))
            #expect(result.unit == "g")
            expectClose(result.quantity, 28.349)
        }

        for unit in ["lb", "lbs", "pound", "pounds"] {
            let result = try #require(UnitConverter.convert(quantity: 1, unit: unit, to: .metric))
            #expect(result.unit == "g")
            expectClose(result.quantity, 453.592)
        }
    }

    @Test("A stick of butter is a weight everywhere but America")
    func sticksToMetric() throws {
        let result = try #require(UnitConverter.convert(quantity: 1, unit: "stick", to: .metric))
        #expect(result.unit == "g")
        expectClose(result.quantity, 113.398)
    }

    @Test("Cups with no known ingredient stay in millilitres")
    func cupsToMetric() throws {
        let millilitres = try #require(UnitConverter.convert(quantity: 1, unit: "cup", to: .metric))
        #expect(millilitres.unit == "ml")
        expectClose(millilitres.quantity, 236.588)

        let litres = try #require(UnitConverter.convert(quantity: 5, unit: "cup", to: .metric))
        #expect(litres.unit == "l")
        expectClose(litres.quantity, 1.183)
    }

    @Test("Cups of a known ingredient convert to grams")
    func cupsToGrams() throws {
        // The whole point: a metric recipe weighs its dry goods.
        let flour = try #require(
            UnitConverter.convert(quantity: 1, unit: "cup", ingredient: "plain flour", to: .metric)
        )
        #expect(flour.unit == "g")
        expectClose(flour.quantity, 125)

        // Same volume, different weight — which is why the ingredient has to
        // come in with the quantity.
        let sugar = try #require(
            UnitConverter.convert(quantity: 1, unit: "cup", ingredient: "granulated sugar", to: .metric)
        )
        #expect(sugar.unit == "g")
        expectClose(sugar.quantity, 200)

        let honey = try #require(
            UnitConverter.convert(quantity: 0.5, unit: "cup", ingredient: "honey", to: .metric)
        )
        #expect(honey.unit == "g")
        expectClose(honey.quantity, 170)
    }

    @Test("The most specific ingredient match wins")
    func densityMatching() throws {
        // "brown sugar" must not be read as "sugar", nor "almond flour" as
        // "flour" — the generic keyword is a substring of the specific one.
        let brown = try #require(
            UnitConverter.convert(quantity: 1, unit: "cup", ingredient: "light brown sugar", to: .metric)
        )
        expectClose(brown.quantity, 213)

        let almond = try #require(
            UnitConverter.convert(quantity: 1, unit: "cup", ingredient: "almond flour", to: .metric)
        )
        expectClose(almond.quantity, 96)
    }

    @Test("Every volume unit a recipe might use is understood")
    func volumeSpellings() throws {
        let expected: [String: Double] = [
            "cup": 236.588, "cups": 236.588,
            "fl oz": 29.574, "fluid ounce": 29.574, "fluid ounces": 29.574,
            "pint": 473.176, "pints": 473.176,
            "quart": 946.353, "quarts": 946.353,
        ]

        for (unit, millilitres) in expected {
            let result = try #require(UnitConverter.convert(quantity: 1, unit: unit, to: .metric))
            #expect(result.unit == "ml")
            expectClose(result.quantity, millilitres, tolerance: 0.01)
        }

        // Over a litre, so it reads as one.
        let gallon = try #require(UnitConverter.convert(quantity: 1, unit: "gallon", to: .metric))
        #expect(gallon.unit == "l")
        expectClose(gallon.quantity, 3.785)
    }

    @Test("Millilitres pick the unit that reads best")
    func millilitresToImperial() throws {
        let cups = try #require(UnitConverter.convert(quantity: 250, unit: "ml", to: .imperial))
        #expect(cups.unit == "cup")
        expectClose(cups.quantity, 1.057)

        // Too small for a cup, so spoons instead of "0.13 cup".
        let tablespoons = try #require(UnitConverter.convert(quantity: 30, unit: "ml", to: .imperial))
        #expect(tablespoons.unit == "tbsp")
        expectClose(tablespoons.quantity, 2.029)

        let teaspoons = try #require(UnitConverter.convert(quantity: 5, unit: "ml", to: .imperial))
        #expect(teaspoons.unit == "tsp")
        expectClose(teaspoons.quantity, 1.014)
    }

    @Test("Spoons of something unweighable are left alone")
    func spoonsStayPut() {
        // Metric kitchens use tsp and tbsp too — "4.93 ml vanilla" helps
        // nobody, so a spoon only moves when there's a weight to move it to.
        #expect(UnitConverter.convert(quantity: 1, unit: "tsp", to: .metric) == nil)
        #expect(UnitConverter.convert(quantity: 1, unit: "tbsp", to: .metric) == nil)
        #expect(
            UnitConverter.convert(
                quantity: 1, unit: "tsp", ingredient: "vanilla extract", to: .metric
            ) == nil
        )
    }

    @Test("Spoons of something weighable convert to grams")
    func spoonsToGrams() throws {
        // "3 tbsp butter" is exactly the line a metric cook wants a number for.
        let butter = try #require(
            UnitConverter.convert(quantity: 3, unit: "tbsp", ingredient: "butter", to: .metric)
        )
        #expect(butter.unit == "g")
        expectClose(butter.quantity, 42.6, tolerance: 0.1)

        let cocoa = try #require(
            UnitConverter.convert(quantity: 2, unit: "tsp", ingredient: "cocoa powder", to: .metric)
        )
        #expect(cocoa.unit == "g")
        expectClose(cocoa.quantity, 3.5, tolerance: 0.1)
    }

    @Test("Unit matching is case insensitive")
    func caseInsensitive() throws {
        let result = try #require(UnitConverter.convert(quantity: 100, unit: "G", to: .imperial))
        #expect(result.unit == "oz")
    }
}
