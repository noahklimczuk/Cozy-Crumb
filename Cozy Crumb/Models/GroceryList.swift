//
//  GroceryList.swift
//  Cozy Crumb
//
//  The app keeps a single active list. The model is a list rather than a bare
//  item collection so multiple named lists stay possible later without a
//  migration.
//

import Foundation
import SwiftData

@Model
final class GroceryList {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \GroceryItem.list)
    var items: [GroceryItem]

    init(
        id: UUID = UUID(),
        name: String = "Groceries",
        createdAt: Date = .now,
        items: [GroceryItem] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.items = items
    }
}

extension GroceryList {
    var outstandingItems: [GroceryItem] {
        items.filter { !$0.isChecked }
    }

    var completedItems: [GroceryItem] {
        items.filter(\.isChecked)
    }

    /// Grouped for the sectioned list, in supermarket-walk order.
    var itemsByCategory: [(category: GroceryCategory, items: [GroceryItem])] {
        Dictionary(grouping: outstandingItems, by: \.category)
            .map { (category: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.category.sortOrder < $1.category.sortOrder }
    }
}
