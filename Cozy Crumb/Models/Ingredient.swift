//
//  Ingredient.swift
//  Cozy Crumb
//
//  One line of a recipe's ingredient list.
//
//  `rawText` always holds the original line verbatim. Everything else is the
//  parser's interpretation, and the raw line is what we fall back to when the
//  interpretation is wrong or absent.
//

import Foundation
import SwiftData

@Model
final class Ingredient {
    @Attribute(.unique) var id: UUID
    var order: Int

    /// The original line, exactly as written by the source.
    var rawText: String

    /// nil for "salt to taste".
    var quantity: Double?
    /// Normalised: g, kg, ml, l, tsp, tbsp, cup, oz, lb, clove, piece, pinch,
    /// can, bunch. nil when the source unit didn't map cleanly.
    var unit: String?
    /// The food item alone — "unsalted butter".
    var name: String
    /// "softened", "divided", "finely chopped".
    var note: String?

    var groceryCategory: GroceryCategory
    /// "For the sauce:" style dividers.
    var isSectionHeader: Bool

    var recipe: Recipe?

    init(
        id: UUID = UUID(),
        order: Int,
        rawText: String,
        quantity: Double? = nil,
        unit: String? = nil,
        name: String,
        note: String? = nil,
        groceryCategory: GroceryCategory = .other,
        isSectionHeader: Bool = false
    ) {
        self.id = id
        self.order = order
        self.rawText = rawText
        self.quantity = quantity
        self.unit = unit
        self.name = name
        self.note = note
        self.groceryCategory = groceryCategory
        self.isSectionHeader = isSectionHeader
    }

    /// Section header convenience.
    convenience init(order: Int, header: String) {
        self.init(
            order: order,
            rawText: header,
            name: header,
            groceryCategory: .other,
            isSectionHeader: true
        )
    }
}

extension Ingredient {
    /// Normalised key for grocery merging and duplicate detection. Phase 5
    /// builds the real merge on top of this.
    var mergeKey: String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when the line carries a number we can scale with servings.
    var isScalable: Bool {
        quantity != nil && !isSectionHeader
    }
}
