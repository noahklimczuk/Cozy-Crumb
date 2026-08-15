//
//  LibraryView.swift
//  Cozy Crumb
//
//  The home tab: sticky search, collection chips, sortable grid.
//

import Foundation
import SwiftData
import SwiftUI
import os

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var recipes: [Recipe]
    @Query(sort: \RecipeCollection.createdAt) private var collections: [RecipeCollection]

    @State private var viewModel = LibraryViewModel()
    @State private var pendingDeletion: Recipe?
    @State private var isNamingCollection = false
    @State private var newCollectionName = ""
    @State private var isImporting = false
    @State private var isEnteringManually = false

    private let columns = [
        GridItem(.flexible(), spacing: CozySpacing.m),
        GridItem(.flexible(), spacing: CozySpacing.m)
    ]

    private var visibleRecipes: [Recipe] {
        viewModel.visibleRecipes(from: recipes)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                content
            }
            .background { BlobBackground() }
            .navigationTitle("Library")
            .toolbar {
                sortMenu
                addMenu
            }
            .sheet(isPresented: $isImporting) {
                ImportFlowView()
            }
            .sheet(isPresented: $isEnteringManually) {
                ImportFlowView(startsInManualEntry: true)
            }
            .confirmationDialog(
                "Delete this recipe?",
                isPresented: .init(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let pendingDeletion { delete(pendingDeletion) }
                    pendingDeletion = nil
                }
                Button("Keep it", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text(pendingDeletion.map { "\($0.title) will be gone for good." } ?? "")
            }
            .alert("New collection", isPresented: $isNamingCollection) {
                TextField("Weeknight, Baking, Mom's…", text: $newCollectionName)
                Button("Create", action: createCollection)
                Button("Cancel", role: .cancel) { newCollectionName = "" }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: CozySpacing.m) {
            CozyTextField(
                placeholder: "Search recipes and ingredients",
                text: $viewModel.searchText,
                systemImage: "magnifyingglass",
                submitLabel: .search
            )
            .padding(.horizontal, CozySpacing.l)

            collectionChips
        }
        .padding(.vertical, CozySpacing.m)
        .background(.ultraThinMaterial)
    }

    private var collectionChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: CozySpacing.s) {
                SelectableChip(
                    text: "All",
                    tint: CozyColor.creamDeep,
                    isSelected: viewModel.selectedCollectionID == nil
                ) {
                    viewModel.selectedCollectionID = nil
                }

                ForEach(collections) { collection in
                    SelectableChip(
                        text: collection.name,
                        tint: collection.tint,
                        isSelected: viewModel.selectedCollectionID == collection.id
                    ) {
                        viewModel.selectedCollectionID =
                            viewModel.selectedCollectionID == collection.id ? nil : collection.id
                    }
                }

                SelectableChip(text: "New", systemImage: "plus", tint: CozyColor.card, isSelected: false) {
                    isNamingCollection = true
                }
            }
            .padding(.horizontal, CozySpacing.l)
        }
        .scrollIndicators(.hidden)
    }

    @ToolbarContentBuilder
    private var addMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    isImporting = true
                } label: {
                    Label("Paste a link", systemImage: "link")
                }
                Button {
                    isEnteringManually = true
                } label: {
                    Label("Type one in", systemImage: "square.and.pencil")
                }
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .accessibilityLabel("Add a recipe")
        }
    }

    @ToolbarContentBuilder
    private var sortMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort", selection: $viewModel.sort) {
                    ForEach(LibrarySort.allCases) { option in
                        Label(option.displayName, systemImage: option.symbol).tag(option)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down.circle")
            }
            .accessibilityLabel("Sort recipes")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if recipes.isEmpty {
            EmptyStateView(
                title: "Your cookbook's a blank page.",
                message: "Paste a link to get started — I'll do the tidying up.",
                pose: .sleeping,
                actionTitle: "Paste a link",
                action: { isImporting = true }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleRecipes.isEmpty {
            EmptyStateView(
                title: "Nothing matches.",
                message: "Try a different word, or clear the filters and start again.",
                pose: .idle,
                actionTitle: "Clear filters",
                action: clearFilters
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: CozySpacing.m) {
                ForEach(Array(visibleRecipes.enumerated()), id: \.element.id) { index, recipe in
                    NavigationLink {
                        RecipeDetailView(recipe: recipe)
                    } label: {
                        RecipeCard(recipe: recipe, index: index) {
                            toggleFavorite(recipe)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu { contextMenu(for: recipe) }
                }
            }
            .padding(CozySpacing.l)
        }
    }

    @ViewBuilder
    private func contextMenu(for recipe: Recipe) -> some View {
        Button {
            toggleFavorite(recipe)
        } label: {
            Label(
                recipe.isFavorite ? "Remove from favourites" : "Add to favourites",
                systemImage: recipe.isFavorite ? "heart.slash" : "heart"
            )
        }

        if !collections.isEmpty {
            Menu {
                ForEach(collections) { collection in
                    Button {
                        toggle(recipe, in: collection)
                    } label: {
                        Label(
                            collection.name,
                            systemImage: recipe.collections.contains(where: { $0.id == collection.id })
                                ? "checkmark"
                                : "plus"
                        )
                    }
                }
            } label: {
                Label("Collections", systemImage: "square.stack")
            }
        }

        Button(role: .destructive) {
            pendingDeletion = recipe
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func clearFilters() {
        viewModel.searchText = ""
        viewModel.selectedCollectionID = nil
    }

    private func toggleFavorite(_ recipe: Recipe) {
        recipe.isFavorite.toggle()
        recipe.touch()
        save("favourite")
    }

    private func toggle(_ recipe: Recipe, in collection: RecipeCollection) {
        if let index = recipe.collections.firstIndex(where: { $0.id == collection.id }) {
            recipe.collections.remove(at: index)
        } else {
            recipe.collections.append(collection)
        }
        recipe.touch()
        save("collection membership")
    }

    private func createCollection() {
        let name = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        newCollectionName = ""
        guard !name.isEmpty else { return }

        modelContext.insert(RecipeCollection(name: name))
        save("new collection")
    }

    private func delete(_ recipe: Recipe) {
        modelContext.delete(recipe)
        save("delete")
    }

    private func save(_ what: String) {
        do {
            try modelContext.save()
        } catch {
            Log.data.error("Could not save \(what, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
