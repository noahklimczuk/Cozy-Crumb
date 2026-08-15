//
//  GroceryCategory.swift
//  Cozy Crumb
//
//  Shared by Ingredient, GroceryItem and PantryItem. Drives the pastel section
//  headers on the grocery list and the chip colours in the pantry.
//
//  Every member is explicitly `nonisolated`. The target defaults actor
//  isolation to MainActor, but @Model types are nonisolated and read these
//  directly (GroceryList.itemsByCategory sorts on sortOrder), so leaving them
//  isolated makes them unreachable from the model layer. None of this is
//  anything but pure data.
//

import SwiftUI

enum GroceryCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case produce
    case dairy
    case meat
    case pantry
    case frozen
    case condiment
    case bakery
    case other

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .produce: "Produce"
        case .dairy: "Dairy"
        case .meat: "Meat & Fish"
        case .pantry: "Pantry"
        case .frozen: "Frozen"
        case .condiment: "Condiments"
        case .bakery: "Bakery"
        case .other: "Other"
        }
    }

    nonisolated var symbol: String {
        switch self {
        case .produce: "carrot"
        case .dairy: "drop"
        case .meat: "fish"
        case .pantry: "shippingbox"
        case .frozen: "snowflake"
        case .condiment: "takeoutbag.and.cup.and.straw"
        case .bakery: "birthday.cake"
        case .other: "basket"
        }
    }

    nonisolated var tint: Color {
        switch self {
        case .produce: CozyColor.mint
        case .dairy: CozyColor.sky
        case .meat: CozyColor.blush
        case .pantry: CozyColor.butter
        case .frozen: CozyColor.sky
        case .condiment: CozyColor.peach
        case .bakery: CozyColor.butter
        case .other: CozyColor.sage
        }
    }

    /// Display order on the grocery list — roughly a supermarket walk.
    nonisolated var sortOrder: Int {
        switch self {
        case .produce: 0
        case .bakery: 1
        case .meat: 2
        case .dairy: 3
        case .frozen: 4
        case .pantry: 5
        case .condiment: 6
        case .other: 7
        }
    }
}
