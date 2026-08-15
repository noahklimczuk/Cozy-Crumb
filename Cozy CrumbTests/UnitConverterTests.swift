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

    @Test("Ounces and pounds convert to grams, and to kilograms once large")
    func imperialMassToMetric() throws {
        let grams = try #require(UnitConverter.convert(quantity: 8, unit: "oz", to: .metric))
        #expect(grams.unit == "g")
        expectClose(grams.quantity, 226.796)

        let fromPound = try #require(UnitConverter.convert(quantity: 1, unit: "lb", to: .metric))
        #expect(fromPound.unit == "g")
        expectClose(fromPound.quantity, 453.592)

        let kilos = try #require(UnitConverter.convert(quantity: 3, unit: "lb", to: .metric))
        #expect(kilos.unit == "kg")
        expectClose(kilos.quantity, 1.361)
    }

    @Test("Cups convert to millilitres, and to litres once large")
    func cupsToMetric() throws {
        let millilitres = try #require(UnitConverter.convert(quantity: 1, unit: "cup", to: .metric))
        #expect(millilitres.unit == "ml")
        expectClose(millilitres.quantity, 236.588)

        let litres = try #require(UnitConverter.convert(quantity: 5, unit: "cup", to: .metric))
        #expect(litres.unit == "l")
        expectClose(litres.quantity, 1.183)
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

    @Test("Spoons are left alone going to metric")
    func spoonsStayPut() {
        // Metric kitchens use tsp and tbsp too — "4.93 ml" helps nobody.
        #expect(UnitConverter.convert(quantity: 1, unit: "tsp", to: .metric) == nil)
        #expect(UnitConverter.convert(quantity: 1, unit: "tbsp", to: .metric) == nil)
    }

    @Test("Unit matching is case insensitive")
    func caseInsensitive() throws {
        let result = try #require(UnitConverter.convert(quantity: 100, unit: "G", to: .imperial))
        #expect(result.unit == "oz")
    }
}
