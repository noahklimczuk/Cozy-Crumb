//
//  PantryTier.swift
//  Cozy Crumb
//
//  The pantry's vocabulary: what kind of thing an item is, where it lives, and
//  how much of it there is when nobody counted.
//
//  The tier is the structural idea the revamp turns on. Treating a bag of
//  flour and a bunch of cilantro as the same kind of object is why pantry
//  features feel like chores: the flour needs no attention and gets asked
//  about anyway, and the cilantro needs attention and is buried among fifty
//  rows of things that never change.
//
//  `nonisolated` throughout for the same reason as `GroceryCategory` — @Model
//  types are nonisolated and read these directly, and the target defaults
//  types to MainActor.
//

import Foundation

// MARK: - Tier

nonisolated enum PantryTier: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Salt, oil, flour, common spices. Assumed present, permanently. Never
    /// decays, never nags, never counts against a recipe. The user can flag
    /// one as out, which is the only time a staple is ever missing.
    case staple

    /// The real working inventory: perishables, proteins, produce, dairy,
    /// anything opened. This is what decays and what Use-It-Up works on, and
    /// it is where nearly all of the app's attention goes.
    case stock

    /// Bought for one specific recipe and not part of the rotation. Miso paste
    /// for that one soup. Tracked, but excluded from running-low nudges and
    /// restock prediction — a cadence inferred from a single purchase is noise.
    case someday

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .staple: "Always in"
        case .stock: "In stock"
        case .someday: "One-off"
        }
    }

    nonisolated var symbol: String {
        switch self {
        case .staple: "pin.fill"
        case .stock: "basket"
        case .someday: "sparkle"
        }
    }

    /// Whether confidence in this item falls off over time.
    ///
    /// Staples are the exception by definition: the whole point of the tier is
    /// that nobody should ever be asked whether they still have salt.
    nonisolated var decays: Bool {
        self != .staple
    }

    /// Whether this item takes part in restock prediction and running-low
    /// nudges. A one-off has no cadence to learn and a staple is topped up on
    /// its own schedule.
    nonisolated var predictsRestock: Bool {
        self == .stock
    }
}

// MARK: - Loose amount

/// How much is left, when nobody measured — which is nearly always.
///
/// Quantity tracking always drifts: you cannot know that half the onion got
/// used. Rather than pretending to a precision the data never has, an item can
/// carry one of four rough levels instead of, or as well as, a number.
///
/// The `some` case is spelled `enough` in Swift and `"some"` on disk. Naming
/// it `some` would collide with `Optional.some` at every `LooseAmount?` call
/// site, which is where this value nearly always lives; the raw value is what
/// gets persisted and read by anything outside this file, so it keeps the name
/// the spec gives it.
nonisolated enum LooseAmount: String, Codable, CaseIterable, Identifiable, Sendable {
    case plenty
    case enough = "some"
    case runningLow
    case almostOut

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .plenty: "Plenty"
        case .enough: "Some left"
        case .runningLow: "Running low"
        case .almostOut: "Almost out"
        }
    }

    /// Ordered from most to least, so a step down is the next one along.
    nonisolated static let descending: [LooseAmount] = [.plenty, .enough, .runningLow, .almostOut]

    /// One level less. Returns nil from `.almostOut`, which means "gone" —
    /// cooking with the last of something is how most things actually run out,
    /// and the caller decides whether that archives the item or just flags it.
    nonisolated func steppedDown() -> LooseAmount? {
        guard let index = Self.descending.firstIndex(of: self),
              index + 1 < Self.descending.count else { return nil }
        return Self.descending[index + 1]
    }

    /// Whether this level is low enough to be worth offering to the grocery
    /// list.
    nonisolated var isLow: Bool {
        self == .runningLow || self == .almostOut
    }
}

// MARK: - Location

/// Which door you open to find it. Separate from `GroceryCategory`, which says
/// which aisle you bought it in — frozen peas are produce you bought in the
/// frozen aisle and keep in the freezer, and all three facts are useful.
nonisolated enum StorageLocation: String, Codable, CaseIterable, Identifiable, Sendable {
    case fridge
    case freezer
    case pantry
    case counter

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .fridge: "Fridge"
        case .freezer: "Freezer"
        case .pantry: "Pantry"
        case .counter: "Counter"
        }
    }

    nonisolated var symbol: String {
        switch self {
        case .fridge: "refrigerator"
        case .freezer: "snowflake"
        case .pantry: "cabinet"
        case .counter: "fork.knife"
        }
    }

    /// A first guess from the aisle it came off. Wrong often enough that the
    /// user can change it, right often enough that nobody has to.
    nonisolated static func inferred(from category: GroceryCategory) -> StorageLocation {
        switch category {
        case .frozen: .freezer
        case .dairy, .meat: .fridge
        case .produce: .fridge
        case .pantry, .condiment, .bakery, .other: .pantry
        }
    }
}
