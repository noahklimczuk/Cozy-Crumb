//
//  PlannedMeal.swift
//  Cozy Crumb
//
//  One recipe pencilled in for one meal on one day. The week planner is just
//  a view over these.
//
//  `date` is always the start of its day, so two meals planned for the same
//  Tuesday compare equal however they were created.
//

import Foundation
import SwiftData

enum MealSlot: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast
    case lunch
    case dinner

    // nonisolated for the same reason as GroceryCategory: @Model types are
    // nonisolated and read these directly.
    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        }
    }

    nonisolated var symbol: String {
        switch self {
        case .breakfast: "sun.horizon"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        }
    }

    nonisolated var sortOrder: Int {
        switch self {
        case .breakfast: 0
        case .lunch: 1
        case .dinner: 2
        }
    }
}

@Model
final class PlannedMeal {
    @Attribute(.unique) var id: UUID

    /// Start of the day this meal is planned for.
    var date: Date
    var slot: MealSlot
    /// How many the user is cooking for, which need not be what the recipe
    /// was written for.
    var servings: Int
    var createdAt: Date

    var recipe: Recipe?

    init(
        id: UUID = UUID(),
        date: Date,
        slot: MealSlot = .dinner,
        servings: Int,
        createdAt: Date = .now,
        recipe: Recipe? = nil
    ) {
        self.id = id
        self.date = date
        self.slot = slot
        self.servings = servings
        self.createdAt = createdAt
        self.recipe = recipe
    }
}
