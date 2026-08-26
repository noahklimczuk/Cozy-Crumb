//
//  LibraryView.swift
//  Cozy Crumb
//
//  The home tab: one grid of recipes, narrowed by a search field and a row of
//  collection chips.
//
//  Collections used to be a grid of folder cards above the recipes, which cost
//  a push and a back tap to answer "show me just the baking" and pushed the
//  actual cookbook below the fold on a phone. They are filters now. The folder
//  screen is still here — it is where a collection is renamed, deleted, or has
//  a recipe taken out of it — reached by long-pressing a chip, or from the
//  sort menu for anyone who never thinks to try that.
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.cozyMotion) private var motion

    // Ordered by the database rather than in Swift. An unordered fetch meant
    // every render sorted the whole cookbook again, and each comparison faults
    // `createdAt` on a SwiftData object — so the default view of the app paid
    // for a full traversal of every recipe it owns, repeatedly, on the main
    // thread. Sorting here costs nothing extra: SQLite is already reading the
    // rows.
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
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
    /// Set by the "Open" item on a chip's long-press menu, and by the sort
    /// menu's list. The folder screen is no longer reached by tapping a card,
    /// so the push has to be driven from state rather than a NavigationLink.
    @State private var openedCollection: RecipeCollection?

    private var columns: [GridItem] {
        CozyGrid.recipeColumns(for: horizontalSizeClass)
    }

    /// The lit chip, resolved against what actually exists. A collection
    /// deleted while its chip was selected simply stops matching, and the grid
    /// falls back to every recipe rather than filtering on a ghost.
    private var selectedCollection: RecipeCollection? {
        guard let id = viewModel.selectedCollectionID else { return nil }
        return collections.first { $0.id == id }
    }

    private var visibleRecipes: [Recipe] {
        viewModel.visibleRecipes(from: recipes, in: selectedCollection?.id)
    }

    var body: some View {
        // The @Query properties above are read during this evaluation, which
        // is the suspected stall.
        let _ = markBodyOnce("cookbook body")

        NavigationStack {
            VStack(spacing: 0) {
                header
                content
            }
            .cozyScreenBackground()
            // The header is the title now. Leaving the navigation bar on as
            // well would put "Cookbook" on the screen twice.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $openedCollection) { collection in
                CollectionFolderView(collection: collection, sort: viewModel.sort)
            }
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

    /// The search field and the add button were already living in a
    /// hand-rolled bar under the navigation title, because a toolbar clips
    /// anything taller than it is and the add button is meant to be
    /// unmissable. `ScreenHeader` is that bar, with the title in it.
    private var header: some View {
        // "Cook / book", broken by hand rather than left to wrap: at 52pt it
        // would break there anyway on a phone, and hard-coding it means the
        // two lines are the design on every width instead of only the narrow
        // ones. `heroTitle` hands VoiceOver the unbroken word.
        ScreenHeader(title: "Cook\nbook", eyebrow: AppBranding.appName) {
            HeaderMascotBadge(pose: .peeking)
        } below: {
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

                HeaderActionButton(
                    systemImage: "plus",
                    accessibilityLabel: "Add a recipe",
                    accessibilityHint: "Opens the paste-a-link screen"
                ) {
                    isImporting = true
                    pasteLinkText = ""
                }
            }
        }
        .heroTitle(spokenAs: "Cookbook")
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

            // The discoverable half of collection management. Long-pressing a
            // chip is faster and is what someone who knows the app will use,
            // but a gesture with nothing on screen to advertise it cannot be
            // the only way in — and once the folder cards are gone, opening a
            // collection is the only route to renaming or deleting one.
            Section("Collections") {
                Button {
                    isNamingCollection = true
                } label: {
                    Label("New collection", systemImage: "folder.badge.plus")
                }

                ForEach(collections) { collection in
                    Button {
                        openedCollection = collection
                    } label: {
                        Label(collection.name, systemImage: "folder")
                    }
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
                CozyColor.card,
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

    /// The empty cookbook comes first, before the chip row is drawn: a row of
    /// filters over nothing is furniture in an empty room.
    ///
    /// Everything else is one branch now. Searching and browsing differed only
    /// in which recipes the grid held once the folder cards went, and keeping
    /// them apart meant two copies of a heading, a sort control and a grid.
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
        } else {
            cookbook
        }
    }

    private var cookbook: some View {
        // Bound once. `visibleRecipes` was read two or three times per pass —
        // by the emptiness check, by the grid, and by the heading while
        // searching — and each read filtered and sorted the entire cookbook
        // from scratch. SwiftUI evaluates a body more than once during launch,
        // so the first screen was doing that work several times over before it
        // drew anything.
        let visible = visibleRecipes

        return ScrollView {
            VStack(alignment: .leading, spacing: CozySpacing.l) {
                collectionChips

                VStack(alignment: .leading, spacing: CozySpacing.m) {
                    HStack(spacing: CozySpacing.s) {
                        Text(headingTitle(visibleCount: visible.count))
                            .cozyText(CozyFont.title2)
                            .cozyDisplayTracking(CozyTracking.title2, relativeTo: .title2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer()
                        sortControl
                    }

                    if visible.isEmpty {
                        emptyResults
                    } else {
                        recipeGrid(recipes: visible)
                    }
                }
            }
            .padding(CozySpacing.l)
        }
    }

    /// What the grid is showing, said once above it. With the folder grid gone
    /// this heading is the only thing that names the filter in force — the lit
    /// chip is above it and scrolls away.
    private func headingTitle(visibleCount: Int) -> String {
        if viewModel.hasSearch {
            return "\(visibleCount) \(visibleCount == 1 ? "match" : "matches")"
        }
        return selectedCollection?.name ?? "All recipes"
    }

    @ViewBuilder
    private var emptyResults: some View {
        // Two different dead ends, and the way out of each is different: a
        // search that found nothing wants the query cleared, an empty
        // collection wants the filter dropped. Offering "clear search" to
        // someone who never typed anything is the sort of thing that makes an
        // empty screen feel broken.
        if viewModel.hasSearch {
            EmptyStateView(
                title: "Nothing matches.",
                message: selectedCollection.map {
                    "Nothing in \($0.name) matches that. Try another word, or look in the whole cookbook."
                } ?? "Try a different word, or clear your search and start again.",
                pose: .idle,
                actionTitle: "Clear search",
                action: clearSearch
            )
            .frame(maxWidth: .infinity)
        } else if let selectedCollection {
            EmptyStateView(
                title: "Nothing filed here yet.",
                message: "Add recipes to \(selectedCollection.name) from a recipe's menu and they'll show up here.",
                pose: .idle,
                actionTitle: "Show all recipes",
                action: { select(nil) }
            )
            .frame(maxWidth: .infinity)
        } else {
            Text("No recipes yet.")
                .cozyText(CozyFont.body, color: CozyColor.inkSecondary)
                .padding(.vertical, CozySpacing.s)
        }
    }

    /// Collections, as a row of filters rather than a grid of folders.
    ///
    /// Each chip carries the long-press menu that used to hang off its card,
    /// which is the only fast route to renaming or deleting a collection now.
    /// It is a hidden gesture, so the sort menu carries the same list in the
    /// open — see the note there.
    private var collectionChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: CozySpacing.s) {
                SelectableChip(
                    text: "All \(recipes.count)",
                    isSelected: selectedCollection == nil
                ) {
                    select(nil)
                }

                ForEach(collections) { collection in
                    // Deliberately the accent rather than `collection.tint`:
                    // the chips are a set of five or six sitting in a row, and
                    // if each lights up a different colour then "selected"
                    // stops being a thing the row says and becomes something
                    // you work out per chip.
                    SelectableChip(
                        text: collection.name,
                        isSelected: selectedCollection?.id == collection.id
                    ) {
                        select(selectedCollection?.id == collection.id ? nil : collection.id)
                    }
                    .contextMenu { collectionMenu(for: collection) }
                }

                SelectableChip(text: "New collection", systemImage: "plus", isSelected: false) {
                    isNamingCollection = true
                }
            }
            // Room for the chips' hit areas without clipping them against the
            // scroll view's edges.
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        // The row is chrome for the grid below it, so it scrolls sideways
        // inside a page that scrolls down, and never the other way.
        .scrollClipDisabled()
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
            openedCollection = collection
        } label: {
            Label("Open", systemImage: "folder")
        }

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

    /// Clears the query and nothing else. The chip stays lit: someone who
    /// searched inside a collection was still inside that collection, and
    /// silently returning them to the whole cookbook is a filter changing
    /// itself behind their back.
    private func clearSearch() {
        viewModel.searchText = ""
    }

    private func select(_ collectionID: UUID?) {
        guard collectionID != viewModel.selectedCollectionID else { return }
        // Through the resolver, not `Motion.snappy` directly — the grid
        // re-flowing under a filter is exactly the kind of movement Reduce
        // Motion is asking to be spared.
        withAnimation(motion(Motion.snappy)) { viewModel.selectedCollectionID = collectionID }
        Haptics.soft()
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
        // Drop the filter with it, so the grid doesn't sit empty behind a chip
        // that has just stopped existing.
        if viewModel.selectedCollectionID == collection.id {
            viewModel.selectedCollectionID = nil
        }
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

/// The screen behind a collection chip's "Open".
///
/// It survived the move from folders to filters because the chips took over
/// only the *browsing* half of what the folder cards did. Renaming a
/// collection, deleting one, and taking a recipe back out of one all still
/// live here, and there is nowhere else in the app they could go.
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
        // Same as the Cookbook: read once, not once per branch.
        let sorted = sortedRecipes

        return Group {
            if sorted.isEmpty {
                EmptyStateView(
                    title: "This folder is empty.",
                    message: "Add recipes from the Cookbook menu and they'll appear here.",
                    pose: .idle
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: CozySpacing.m) {
                        ForEach(Array(sorted.enumerated()), id: \.element.id) { index, recipe in
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
        .cozyScreenBackground()
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
