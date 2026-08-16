//
//  SousChefContext.swift
//  Cozy Crumb
//
//  What the Sous Chef knows before you say anything.
//
//  A general-purpose model can tell anyone how to make carbonara. The only
//  thing it can do that a search engine can't is answer *for this kitchen* —
//  what's in the fridge, what's already planned, which of your saved recipes
//  is quick enough for tonight. So every turn carries a digest of the user's
//  own data, and the system prompt tells the model to prefer it over general
//  knowledge.
//
//  Two rules keep the digest honest:
//
//    1. It's built from the store, never from the model's memory of earlier
//       turns, so it can't drift out of date mid-conversation.
//    2. It's capped. A cookbook of four hundred recipes would swamp the
//       question being asked, so the list is trimmed to what's most likely to
//       matter — recently cooked, then recently added — and says how many it
//       left out rather than pretending that's all there is.
//
//  The digest itself is a plain value and its rendering is pure, so both can be
//  tested against fixtures with no store and no network. Only `build` touches
//  SwiftData, and it runs on the main actor because that is where the store is.
//

import Foundation

nonisolated struct SousChefContext: Sendable {

    /// How many recipes are described in full before the digest starts
    /// summarising. Enough to reason over, small enough to leave room for the
    /// conversation.
    nonisolated static let recipeLimit = 40
    nonisolated static let pantryLimit = 60
    nonisolated static let groceryLimit = 40

    nonisolated struct RecipeDigest: Sendable, Equatable {
        var title: String
        var minutes: Int?
        var servings: Int
        var tags: [String]
        var lastCookedAt: Date?
        var isFavorite: Bool
        /// A handful of the defining ingredients, so "what can I make with
        /// chicken and rice" has something to match on.
        var keyIngredients: [String]
    }

    nonisolated struct PlannedDigest: Sendable, Equatable {
        var day: String
        var slot: String
        var title: String
    }

    var recipes: [RecipeDigest]
    var totalRecipeCount: Int
    var pantry: [String]
    var groceries: [String]
    var plan: [PlannedDigest]
    var units: MeasurementSystem

    nonisolated init(
        recipes: [RecipeDigest] = [],
        totalRecipeCount: Int = 0,
        pantry: [String] = [],
        groceries: [String] = [],
        plan: [PlannedDigest] = [],
        units: MeasurementSystem = .asWritten
    ) {
        self.recipes = recipes
        self.totalRecipeCount = totalRecipeCount
        self.pantry = pantry
        self.groceries = groceries
        self.plan = plan
        self.units = units
    }

    // MARK: - Rendering

    /// The digest as the model sees it. Terse on purpose: this is read by a
    /// machine, and every line costs budget the actual question could use.
    nonisolated var promptText: String {
        var lines: [String] = []

        lines.append("THE USER'S COOKBOOK (\(totalRecipeCount) recipes saved)")

        if recipes.isEmpty {
            lines.append("- empty. They haven't saved anything yet.")
        } else {
            for recipe in recipes {
                lines.append("- \(describe(recipe))")
            }

            if totalRecipeCount > recipes.count {
                lines.append("- …and \(totalRecipeCount - recipes.count) more not listed here. "
                    + "Use find_recipes to search the rest rather than assuming they don't exist.")
            }
        }

        lines.append("")
        lines.append("IN THE PANTRY")
        lines.append(pantry.isEmpty ? "- nothing recorded" : "- " + pantry.joined(separator: ", "))

        lines.append("")
        lines.append("ON THE SHOPPING LIST")
        lines.append(groceries.isEmpty ? "- nothing yet" : "- " + groceries.joined(separator: ", "))

        lines.append("")
        lines.append("PLANNED THIS WEEK")
        if plan.isEmpty {
            lines.append("- nothing planned")
        } else {
            for meal in plan {
                lines.append("- \(meal.day) \(meal.slot): \(meal.title)")
            }
        }

        lines.append("")
        lines.append("They read measurements as: \(units.displayName).")

        return lines.joined(separator: "\n")
    }

    private nonisolated func describe(_ recipe: RecipeDigest) -> String {
        var parts = [recipe.title]

        if let minutes = recipe.minutes {
            parts.append("\(minutes) min")
        }
        parts.append("serves \(recipe.servings)")

        if !recipe.tags.isEmpty {
            parts.append(recipe.tags.prefix(4).joined(separator: "/"))
        }
        if recipe.isFavorite {
            parts.append("favourite")
        }
        if let lastCookedAt = recipe.lastCookedAt {
            let days = Int(Date.now.timeIntervalSince(lastCookedAt) / 86_400)
            parts.append(days <= 0 ? "cooked today" : "last cooked \(days)d ago")
        } else {
            parts.append("never cooked")
        }
        if !recipe.keyIngredients.isEmpty {
            parts.append("uses " + recipe.keyIngredients.prefix(6).joined(separator: ", "))
        }

        return parts.joined(separator: " · ")
    }
}

// MARK: - Building from the store

extension SousChefContext {
    /// Recently cooked first, then recently added: the recipes someone is most
    /// likely to be asking about are the ones they've been near lately.
    @MainActor
    static func build(
        recipes: [Recipe],
        pantry: [PantryItem],
        groceries: [GroceryItem],
        plannedMeals: [PlannedMeal],
        units: MeasurementSystem,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> SousChefContext {
        let ranked = recipes.sorted { lhs, rhs in
            switch (lhs.lastCookedAt, rhs.lastCookedAt) {
            case let (left?, right?): left > right
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): lhs.createdAt > rhs.createdAt
            }
        }

        let digests = ranked.prefix(recipeLimit).map { recipe in
            RecipeDigest(
                title: recipe.title,
                minutes: recipe.totalMinutes,
                servings: recipe.servings,
                tags: recipe.tags,
                lastCookedAt: recipe.lastCookedAt,
                isFavorite: recipe.isFavorite,
                keyIngredients: recipe.orderedIngredients
                    .filter { !$0.isSectionHeader }
                    .map(\.name)
                    .filter { !$0.isEmpty }
                    .prefix(6)
                    .map { $0 }
            )
        }

        let pantryNames = pantry
            .prefix(pantryLimit)
            .map { item -> String in
                let amount = FractionFormatter.quantityString(quantity: item.quantity, unit: item.unit)
                return amount.isEmpty ? item.name : "\(amount) \(item.name)"
            }

        let groceryNames = groceries
            .filter { !$0.isChecked }
            .prefix(groceryLimit)
            .map(\.name)

        let weekMeals = MealPlanService.meals(inWeekContaining: now, from: plannedMeals, calendar: calendar)

        let planDigests = weekMeals.compactMap { meal -> PlannedDigest? in
            guard let title = meal.recipe?.title else { return nil }
            return PlannedDigest(
                day: meal.date.formatted(.dateTime.weekday(.abbreviated)),
                slot: meal.slot.displayName,
                title: title
            )
        }

        return SousChefContext(
            recipes: Array(digests),
            totalRecipeCount: recipes.count,
            pantry: Array(pantryNames),
            groceries: Array(groceryNames),
            plan: planDigests,
            units: units
        )
    }
}
