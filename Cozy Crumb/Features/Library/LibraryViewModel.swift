//
//  LibraryViewModel.swift
//  Cozy Crumb
//
//  Owns the Cookbook's view state: what's typed in the search field, which
//  collection is filtering the grid, and how recipe grids are sorted.
//
//  Collections used to be folders you navigated into, drawn as a grid of cards
//  above the recipes. They are filters now: a row of chips that narrows the
//  one grid in place. The folder screen still exists and is still where a
//  collection is renamed or deleted — it is reached by long-pressing its chip
//  or through the sort menu — but the common case, "show me just the baking",
//  no longer costs a push and a back tap.
//
//  Filtering happens here rather than in a @Query predicate because searching
//  ingredient names means walking a relationship, which SwiftData predicates
//  handle poorly. At personal-cookbook scale this is nowhere near hot enough
//  to matter.
//

import Foundation
import SwiftUI

enum LibrarySort: String, CaseIterable, Identifiable, Sendable {
    case recentlyAdded
    case recentlyCooked
    case alphabetical
    case rating
    case quickest

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .recentlyAdded: "Recently added"
        case .recentlyCooked: "Recently cooked"
        case .alphabetical: "A–Z"
        case .rating: "Rating"
        case .quickest: "Quickest"
        }
    }

    nonisolated var symbol: String {
        switch self {
        case .recentlyAdded: "clock.arrow.circlepath"
        case .recentlyCooked: "flame"
        case .alphabetical: "textformat.abc"
        case .rating: "star"
        case .quickest: "hare"
        }
    }
}

@Observable
@MainActor
final class LibraryViewModel {
    var searchText = ""

    /// Which collection chip is lit, or nil for "All".
    ///
    /// Deliberately not persisted, unlike `sort`. A sort is how someone likes
    /// to read their cookbook; a collection filter is where they happen to be
    /// looking right now, and opening the app tomorrow inside "Baking" with no
    /// memory of having tapped it is how a cookbook appears to lose recipes.
    ///
    /// Held as the collection's id rather than the object so a deleted
    /// collection degrades to "All" on its own instead of keeping a filter
    /// alive against something that no longer exists.
    var selectedCollectionID: UUID?

    /// Remembered between launches — a cookbook someone sorted A–Z once
    /// shouldn't quietly go back to newest-first the next morning.
    var sort: LibrarySort = .recentlyAdded {
        didSet {
            guard sort != oldValue else { return }
            defaults.set(sort.rawValue, forKey: CozyDefaultsKey.librarySort)
        }
    }

    var hasSearch: Bool { !trimmedSearch.isEmpty }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let stored = defaults.string(forKey: CozyDefaultsKey.librarySort),
           let restored = LibrarySort(rawValue: stored) {
            sort = restored
        }
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Applies the collection filter, then search, then sort.
    ///
    /// The two filters compose rather than replacing each other: a chip plus a
    /// query narrows to both, and clearing the search leaves the chip where it
    /// was. They are separate pieces of state for exactly that reason.
    ///
    /// `collections` is walked in memory rather than asked for in a predicate,
    /// for the same reason the ingredient search below is — it is a
    /// relationship, and at personal-cookbook scale this is nowhere near hot
    /// enough to matter.
    func visibleRecipes(from recipes: [Recipe], in collectionID: UUID? = nil) -> [Recipe] {
        var result = recipes

        if let collectionID {
            result = result.filter { recipe in
                recipe.collections.contains { $0.id == collectionID }
            }
        }

        let query = trimmedSearch.lowercased()
        if !query.isEmpty {
            result = result.filter { $0.matches(query) }
        }

        return sortedRecipes(result)
    }

    func sortedRecipes(_ recipes: [Recipe]) -> [Recipe] {
        switch sort {
        case .recentlyAdded:
            recipes.sorted { $0.createdAt > $1.createdAt }

        case .recentlyCooked:
            // Never-cooked recipes sink to the bottom rather than jumping to
            // the top on a nil date.
            recipes.sorted { lhs, rhs in
                switch (lhs.lastCookedAt, rhs.lastCookedAt) {
                case let (l?, r?): l > r
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): lhs.createdAt > rhs.createdAt
                }
            }

        case .alphabetical:
            recipes.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        case .rating:
            recipes.sorted { lhs, rhs in
                (lhs.rating ?? 0, lhs.createdAt) > (rhs.rating ?? 0, rhs.createdAt)
            }

        case .quickest:
            recipes.sorted { lhs, rhs in
                // Unknown timings go last — "quickest" shouldn't promote a
                // recipe just because nobody filled in the time.
                (lhs.totalMinutes ?? .max) < (rhs.totalMinutes ?? .max)
            }
        }
    }
}

// MARK: - Search

extension Recipe {
    /// Matches title, tags and ingredient names — so "tahini" finds the recipe
    /// that uses it even when the title never mentions it (§8.9).
    nonisolated func matches(_ lowercasedQuery: String) -> Bool {
        if title.lowercased().contains(lowercasedQuery) { return true }
        if let summary, summary.lowercased().contains(lowercasedQuery) { return true }
        if tags.contains(where: { $0.lowercased().contains(lowercasedQuery) }) { return true }
        if ingredients.contains(where: { $0.name.lowercased().contains(lowercasedQuery) }) { return true }
        return false
    }
}
