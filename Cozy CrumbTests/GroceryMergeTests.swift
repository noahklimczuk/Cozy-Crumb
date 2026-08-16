//
//  GroceryMergeTests.swift
//  Cozy CrumbTests
//
//  The spec calls the smart merge out by name as something to test properly
//  (§5.5, §10). A wrong merge puts a wrong number on a shopping list, and the
//  user won't find out until they're standing in the shop.
//

import Testing

@testable import Cozy_Crumb

@Suite("Grocery smart merge")
struct GroceryMergeTests {

    private func line(
        _ name: String,
        _ quantity: Double? = nil,
        _ unit: String? = nil,
        category: GroceryCategory = .other,
        from sources: [String] = []
    ) -> GroceryLineItem {
        GroceryLineItem(
            name: name,
            quantity: quantity,
            unit: unit,
            category: category,
            sourceRecipeTitles: sources
        )
    }

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

    // MARK: - The headline case

    @Test("Two cloves plus three cloves is five cloves, not two rows")
    func garlic() {
        let folded = GroceryMerge.folded([
            line("garlic", 3, "clove"),
            line("garlic", 2, "clove")
        ])

        #expect(folded.count == 1)
        expectClose(folded[0].quantity, 5)
        #expect(folded[0].unit == "clove")
    }

    // MARK: - Names

    @Test("Plurals, articles and casing all land on the same key")
    func nameNormalisation() {
        #expect(GroceryMerge.normalizedName("Eggs") == GroceryMerge.normalizedName("egg"))
        #expect(GroceryMerge.normalizedName("  Sweet Potatoes ") == GroceryMerge.normalizedName("sweet potato"))
        #expect(GroceryMerge.normalizedName("a lemon") == GroceryMerge.normalizedName("lemons"))
        #expect(GroceryMerge.normalizedName("cherries") == GroceryMerge.normalizedName("cherry"))
    }

    @Test("Words that merely end in s are not mangled into a match")
    func falsePlurals() {
        #expect(GroceryMerge.normalizedName("asparagus") == "asparagus")
        #expect(GroceryMerge.normalizedName("watercress") == "watercress")
    }

    @Test("Different foods never merge")
    func differentNames() {
        let folded = GroceryMerge.folded([
            line("flour", 200, "g"),
            line("sugar", 200, "g")
        ])

        #expect(folded.count == 2)
    }

    // MARK: - Units

    @Test("Compatible units convert into the unit already on the list")
    func compatibleUnits() {
        let folded = GroceryMerge.folded([
            line("flour", 200, "g"),
            line("flour", 300, "g")
        ])

        #expect(folded.count == 1)
        expectClose(folded[0].quantity, 500)
        #expect(folded[0].unit == "g")
    }

    @Test("Kilograms and grams add up, and promote when they get big")
    func massPromotion() {
        let folded = GroceryMerge.folded([
            line("potatoes", 800, "g"),
            line("potatoes", 1, "kg")
        ])

        #expect(folded.count == 1)
        expectClose(folded[0].quantity, 1.8)
        #expect(folded[0].unit == "kg")
    }

    @Test("Millilitres promote to litres the same way")
    func volumePromotion() {
        let folded = GroceryMerge.folded([
            line("stock", 600, "ml"),
            line("stock", 0.5, "l")
        ])

        #expect(folded.count == 1)
        expectClose(folded[0].quantity, 1.1)
        #expect(folded[0].unit == "l")
    }

    @Test("Spoons fold into cups")
    func spoonsIntoCups() {
        let folded = GroceryMerge.folded([
            line("milk", 1, "cup"),
            line("milk", 2, "tbsp")
        ])

        #expect(folded.count == 1)
        #expect(folded[0].unit == "cup")
        expectClose(folded[0].quantity, 1.125, tolerance: 0.01)
    }

    @Test("Mass and volume stay apart — density is not ours to guess")
    func incompatibleDimensions() {
        let folded = GroceryMerge.folded([
            line("butter", 200, "g"),
            line("butter", 1, "cup")
        ])

        #expect(folded.count == 2)
    }

    @Test("A count unit never merges with a measured one")
    func countVersusMeasured() {
        #expect(!GroceryMerge.unitsAreCompatible("clove", "g"))
        #expect(!GroceryMerge.unitsAreCompatible("piece", nil))
        #expect(GroceryMerge.unitsAreCompatible("clove", "clove"))
        #expect(GroceryMerge.unitsAreCompatible(nil, nil))
    }

    @Test("Unitless counts still add up")
    func unitlessCounts() {
        let folded = GroceryMerge.folded([
            line("banana", 3),
            line("bananas", 2)
        ])

        #expect(folded.count == 1)
        expectClose(folded[0].quantity, 5)
        #expect(folded[0].unit == nil)
    }

    // MARK: - Missing amounts

    @Test("An amount-less line merges in without wiping out the amount")
    func missingQuantity() {
        let folded = GroceryMerge.folded([
            line("salt", 2, nil),
            line("salt", nil, nil)
        ])

        #expect(folded.count == 1)
        expectClose(folded[0].quantity, 2)
    }

    @Test("Two amount-less lines stay amount-less")
    func bothMissing() {
        let folded = GroceryMerge.folded([
            line("salt"),
            line("salt")
        ])

        #expect(folded.count == 1)
        #expect(folded[0].quantity == nil)
    }

    @Test("An amount arriving after a blank line is kept")
    func quantityArrivesSecond() {
        let folded = GroceryMerge.folded([
            line("pepper"),
            line("pepper", 1)
        ])

        #expect(folded.count == 1)
        expectClose(folded[0].quantity, 1)
    }

    @Test("A blank line and a measured one stay apart — no unit to add into")
    func blankAgainstMeasured() {
        let folded = GroceryMerge.folded([
            line("pepper"),
            line("pepper", 1, "tsp")
        ])

        #expect(folded.count == 2)
    }

    // MARK: - Carried metadata

    @Test("Every source recipe is remembered, without repeats")
    func sourceTitles() {
        let folded = GroceryMerge.folded([
            line("onion", 1, nil, from: ["Curry"]),
            line("onion", 2, nil, from: ["Ragu"]),
            line("onion", 1, nil, from: ["Curry"])
        ])

        #expect(folded.count == 1)
        #expect(folded[0].sourceRecipeTitles == ["Curry", "Ragu"])
    }

    @Test("A real category beats the fallback, whichever side it came from")
    func categoryPromotion() {
        let folded = GroceryMerge.folded([
            line("carrot", 2, nil, category: .other),
            line("carrot", 1, nil, category: .produce)
        ])

        #expect(folded.count == 1)
        #expect(folded[0].category == .produce)
    }

    // MARK: - Batch behaviour

    @Test("Folding preserves the order things first appeared in")
    func order() {
        let folded = GroceryMerge.folded([
            line("flour", 100, "g"),
            line("eggs", 2),
            line("flour", 100, "g")
        ])

        #expect(folded.map(\.name) == ["flour", "eggs"])
    }

    @Test("An empty batch folds to nothing")
    func empty() {
        #expect(GroceryMerge.folded([]).isEmpty)
    }

    // MARK: - Export text

    @Test("Notes gets a real checklist")
    func checklistText() {
        let text = GroceryExport.checklistText(for: [
            line("flour", 200, "g"),
            line("salt")
        ])

        #expect(text == "- [ ] 200 g flour\n- [ ] salt")
    }
}
