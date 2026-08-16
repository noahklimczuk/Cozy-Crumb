//
//  MealPlanService.swift
//  Cozy Crumb
//
//  Week arithmetic and the plan → grocery list hand-off.
//
//  Weeks follow the user's own calendar, so a locale that starts on Sunday
//  gets a Sunday column and one that starts on Monday gets a Monday column.
//

import Foundation
import SwiftData
import os

enum MealPlanService {

    // MARK: - Weeks

    static func startOfWeek(containing date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    static func days(ofWeekContaining date: Date, calendar: Calendar = .current) -> [Date] {
        let start = startOfWeek(containing: date, calendar: calendar)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func week(offsetBy weeks: Int, from date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .weekOfYear, value: weeks, to: date) ?? date
    }

    /// "10 – 16 Aug", or "28 Jul – 3 Aug" when the week straddles a month.
    static func weekLabel(for date: Date, calendar: Calendar = .current) -> String {
        let days = days(ofWeekContaining: date, calendar: calendar)
        guard let first = days.first, let last = days.last else { return "" }

        let sameMonth = calendar.isDate(first, equalTo: last, toGranularity: .month)
        let start = first.formatted(.dateTime.day().month(sameMonth ? .omitted : .abbreviated))
        let end = last.formatted(.dateTime.day().month(.abbreviated))

        return "\(start) – \(end)"
    }

    static func isCurrentWeek(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(date, equalTo: .now, toGranularity: .weekOfYear)
    }

    // MARK: - Reading

    /// Every meal planned in the week containing `date`, oldest day first and
    /// breakfast before dinner within a day.
    static func meals(
        inWeekContaining date: Date,
        from all: [PlannedMeal],
        calendar: Calendar = .current
    ) -> [PlannedMeal] {
        let days = days(ofWeekContaining: date, calendar: calendar)
        guard let first = days.first, let last = days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return [] }

        return all
            .filter { $0.date >= first && $0.date < end }
            .sorted { sortsBefore($0, $1) }
    }

    static func meals(on day: Date, from all: [PlannedMeal], calendar: Calendar = .current) -> [PlannedMeal] {
        all
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { sortsBefore($0, $1) }
    }

    private static func sortsBefore(_ lhs: PlannedMeal, _ rhs: PlannedMeal) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.slot != rhs.slot { return lhs.slot.sortOrder < rhs.slot.sortOrder }
        return lhs.createdAt < rhs.createdAt
    }

    // MARK: - Writing

    @discardableResult
    static func add(
        _ recipe: Recipe,
        on day: Date,
        slot: MealSlot,
        servings: Int? = nil,
        in context: ModelContext,
        calendar: Calendar = .current
    ) -> PlannedMeal {
        let meal = PlannedMeal(
            date: calendar.startOfDay(for: day),
            slot: slot,
            servings: servings ?? max(1, recipe.servings),
            recipe: recipe
        )

        context.insert(meal)
        save(context, "planned meal")
        return meal
    }

    static func remove(_ meal: PlannedMeal, in context: ModelContext) {
        context.delete(meal)
        save(context, "remove planned meal")
    }

    static func clear(_ meals: [PlannedMeal], in context: ModelContext) {
        for meal in meals {
            context.delete(meal)
        }
        save(context, "clear week")
    }

    /// Moves a meal to another day or slot rather than deleting and re-adding,
    /// so its servings override survives.
    static func move(
        _ meal: PlannedMeal,
        to day: Date,
        slot: MealSlot,
        in context: ModelContext,
        calendar: Calendar = .current
    ) {
        meal.date = calendar.startOfDay(for: day)
        meal.slot = slot
        save(context, "move planned meal")
    }

    // MARK: - Groceries

    /// Everything the week needs, merged into one shopping list. Each meal is
    /// costed at the servings it was planned for, not the recipe's original.
    static func groceryLines(for meals: [PlannedMeal]) -> [GroceryLineItem] {
        let lines = meals.flatMap { meal -> [GroceryLineItem] in
            guard let recipe = meal.recipe else { return [] }
            return GroceryService.lineItems(from: recipe, servings: meal.servings)
        }

        return GroceryMerge.folded(lines)
    }

    // MARK: - Plumbing

    private static func save(_ context: ModelContext, _ what: String) {
        do {
            try context.save()
        } catch {
            Log.data.error(
                "Could not save \(what, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
