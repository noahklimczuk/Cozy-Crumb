//
//  PantryItem.swift
//  Cozy Crumb
//
//  What the user currently has. Feeds the Sous Chef's "what can I make?" and
//  is populated by hand, by a confirmed fridge photo, or by checking an item
//  off the grocery list.
//

import Foundation
import SwiftData

enum PantryItemSource: String, Codable, CaseIterable, Sendable {
    case manual
    case fridgePhoto
    case groceryCheckoff

    nonisolated var displayName: String {
        switch self {
        case .manual: "Added by hand"
        case .fridgePhoto: "Spotted in a photo"
        case .groceryCheckoff: "Ticked off the list"
        }
    }
}

@Model
final class PantryItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var quantity: Double?
    var unit: String?
    var category: GroceryCategory
    var addedAt: Date
    var expiresAt: Date?
    var source: PantryItemSource

    init(
        id: UUID = UUID(),
        name: String,
        quantity: Double? = nil,
        unit: String? = nil,
        category: GroceryCategory = .other,
        addedAt: Date = .now,
        expiresAt: Date? = nil,
        source: PantryItemSource = .manual
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.addedAt = addedAt
        self.expiresAt = expiresAt
        self.source = source
    }
}

extension PantryItem {
    /// Days until expiry, or nil when no date is set.
    func daysUntilExpiry(now: Date = .now) -> Int? {
        guard let expiresAt else { return nil }
        let days = Calendar.current.dateComponents([.day], from: now, to: expiresAt).day
        return days
    }

    /// Items within three days float to the top with an amber tint (§5.8).
    func isExpiringSoon(now: Date = .now) -> Bool {
        guard let days = daysUntilExpiry(now: now) else { return false }
        return days <= 3
    }

    func isExpired(now: Date = .now) -> Bool {
        guard let days = daysUntilExpiry(now: now) else { return false }
        return days < 0
    }
}
