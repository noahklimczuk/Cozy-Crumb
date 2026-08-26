//
//  ServingsScalerTests.swift
//  Cozy CrumbTests
//

import Testing

@testable import Cozy_Crumb

@Suite("Servings scaling")
struct ServingsScalerTests {

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

    @Test("Factor is the ratio of target to original")
    func factor() {
        #expect(ServingsScaler.factor(from: 4, to: 8) == 2)
        #expect(ServingsScaler.factor(from: 4, to: 2) == 0.5)
        #expect(ServingsScaler.factor(from: 4, to: 4) == 1)
    }

    @Test("Nonsense servings fall back to 1x rather than dividing by zero")
    func degenerateFactors() {
        #expect(ServingsScaler.factor(from: 0, to: 4) == 1)
        #expect(ServingsScaler.factor(from: 4, to: 0) == 1)
        #expect(ServingsScaler.factor(from: -2, to: 4) == 1)
    }

    @Test("Quantities scale with servings")
    func scaling() {
        let doubled = ServingsScaler.scale(quantity: 150, unit: "g", from: 4, to: 8)
        expectClose(doubled.quantity, 300)
        #expect(doubled.unit == "g")

        let halved = ServingsScaler.scale(quantity: 150, unit: "g", from: 4, to: 2)
        expectClose(halved.quantity, 75)
    }

    @Test("Lines with no quantity never scale")
    func noQuantity() {
        // "Salt, to taste" must survive untouched.
        let result = ServingsScaler.scale(quantity: nil, unit: nil, from: 4, to: 12)
        #expect(result.quantity == nil)
        #expect(result.isAwkward == false)
        #expect(result.awkwardNote == nil)
    }

    @Test("Fractions of countable things are flagged")
    func awkwardAmounts() {
        // 3 eggs scaled from 4 to 6 servings is 4.5 eggs.
        let eggs = ServingsScaler.scale(quantity: 3, unit: "piece", from: 4, to: 6)
        expectClose(eggs.quantity, 4.5)
        #expect(eggs.isAwkward)
        #expect(eggs.awkwardNote != nil)

        let cloves = ServingsScaler.scale(quantity: 3, unit: "clove", from: 2, to: 3)
        expectClose(cloves.quantity, 4.5)
        #expect(cloves.isAwkward)
    }

    @Test("Whole counts are not flagged")
    func wholeCounts() {
        let eggs = ServingsScaler.scale(quantity: 2, unit: "piece", from: 4, to: 8)
        expectClose(eggs.quantity, 4)
        #expect(eggs.isAwkward == false)
        #expect(eggs.awkwardNote == nil)
    }

    @Test("Measured amounts are never flagged as awkward")
    func measuredAmounts() {
        // 187.5 g is fine — you can weigh it.
        let flour = ServingsScaler.scale(quantity: 150, unit: "g", from: 4, to: 5)
        expectClose(flour.quantity, 187.5)
        #expect(flour.isAwkward == false)
    }

    @Test("Awkward note suggests rounding up")
    func awkwardNoteText() throws {
        let eggs = ServingsScaler.scale(quantity: 3, unit: "piece", from: 4, to: 6)
        let note = try #require(eggs.awkwardNote)
        #expect(note.contains("4½"))
        #expect(note.contains("5"))
    }

    @Test("Scaling happens before conversion")
    func scaleThenConvert() throws {
        // 8 oz doubled is 16 oz, which is 453.59 g. Converting first and then
        // doubling would compound the rounding error.
        let result = ServingsScaler.scale(quantity: 8, unit: "oz", from: 4, to: 8, system: .metric)
        #expect(result.unit == "g")
        expectClose(result.quantity, 453.592, tolerance: 0.01)
    }

    @Test("The ingredient reaches the converter, so volumes can go to grams")
    func ingredientReachesConverter() {
        // Without the name this is 473 ml. With it, it's the number a scale
        // can actually show.
        let result = ServingsScaler.scale(
            quantity: 1,
            unit: "cup",
            ingredient: "plain flour",
            from: 4,
            to: 8,
            system: .metric
        )
        #expect(result.unit == "g")
        expectClose(result.quantity, 250)
    }

    @Test("Converted amounts are not flagged as awkward")
    func convertedNotAwkward() {
        // A converted number is already approximate; flagging it is noise.
        let result = ServingsScaler.scale(quantity: 100, unit: "g", from: 4, to: 6, system: .imperial)
        #expect(result.isAwkward == false)
    }

    @Test("Counts survive conversion untouched")
    func countsSurviveConversion() {
        let result = ServingsScaler.scale(quantity: 3, unit: "piece", from: 4, to: 6, system: .metric)
        #expect(result.unit == "piece")
        expectClose(result.quantity, 4.5)
        #expect(result.isAwkward)
    }
}
