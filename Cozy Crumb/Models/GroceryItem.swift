//
//  GroceryItem.swift
//  Cozy Crumb
//
//  One row on the grocery list. `sourceRecipeTitles` is stored rather than
//  modelled as a relationship so the caption survives the recipe being
//  deleted — the item is still on your list either way.
//

import Foundation
import SwiftData

@Model
final class GroceryItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var quantity: Double?
    var unit: String?
    var category: GroceryCategory
    var isChecked: Bool
    var addedAt: Date

    /// Which recipe(s) this came from, shown as a tiny caption (§5.5).
    var sourceRecipeTitles: [String]

    var list: GroceryList?

    init(
        id: UUID = UUID(),
        name: String,
        quantity: Double? = nil,
        unit: String? = nil,
        category: GroceryCategory = .other,
        isChecked: Bool = false,
        addedAt: Date = .now,
        sourceRecipeTitles: [String] = []
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.isChecked = isChecked
        self.addedAt = addedAt
        self.sourceRecipeTitles = sourceRecipeTitles
    }
}

extension GroceryItem {
    /// Normalised key used by the Phase 5 smart merge.
    var mergeKey: String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var sourceCaption: String? {
        guard !sourceRecipeTitles.isEmpty else { return nil }
        return sourceRecipeTitles.joined(separator: ", ")
    }
}
