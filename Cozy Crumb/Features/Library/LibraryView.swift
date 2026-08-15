//
//  LibraryView.swift
//  Cozy Crumb
//
//  The home tab. Phase 2 renders the grid; Phase 3 adds search, sort,
//  collection chips, and navigation into Recipe Detail.
//

import Foundation
import SwiftData
import SwiftUI
import os

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Recipe.createdAt, order: .reverse)
    private var recipes: [Recipe]

    private let columns = [
        GridItem(.flexible(), spacing: CozySpacing.m),
        GridItem(.flexible(), spacing: CozySpacing.m)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if recipes.isEmpty {
                    EmptyStateView(
                        title: "Your cookbook's a blank page.",
                        message: "Paste a link to get started — I'll do the tidying up.",
                        pose: .sleeping
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    grid
                }
            }
            .background { BlobBackground() }
            .navigationTitle("Library")
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: CozySpacing.m) {
                ForEach(Array(recipes.enumerated()), id: \.element.id) { index, recipe in
                    RecipeCard(recipe: recipe, index: index) {
                        toggleFavorite(recipe)
                    }
                }
            }
            .padding(CozySpacing.l)
        }
    }

    private func toggleFavorite(_ recipe: Recipe) {
        recipe.isFavorite.toggle()
        recipe.touch()

        do {
            try modelContext.save()
        } catch {
            Log.data.error("Could not save favourite: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Previews

#Preview("Library") {
    LibraryView()
        .modelContainer(PreviewData.container)
}

#Preview("Library — dark") {
    LibraryView()
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}

#Preview("Library — empty") {
    LibraryView()
        .modelContainer(PreviewData.emptyContainer)
}
