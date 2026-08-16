//
//  SousChefTools.swift
//  Cozy Crumb
//
//  The difference between an assistant and a chatbot.
//
//  A chatbot says "you'll want butter, eggs and flour — add those to your
//  list". An assistant adds them. These are the functions the model is allowed
//  to ask for, and the code that runs them against the real store.
//
//  Three rules, because a model with write access to someone's data needs
//  them:
//
//    1. The tools are deliberately few and blunt. Search the cookbook, add to
//       the shopping list, put a meal on the plan. Nothing here deletes,
//       overwrites or edits a recipe — a misunderstanding should cost the user
//       a tap to undo, never a lost recipe.
//    2. A tool call that doesn't match anything says so plainly, and the model
//       is told to relay that rather than pretend it worked. "I couldn't find
//       a recipe called that" is a better answer than a confident lie.
//    3. Every run reports back in the transcript, so the user can see what was
//       done to their data without going to look.
//

import Foundation
import SwiftData
import os

// MARK: - Declarations

nonisolated enum SousChefTools {

    nonisolated static let findRecipes = "find_recipes"
    nonisolated static let addToGroceryList = "add_to_grocery_list"
    nonisolated static let planMeal = "plan_meal"

    /// Descriptions are prompts, not documentation — the model picks a
    /// function by reading them, so they say when *not* to call as well.
    nonisolated static var declarations: [GeminiFunctionDeclaration] {
        [
            GeminiFunctionDeclaration(
                name: findRecipes,
                description: """
                Search the user's saved recipes by words in the title, tags or \
                ingredients, optionally filtered by how long they take. Use \
                this when the cookbook summary you were given may not list \
                every recipe, or to check something exists before suggesting \
                it. Do not use it for recipes the user has not saved.
                """,
                parameters: .record(
                    [
                        ("query", .text("Words to match — an ingredient, a cuisine, part of a title")),
                        ("max_minutes", .whole("Only recipes at or under this total time", nullable: true))
                    ],
                    required: ["query"]
                )
            ),
            GeminiFunctionDeclaration(
                name: addToGroceryList,
                description: """
                Add items to the user's shopping list. Only call this when they \
                have asked for something to be added, or agreed to it. Amounts \
                are optional — leave them out rather than guessing.
                """,
                parameters: .record(
                    [
                        ("items", .list(of: .record(
                            [
                                ("name", .text("What to buy, e.g. \"unsalted butter\"")),
                                ("quantity", .decimal("How much, as a number", nullable: true)),
                                ("unit", .text("g, ml, tbsp, cup, clove, piece…", nullable: true))
                            ],
                            required: ["name"]
                        )))
                    ],
                    required: ["items"]
                )
            ),
            GeminiFunctionDeclaration(
                name: planMeal,
                description: """
                Put one of the user's saved recipes on the meal plan. Only call \
                this when they have asked for something to be planned, or \
                agreed to it. The recipe must already be in their cookbook.
                """,
                parameters: .record(
                    [
                        ("recipe_title", .text("The saved recipe's title, as written in the cookbook")),
                        ("days_from_today", .whole("0 for today, 1 for tomorrow, up to 13")),
                        ("meal", .text("breakfast, lunch or dinner")),
                        ("servings", .whole("How many people, if they said", nullable: true))
                    ],
                    required: ["recipe_title", "days_from_today", "meal"]
                )
            )
        ]
    }

    nonisolated static var tool: GeminiTool {
        GeminiTool(functionDeclarations: declarations)
    }
}

// MARK: - Running them

/// What a tool run produced: one line for the model to reason with, and one
/// for the user to see in the transcript.
nonisolated struct SousChefToolOutcome: Sendable, Equatable {
    /// Fed back to the model as the function's result.
    var forModel: String
    /// Shown in the chat as a receipt. Nil for read-only lookups, which don't
    /// need announcing.
    var receipt: String?

    nonisolated init(forModel: String, receipt: String? = nil) {
        self.forModel = forModel
        self.receipt = receipt
    }
}

@MainActor
struct SousChefToolRunner {
    let context: ModelContext

    func run(_ call: GeminiFunctionCall) -> SousChefToolOutcome {
        switch call.name {
        case SousChefTools.findRecipes:
            findRecipes(call)
        case SousChefTools.addToGroceryList:
            addToGroceryList(call)
        case SousChefTools.planMeal:
            planMeal(call)
        default:
            SousChefToolOutcome(forModel: "There's no tool called \(call.name).")
        }
    }

