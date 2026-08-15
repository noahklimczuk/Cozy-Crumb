//
//  LibraryViewModel.swift
//  Cozy Crumb
//
//  Owns the Library's view state: what's typed in the search field, how the
//  grid is sorted, and which collection is filtering it.
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
    var sort: LibrarySort = .recentlyAdded
    var selectedCollectionID: UUID?

    var isFiltering: Bool {
        !trimmedSearch.isEmpty || selectedCollectionID != nil
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Applies the collection filter, then the search, then the sort.
    func visibleRecipes(from recipes: [Recipe]) -> [Recipe] {
        var result = recipes

        if let selectedCollectionID {
            result = result.filter { recipe in
                recipe.collections.contains { $0.id == selectedCollectionID }
            }
        }

        let query = trimmedSearch.lowercased()
        if !query.isEmpty {
            result = result.filter { $0.matches(query) }
        }

        return sorted(result)
    }

    private func sorted(_ recipes: [Recipe]) -> [Recipe] {
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
