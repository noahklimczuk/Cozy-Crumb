//
//  FractionFormatterTests.swift
//  Cozy CrumbTests
//
//  Written with Swift Testing, which is what Xcode 26 creates for a new test
//  bundle. If the target ends up on XCTest instead, these need converting.
//

import Testing

@testable import Cozy_Crumb

@Suite("Fraction formatting")
struct FractionFormatterTests {

    @Test("Whole numbers stay whole")
    func wholeNumbers() {
        #expect(FractionFormatter.string(for: 1) == "1")
        #expect(FractionFormatter.string(for: 2) == "2")
        #expect(FractionFormatter.string(for: 150) == "150")
    }

    @Test("Common fractions become glyphs")
    func commonFractions() {
        #expect(FractionFormatter.string(for: 0.5) == "½")
        #expect(FractionFormatter.string(for: 0.25) == "¼")
        #expect(FractionFormatter.string(for: 0.75) == "¾")
        #expect(FractionFormatter.string(for: 1.0 / 3.0) == "⅓")
        #expect(FractionFormatter.string(for: 2.0 / 3.0) == "⅔")
        #expect(FractionFormatter.string(for: 0.125) == "⅛")
    }

    @Test("Mixed numbers combine whole and fraction")
    func mixedNumbers() {
        #expect(FractionFormatter.string(for: 1.5) == "1½")
        #expect(FractionFormatter.string(for: 2.25) == "2¼")
        #expect(FractionFormatter.string(for: 3.0 + 2.0 / 3.0) == "3⅔")
    }

    @Test("Repeating decimals do not leak through")
    func repeatingDecimals() {
        // The whole point: 0.6666666 must never reach the screen.
        #expect(FractionFormatter.string(for: 0.6666666) == "⅔")
        #expect(FractionFormatter.string(for: 0.3333333) == "⅓")
    }

    @Test("Near-whole values round to whole")
    func nearWhole() {
        #expect(FractionFormatter.string(for: 1.999) == "2")
        #expect(FractionFormatter.string(for: 2.005) == "2")
    }

    @Test("Large values skip fractions entirely")
    func largeValues() {
        #expect(FractionFormatter.string(for: 212.5) == "213")
        #expect(FractionFormatter.string(for: 1000) == "1000")
    }

    @Test("Values with no clean fraction fall back to a trimmed decimal")
    func awkwardValues() {
        #expect(FractionFormatter.string(for: 0.05) == "0.05")
    }

    @Test("Zero and negatives do not produce nonsense")
    func edgeCases() {
        #expect(FractionFormatter.string(for: 0) == "0")
        #expect(FractionFormatter.string(for: -1) == "0")
    }

    @Test("Countable units pluralise, measured units do not")
    func pluralisation() {
        #expect(FractionFormatter.quantityString(quantity: 1, unit: "clove") == "1 clove")
        #expect(FractionFormatter.quantityString(quantity: 2, unit: "clove") == "2 cloves")
        #expect(FractionFormatter.quantityString(quantity: 3, unit: "can") == "3 cans")
        // "2 gs" would be worse than leaving it alone.
        #expect(FractionFormatter.quantityString(quantity: 150, unit: "g") == "150 g")
        #expect(FractionFormatter.quantityString(quantity: 2, unit: "tbsp") == "2 tbsp")
    }

    @Test("Quantity strings combine amount and unit")
    func quantityStrings() {
        #expect(FractionFormatter.quantityString(quantity: 1.5, unit: "cup") == "1½ cup")
        #expect(FractionFormatter.quantityString(quantity: 0.5, unit: "tsp") == "½ tsp")
        #expect(FractionFormatter.quantityString(quantity: 2, unit: nil) == "2")
    }
}