    // MARK: - Search

    private func findRecipes(_ call: GeminiFunctionCall) -> SousChefToolOutcome {
        let query = (call["query"]?.stringValue ?? "").lowercased()
        let maxMinutes = call["max_minutes"]?.intValue

        let all = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []

        let matches = all.filter { recipe in
            guard query.isEmpty || recipe.matches(query) else { return false }
            guard let maxMinutes else { return true }
            guard let minutes = recipe.totalMinutes else { return false }
            return minutes <= maxMinutes
        }

        guard !matches.isEmpty else {
            return SousChefToolOutcome(
                forModel: "No saved recipe matches \"\(query)\"\(maxMinutes.map { " under \($0) minutes" } ?? "")."
            )
        }

        let lines = matches.prefix(8).map { recipe -> String in
            var parts = [recipe.title]
            if let minutes = recipe.totalMinutes { parts.append("\(minutes) min") }
            parts.append("serves \(recipe.servings)")
            if !recipe.tags.isEmpty { parts.append(recipe.tags.prefix(3).joined(separator: "/")) }
            return parts.joined(separator: " · ")
        }

        return SousChefToolOutcome(
            forModel: "Saved recipes matching \"\(query)\":\n" + lines.joined(separator: "\n")
        )
    }

    // MARK: - Shopping

    private func addToGroceryList(_ call: GeminiFunctionCall) -> SousChefToolOutcome {
        let items = call["items"]?.arrayValue ?? []

        let lines: [GroceryLineItem] = items.compactMap { item in
            guard let name = item["name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return nil }

            return GroceryLineItem(
                name: name,
                quantity: item["quantity"]?.doubleValue,
                unit: item["unit"]?.stringValue,
                category: GroceryCategoryGuesser.category(for: name)
            )
        }

        guard !lines.isEmpty else {
            return SousChefToolOutcome(forModel: "Nothing was added — no item names came through.")
        }

        let list = GroceryService.activeList(in: context)
        let outcome = GroceryService.add(lines, to: list, in: context)
        Haptics.notify(.success)

        let names = lines.map(\.name).joined(separator: ", ")
        let summary = outcome.summary ?? "\(outcome.total) added"

        Log.ai.info("Sous Chef added \(lines.count, privacy: .public) grocery lines")

        return SousChefToolOutcome(
            forModel: "Added to the shopping list: \(names). (\(summary))",
            receipt: "Added to your list: \(names)"
        )
    }

    // MARK: - Planning

    private func planMeal(_ call: GeminiFunctionCall) -> SousChefToolOutcome {
        let title = call["recipe_title"]?.stringValue ?? ""
        let offset = min(max(call["days_from_today"]?.intValue ?? 0, 0), 13)
        let slot = MealSlot.named(call["meal"]?.stringValue) ?? .dinner
        let servings = call["servings"]?.intValue

        let all = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []

        guard let recipe = Self.bestMatch(for: title, in: all) else {
            return SousChefToolOutcome(
                forModel: "There's no saved recipe called \"\(title)\", so nothing was planned. "
                    + "Tell the user, and suggest one of their saved recipes instead of inventing one."
            )
        }

        let day = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
        _ = MealPlanService.add(recipe, on: day, slot: slot, servings: servings, in: context)
        Haptics.notify(.success)

        let when = day.formatted(.dateTime.weekday(.wide))

        return SousChefToolOutcome(
            forModel: "Planned \(recipe.title) for \(slot.displayName.lowercased()) on \(when).",
            receipt: "Planned \(recipe.title) — \(when) \(slot.displayName.lowercased())"
        )
    }

    /// Exact title first, then a contains match either way round, so "the miso
    /// salmon" finds "Miso Glazed Salmon" without matching everything.
    nonisolated static func bestMatch(for title: String, in recipes: [Recipe]) -> Recipe? {
        let needle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }

        if let exact = recipes.first(where: { $0.title.lowercased() == needle }) {
            return exact
        }

        if let contained = recipes.first(where: { $0.title.lowercased().contains(needle) }) {
            return contained
        }

        return recipes.first { needle.contains($0.title.lowercased()) }
    }
}

// MARK: - Slots by name

extension MealSlot {
    /// The model writes "dinner", not `.dinner`.
    nonisolated static func named(_ name: String?) -> MealSlot? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }

        return allCases.first { $0.rawValue.lowercased() == name || $0.displayName.lowercased() == name }
    }
}
