//
//  LibraryView.swift
//  Cozy Crumb
//
//  The home tab: searchable recipes and editable collection folders.
//

import Foundation
import SwiftData
import SwiftUI
import os

/// A pasted link, wrapped so `.sheet(item:)` can present it — the URL itself
/// isn't `Identifiable`, and two pastes of the same link should each open.
private struct QuickPastedLink: Identifiable {
    let id = UUID()
    let url: URL
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accentPalette) private var accent
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Query private var recipes: [Recipe]
    @Query(sort: \RecipeCollection.createdAt) private var collections: [RecipeCollection]

    @State private var viewModel = LibraryViewModel()
    @State private var pendingDeletion: Recipe?
    @State private var pendingCollectionDeletion: RecipeCollection?
    @State private var isNamingCollection = false
    @State private var newCollectionName = ""
    @State private var collectionBeingRenamed: RecipeCollection?
    @State private var renamedCollectionName = ""
    @State private var isImporting = false
    @State private var clipboardHadNoLink = false
    @State private var pasteLinkText = ""

    private var columns: [GridItem] {
        CozyGrid.recipeColumns(for: horizontalSizeClass)
    }

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
            .navigationTitle("Cookbook")
            .sheet(isPresented: $isImporting) {
                importSheet
            }
            .alert("No link on the clipboard", isPresented: $clipboardHadNoLink) {
                Button("Try again") { }
                Button("Never mind", role: .cancel) {}
            } message: {
                Text("Copy a recipe link first, then tap Add to paste it.")
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
            .confirmationDialog(
                "Delete this collection?",
                isPresented: .init(
                    get: { pendingCollectionDeletion != nil },
                    set: { if !$0 { pendingCollectionDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete collection", role: .destructive) {
                    if let pendingCollectionDeletion { delete(pendingCollectionDeletion) }
                    pendingCollectionDeletion = nil
                }
                Button("Keep it", role: .cancel) { pendingCollectionDeletion = nil }
            } message: {
                Text("The recipes will stay in your cookbook.")
            }
            .alert("New collection", isPresented: $isNamingCollection) {
                TextField("Weeknight, Baking, Mom's…", text: $newCollectionName)
                Button("Create", action: createCollection)
                Button("Cancel", role: .cancel) { newCollectionName = "" }
            }
            .alert("Rename collection", isPresented: .init(
                get: { collectionBeingRenamed != nil },
                set: { if !$0 { collectionBeingRenamed = nil } }
            )) {
                TextField("Collection name", text: $renamedCollectionName)
                Button("Save", action: renameCollection)
                Button("Cancel", role: .cancel) { collectionBeingRenamed = nil }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: CozySpacing.m) {
            CozyTextField(
                placeholder: "Search recipes and ingredients",
                text: $viewModel.searchText,
                systemImage: "magnifyingglass",
                submitLabel: .search,
                // Only submitted searches are logged. Recording every
                // keystroke would fill the log with the prefixes of one word.
                onSubmit: { SignalLog.searched(viewModel.searchText, in: modelContext) }
            )

            addButton
        }
        .padding(.horizontal, CozySpacing.l)
        .padding(.vertical, CozySpacing.m)
        .background(.ultraThinMaterial)
    }

    /// The main call to action: one big button to paste a link.
    ///
    /// It sits beside the search field rather than in the toolbar because a
    /// navigation bar clips anything taller than it is, and this button is
    /// meant to be unmissable.
    private var addButton: some View {
        Button {
            isImporting = true
            pasteLinkText = ""
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(CozyColor.inkPrimary)
                .frame(width: CozyMetrics.addButtonDiameter,
                       height: CozyMetrics.addButtonDiameter)
                .background(accent.color, in: .circle)
                .overlay {
                    Circle().strokeBorder(accent.deep, lineWidth: 2)
                }
                .cozyLiftShadow()
        }
        .buttonStyle(.squishy)
        .accessibilityLabel("Add a recipe")
        .accessibilityHint("Opens the paste-a-link screen")
    }

    /// Sheet for importing a recipe with inline paste button
    @ViewBuilder
    private var importSheet: some View {
        ImportFlowView(pasteLinkText: $pasteLinkText)
    }

    /// Sort lives beside a heading rather than in the toolbar, so the toolbar
    /// belongs to adding recipes.
    ///
    /// Plain buttons rather than a `Picker`: a picker inside a menu is rendered
    /// as a nested submenu, so the options sat a tap further in than the icon
    /// suggested and the control read as doing nothing at all. The label now
    /// names the sort in force, so a change is visible even before the grid
    /// re-orders.
    private var sortControl: some View {
        Menu {
            ForEach(LibrarySort.allCases) { option in
                Button {
                    guard option != viewModel.sort else { return }
                    viewModel.sort = option
                    Haptics.soft()
                } label: {
                    Label(
                        option.displayName,
                        systemImage: option == viewModel.sort ? "checkmark" : option.symbol
                    )
                }
            }
        } label: {
            HStack(spacing: CozySpacing.xs) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.footnote.weight(.semibold))
                Text(viewModel.sort.displayName)
                    .lineLimit(1)
            }
            .font(CozyFont.subheadline)
            .foregroundStyle(CozyColor.inkSecondary)
            .padding(.horizontal, CozySpacing.m)
            .frame(minHeight: CozyMetrics.minimumTouchTarget)
            .background(
                CozyColor.card.opacity(0.9),
                in: .rect(cornerRadius: CozyRadius.chip, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CozyRadius.chip, style: .continuous)
                    .strokeBorder(CozyColor.outline, lineWidth: CozyBorder.card)
            }
            .contentShape(.rect)
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Sort recipes")
        .accessibilityValue(viewModel.sort.displayName)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if recipes.isEmpty && collections.isEmpty {
            EmptyStateView(
                title: "Your cookbook's a blank page.",
                message: "Paste a link to get started — I'll do the tidying up.",
                pose: .sleeping,
                actionTitle: "Paste a link",
                action: { isImporting = true }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.hasSearch && visibleRecipes.isEmpty {
            EmptyStateView(
                title: "Nothing matches.",
                message: "Try a different word, or clear your search and start again.",
                pose: .idle,
                actionTitle: "Clear search",
                action: clearFilters
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.hasSearch {
            grid
        } else {
            cookbookHome
        }
    }

    private var cookbookHome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CozySpacing.xl) {
                collectionFolders

                VStack(alignment: .leading, spacing: CozySpacing.m) {
                    HStack(spacing: CozySpacing.s) {
                        Text("All recipes")
                            .cozyText(CozyFont.title2)
                        Spacer()
                        sortControl
                    }

                    if visibleRecipes.isEmpty {
                        Text("No recipes yet.")
                            .cozyText(CozyFont.body, color: CozyColor.inkSecondary)
                            .padding(.vertical, CozySpacing.s)
                    } else {
                        recipeGrid(recipes: visibleRecipes)
                    }
                }
            }
            .padding(CozySpacing.l)
        }
    }

    private var collectionFolders: some View {
        VStack(alignment: .leading, spacing: CozySpacing.m) {
            Text("Collections")
                .cozyText(CozyFont.title2)

            LazyVGrid(columns: columns, spacing: CozySpacing.m) {
                ForEach(collections) { collection in
                    NavigationLink {
                        CollectionFolderView(collection: collection, sort: viewModel.sort)
                    } label: {
                        CollectionFolderCard(collection: collection)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { collectionMenu(for: collection) }
                }

                Button { isNamingCollection = true } label: {
                    NewCollectionFolderCard()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create a new collection")
            }
        }
    }

    /// Search results.
    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CozySpacing.m) {
                HStack(spacing: CozySpacing.s) {
                    Text("\(visibleRecipes.count) \(visibleRecipes.count == 1 ? "match" : "matches")")
                        .cozyText(CozyFont.title2)
                    Spacer()
                    sortControl
                }

                recipeGrid(recipes: visibleRecipes)
            }
            .padding(CozySpacing.l)
        }
    }

    private func recipeGrid(recipes: [Recipe]) -> some View {
        LazyVGrid(columns: columns, spacing: CozySpacing.m) {
            ForEach(Array(recipes.enumerated()), id: \.element.id) { index, recipe in
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
    }

    @ViewBuilder
    private func collectionMenu(for collection: RecipeCollection) -> some View {
        Button {
            collectionBeingRenamed = collection
            renamedCollectionName = collection.name
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button(role: .destructive) {
            pendingCollectionDeletion = collection
        } label: {
            Label("Delete", systemImage: "trash")
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
    }

    private func toggleFavorite(_ recipe: Recipe) {
        recipe.isFavorite.toggle()
        recipe.touch()
        save("favourite")
        SignalLog.favorited(recipe, isNowFavorite: recipe.isFavorite, in: modelContext)
    }

    private func toggle(_ recipe: Recipe, in collection: RecipeCollection) {
        let wasIn = recipe.collections.contains { $0.id == collection.id }

        if let index = recipe.collections.firstIndex(where: { $0.id == collection.id }) {
            recipe.collections.remove(at: index)
        } else {
            recipe.collections.append(collection)
        }
        recipe.touch()
        save("collection membership")

        // Filing something away is deliberate curation. Taking it out again
        // is tidying, and is not read as a rejection.
        if !wasIn {
            SignalLog.addedToCollection(recipe, in: modelContext)
        }
    }

    private func createCollection() {
        let name = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        newCollectionName = ""
        guard !name.isEmpty else { return }

        modelContext.insert(RecipeCollection(name: name))
        save("new collection")
    }

    private func renameCollection() {
        let name = renamedCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let collectionBeingRenamed, !name.isEmpty else { return }

        collectionBeingRenamed.name = name
        self.collectionBeingRenamed = nil
        save("collection rename")
    }

    private func delete(_ collection: RecipeCollection) {
        modelContext.delete(collection)
        save("delete collection")
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

// MARK: - Collection folders

private struct CollectionFolderCard: View {
    let collection: RecipeCollection

    var body: some View {
        CrumbCard(fill: collection.tint.opacity(0.55)) {
            VStack(alignment: .leading, spacing: CozySpacing.s) {
                HStack {
                    Image(systemName: "folder.fill")
                        .font(.title2)
                        .foregroundStyle(CozyColor.inkPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CozyColor.inkSecondary)
                }

                Spacer(minLength: CozySpacing.s)

                Text(collection.name)
                    .cozyText(CozyFont.headline)
                    .lineLimit(2)
                Text("\(collection.recipeCount) \(collection.recipeCount == 1 ? "recipe" : "recipes")")
                    .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        }
        .accessibilityLabel("\(collection.name), \(collection.recipeCount) recipes")
    }
}

private struct NewCollectionFolderCard: View {
    var body: some View {
        CrumbCard(fill: CozyColor.creamDeep) {
            VStack(spacing: CozySpacing.s) {
                Image(systemName: "folder.badge.plus")
                    .font(.title2)
                    .foregroundStyle(CozyColor.inkPrimary)
                Text("New collection")
                    .cozyText(CozyFont.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        }
    }
}

private struct CollectionFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Bindable var collection: RecipeCollection
    let sort: LibrarySort

    @State private var isRenaming = false
    @State private var name = ""
    @State private var isConfirmingDeletion = false

    private var columns: [GridItem] {
        CozyGrid.recipeColumns(for: horizontalSizeClass)
    }

    private var sortedRecipes: [Recipe] {
        switch sort {
        case .recentlyAdded:
            collection.recipes.sorted { $0.createdAt > $1.createdAt }
        case .recentlyCooked:
            collection.recipes.sorted { ($0.lastCookedAt ?? .distantPast) > ($1.lastCookedAt ?? .distantPast) }
        case .alphabetical:
            collection.recipes.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .rating:
            collection.recipes.sorted { ($0.rating ?? 0, $0.createdAt) > ($1.rating ?? 0, $1.createdAt) }
        case .quickest:
            collection.recipes.sorted { ($0.totalMinutes ?? .max) < ($1.totalMinutes ?? .max) }
        }
    }

    var body: some View {
        Group {
            if sortedRecipes.isEmpty {
                EmptyStateView(
                    title: "This folder is empty.",
                    message: "Add recipes from the Cookbook menu and they'll appear here.",
                    pose: .idle
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: CozySpacing.m) {
                        ForEach(Array(sortedRecipes.enumerated()), id: \.element.id) { index, recipe in
                            NavigationLink {
                                RecipeDetailView(recipe: recipe)
                            } label: {
                                RecipeCard(recipe: recipe, index: index) { toggleFavorite(recipe) }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    remove(recipe)
                                } label: {
                                    Label("Remove from collection", systemImage: "folder.badge.minus")
                                }
                            }
                        }
                    }
                    .padding(CozySpacing.l)
                }
            }
        }
        .background { BlobBackground() }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button {
                    name = collection.name
                    isRenaming = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    isConfirmingDeletion = true
                } label: {
                    Label("Delete collection", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .alert("Rename collection", isPresented: $isRenaming) {
            TextField("Collection name", text: $name)
            Button("Save", action: rename)
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this collection?", isPresented: $isConfirmingDeletion) {
            Button("Delete collection", role: .destructive, action: deleteCollection)
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The recipes will stay in your cookbook.")
        }
    }

    private func toggleFavorite(_ recipe: Recipe) {
        recipe.isFavorite.toggle()
        recipe.touch()
        save("favourite")
        SignalLog.favorited(recipe, isNowFavorite: recipe.isFavorite, in: modelContext)
    }

    private func remove(_ recipe: Recipe) {
        recipe.collections.removeAll { $0.id == collection.id }
        recipe.touch()
        save("collection membership")
    }

    private func rename() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        collection.name = trimmed
        save("collection rename")
    }

    private func deleteCollection() {
        for recipe in collection.recipes {
            recipe.collections.removeAll { $0.id == collection.id }
        }
        modelContext.delete(collection)
        save("delete collection")
        dismiss()
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
        .environment(KitchenTimers(usesNotifications: false))
}

#Preview("Library — dark") {
    LibraryView()
        .modelContainer(PreviewData.container)
        .environment(KitchenTimers(usesNotifications: false))
        .preferredColorScheme(.dark)
}

#Preview("Library — empty") {
    LibraryView()
        .modelContainer(PreviewData.emptyContainer)
        .environment(KitchenTimers(usesNotifications: false))
}
