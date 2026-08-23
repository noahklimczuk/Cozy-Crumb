//
//  PantryStaples.swift
//  Cozy Crumb
//
//  The things almost every kitchen has, which nobody should ever be asked
//  about.
//
//  This list already existed, as `IngredientCanonicalizer.staples`, and it is
//  built on rather than copied: that set is what the recommendation engine
//  uses to stop marking a recipe "missing 3 ingredients" because the user
//  never thought to add salt. Two staples lists would drift, and the drift
//  would show up as a recipe scoring differently depending on which code path
//  asked — the worst kind of bug to find.
//
//  What this adds on top is the things a *pantry* considers permanent but a
//  recipe matcher does not care about, and the user's own edits.
//
//  Edits live in UserDefaults rather than a model. There are at most a few
//  dozen of them, they are pure preference, and giving them a `@Model` would
//  mean a migration and a fetch for something that is a list of strings.
//

import Foundation

nonisolated enum PantryStaples {

    // MARK: - Keys

    nonisolated static let addedKey = "pantry.staples.added"
    nonisolated static let removedKey = "pantry.staples.removed"
    nonisolated static let seededKey = "pantry.staples.seeded"

    // MARK: - The list

    /// Staples the recipe matcher already knew about, plus the ones a kitchen
    /// treats as permanent even though a recipe would name them properly.
    ///
    /// All canonical forms — run anything from outside through
    /// `IngredientCanonicalizer.canonical(_:)` before comparing.
    nonisolated static let additions: Set<String> = [
        "soy sauce", "fish sauce", "honey", "maple syrup", "mustard",
        "ketchup", "mayonnaise", "hot sauce", "sesame oil", "rice vinegar",
        "balsamic vinegar", "worcestershire sauce", "tomato paste",
        "stock cube", "bay leaf", "cinnamon", "cumin", "paprika",
        "chilli flake", "oregano", "thyme", "garlic powder", "onion powder",
        "curry powder", "turmeric", "coriander seed", "nutmeg", "vanilla",
        "yeast", "rice", "pasta", "lentil", "chickpea", "tinned tomato",
        "peanut butter", "jam", "tea", "coffee"
    ]

    /// The full default list: the matcher's staples plus the additions above.
    nonisolated static let defaults: Set<String> = IngredientCanonicalizer.staples
        .union(additions)

    /// The list in force, after the user's own additions and removals.
    nonisolated static func current(
        defaults store: UserDefaults = .standard
    ) -> Set<String> {
        let added = Set(store.stringArray(forKey: addedKey) ?? [])
        let removed = Set(store.stringArray(forKey: removedKey) ?? [])
        return defaults.union(added).subtracting(removed)
    }

    /// Whether a name — raw or canonical — is treated as always-in.
    nonisolated static func contains(
        _ raw: String,
        defaults store: UserDefaults = .standard
    ) -> Bool {
        let list = current(defaults: store)
        let canonical = IngredientCanonicalizer.canonical(raw)
        return list.contains(canonical) || list.contains(IngredientCanonicalizer.surfaceForm(raw))
    }

    // MARK: - Editing

    /// Adds a food to the staples list. Stored canonically so "Olive Oil" and
    /// "olive oil" are one entry.
    nonisolated static func add(_ raw: String, defaults store: UserDefaults = .standard) {
        let canonical = IngredientCanonicalizer.canonical(raw)
        guard !canonical.isEmpty else { return }

        // Un-remove before adding, so re-adding something the user took out
        // restores it rather than leaving it in both lists.
        var removed = Set(store.stringArray(forKey: removedKey) ?? [])
        if removed.remove(canonical) != nil {
            store.set(Array(removed).sorted(), forKey: removedKey)
        }

        guard !defaults.contains(canonical) else { return }

        var added = Set(store.stringArray(forKey: addedKey) ?? [])
        guard added.insert(canonical).inserted else { return }
        store.set(Array(added).sorted(), forKey: addedKey)
    }

    /// Takes a food off the staples list.
    nonisolated static func remove(_ raw: String, defaults store: UserDefaults = .standard) {
        let canonical = IngredientCanonicalizer.canonical(raw)
        guard !canonical.isEmpty else { return }

        var added = Set(store.stringArray(forKey: addedKey) ?? [])
        if added.remove(canonical) != nil {
            store.set(Array(added).sorted(), forKey: addedKey)
        }

        guard defaults.contains(canonical) else { return }

        var removed = Set(store.stringArray(forKey: removedKey) ?? [])
        guard removed.insert(canonical).inserted else { return }
        store.set(Array(removed).sorted(), forKey: removedKey)
    }

    /// Puts the list back to the shipped default.
    nonisolated static func resetEdits(defaults store: UserDefaults = .standard) {
        store.removeObject(forKey: addedKey)
        store.removeObject(forKey: removedKey)
    }

    // MARK: - Seeding

    /// The staples to write into a fresh pantry, with a sensible aisle each.
    ///
    /// Deliberately shorter than `defaults`: a first run that drops forty rows
    /// into an empty pantry reads as clutter, and the point of the tier is
    /// that these are the rows nobody looks at. The rest of the list still
    /// counts as a staple for matching — it just does not get a row until
    /// something actually puts one there.
    nonisolated static let seeds: [(name: String, category: GroceryCategory)] = [
        ("Salt", .condiment),
        ("Black pepper", .condiment),
        ("Olive oil", .condiment),
        ("Vegetable oil", .condiment),
        ("Butter", .dairy),
        ("Plain flour", .pantry),
        ("Sugar", .pantry),
        ("Rice", .pantry),
        ("Pasta", .pantry),
        ("Soy sauce", .condiment),
        ("Vinegar", .condiment),
        ("Baking powder", .pantry)
    ]
}
