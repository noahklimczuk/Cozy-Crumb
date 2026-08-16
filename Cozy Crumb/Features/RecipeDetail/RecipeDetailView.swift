//
//  RecipeDetailView.swift
//  Cozy Crumb
//
//  One recipe, cooked from. Servings scale every quantity live, units convert
//  where it makes sense, and "I made this" writes a CookLog.
//

import Foundation
import SwiftData
import SwiftUI
import os

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.cozyMotion) private var motion

    @AppStorage(CozyDefaultsKey.measurementSystem)
    private var systemRaw = MeasurementSystem.asWritten.rawValue

    let recipe: Recipe

    @State private var viewModel: RecipeDetailViewModel
    @State private var isEditing = false
    @State private var groceryToast: String?
    @State private var isPresentingAddReview = false

    private static let scrollSpace = "recipeScroll"
    private static let heroHeight: CGFloat = 260

    init(recipe: Recipe) {
        self.recipe = recipe
        _viewModel = State(initialValue: RecipeDetailViewModel(recipe: recipe))
    }

    private var system: MeasurementSystem {
        MeasurementSystem(rawValue: systemRaw) ?? .asWritten
    }

    var body: some View {
        ScrollView {
            VStack(spacing: CozySpacing.l) {
                hero
                heading
                servingsCard
                ingredientsCard
                addToGroceriesButton
                stepsSection
                notesCard
                madeThisSection
                if !recipe.cookLogs.isEmpty {
                    historySection
                }
            }
            .padding(.bottom, CozySpacing.xxl)
        }
        .coordinateSpace(.named(Self.scrollSpace))
        .background { BlobBackground() }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            favoriteButton
            editButton
        }
        .sheet(isPresented: $isEditing) {
            viewModel.resync(with: recipe)
        } content: {
            ImportFlowView(editingRecipe: recipe)
        }
        .sheet(isPresented: $viewModel.isLoggingCook) {
            CookLogSheet(recipeTitle: recipe.title) { rating, notes in
                logCook(rating: rating, notes: notes)
            }
        }
        .sheet(isPresented: $isPresentingAddReview) {
            let lines = GroceryService.lineItems(from: recipe, servings: viewModel.servings)
            GroceryAddReviewView(lines: lines, sourceTitle: recipe.title)
        }
        .overlay(alignment: .bottom) { groceryToastBanner }
    }

    // MARK: - Groceries

    /// Sends the ingredient list — at whatever servings the user has dialled
    /// to, not the recipe's original — over to the grocery list.
    private var addToGroceriesButton: some View {
        SquishyButton(title: "Add to groceries", systemImage: "checklist", emphasis: .secondary) {
            addToGroceries()
        }
        .padding(.horizontal, CozySpacing.l)
    }

    @ViewBuilder
    private var groceryToastBanner: some View {
        if let groceryToast {
            Text(groceryToast)
                .cozyText(CozyFont.caption, color: CozyColor.inkPrimary)
                .padding(.horizontal, CozySpacing.m)
                .padding(.vertical, CozySpacing.s)
                .background(CozyColor.creamDeep, in: .capsule)
                .cozyLiftShadow()
                .padding(.bottom, CozySpacing.xl)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    private func addToGroceries() {
        let lines = GroceryService.lineItems(from: recipe, servings: viewModel.servings)
        
        // Show review view if there are items to add
        if !lines.isEmpty {
            // Present review sheet with the lines
            isPresentingAddReview = true
        } else {
            // Show toast for no items needed
            Haptics.notify(.success)
            withAnimation(motion(Motion.snappy)) {
                groceryToast = "Nothing on this one needs buying."
            }

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.2))
                withAnimation(motion(Motion.gentle)) { groceryToast = nil }
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .named(Self.scrollSpace)).minY
            // Pulling down stretches the image instead of leaving a gap.
            let stretch = max(0, minY)

            RecipeHeroView(recipe: recipe)
                .frame(width: proxy.size.width, height: Self.heroHeight + stretch)
                .offset(y: -stretch)
        }
        .frame(height: Self.heroHeight)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: CozySpacing.s) {
            Text(recipe.title)
                .cozyText(CozyFont.title)
                .fixedSize(horizontal: false, vertical: true)

            if let summary = recipe.summary {
                Text(summary)
                    .cozyText(CozyFont.subheadline, color: CozyColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: CozySpacing.xs) {
                if let time = recipe.totalTimeDisplay {
                    PillTag(text: time, systemImage: "clock")
                }
                if let sourceLabel = SourcePill.label(for: recipe) {
                    SourcePill(
                        name: sourceLabel,
                        symbol: recipe.sourceKind.symbol,
                        url: recipe.sourceURL
                    )
                }
            }

            if recipe.needsReview {
                Text("I did my best guess here — worth a quick look.")
                    .cozyText(CozyFont.caption, color: CozyColor.inkPrimary)
                    .padding(CozySpacing.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CozyColor.warning.opacity(0.45),
                                in: .rect(cornerRadius: CozyRadius.chip, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CozySpacing.l)
    }

    // MARK: - Servings & units

    private var servingsCard: some View {
        CrumbCard {
            VStack(spacing: CozySpacing.m) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Servings")
                            .cozyText(CozyFont.headline)
                        if let description = viewModel.scaleDescription {
                            Text(description)
                                .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                        } else if viewModel.isScaled {
                            Text("written for \(viewModel.originalServings)")
                                .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                        }
                    }

                    Spacer()

                    stepper
                }

                Divider().overlay(CozyColor.outline)

                VStack(alignment: .leading, spacing: CozySpacing.s) {
                    Text("Units")
                        .cozyText(CozyFont.headline)
                    Picker("Units", selection: $systemRaw) {
                        ForEach(MeasurementSystem.allCases, id: \.rawValue) { option in
                            Text(option.displayName).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, CozySpacing.l)
    }

    private var stepper: some View {
        HStack(spacing: CozySpacing.m) {
            SquishyIconButton(systemImage: "minus", accessibilityLabel: "Fewer servings") {
                viewModel.decreaseServings()
            }

            Text("\(viewModel.servings)")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(CozyColor.inkPrimary)
                .contentTransition(.numericText())
                .frame(minWidth: 36)
                .cozyAnimation(Motion.bouncy, value: viewModel.servings)

            SquishyIconButton(systemImage: "plus", accessibilityLabel: "More servings") {
                viewModel.increaseServings()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(viewModel.servings) servings")
    }

    // MARK: - Ingredients

    private var ingredientsCard: some View {
        CrumbCard {
            VStack(alignment: .leading, spacing: CozySpacing.s) {
                HStack {
                    Text("Ingredients")
                        .cozyText(CozyFont.title2)
                    Spacer()
                    if viewModel.isScaled {
                        Button("Reset", action: viewModel.resetServings)
                            .font(CozyFont.caption)
                            .foregroundStyle(CozyColor.inkSecondary)
                    }
                }

                ForEach(recipe.orderedIngredients) { ingredient in
                    IngredientRow(
                        ingredient: ingredient,
                        originalServings: viewModel.originalServings,
                        targetServings: viewModel.servings,
                        system: system,
                        isChecked: viewModel.isChecked(ingredient)
                    ) {
                        viewModel.toggle(ingredient)
                    }
                }

                Text("Ticks reset when you leave.")
                    .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
                    .padding(.top, CozySpacing.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, CozySpacing.l)
    }

    // MARK: - Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: CozySpacing.m) {
            Text("Method")
                .cozyText(CozyFont.title2)
                .padding(.horizontal, CozySpacing.l)

            ForEach(Array(recipe.orderedSteps.enumerated()), id: \.element.id) { index, step in
                StepCard(step: step, number: index + 1)
                    .padding(.horizontal, CozySpacing.l)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Notes

    private var notesCard: some View {
        CrumbCard {
            VStack(alignment: .leading, spacing: CozySpacing.s) {
                Text("Your notes")
                    .cozyText(CozyFont.title2)

                TextField(
                    "Halved the sugar and it was still plenty sweet…",
                    text: notesBinding,
                    axis: .vertical
                )
                .font(CozyFont.body)
                .foregroundStyle(CozyColor.inkPrimary)
                .lineLimit(3...10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, CozySpacing.l)
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { recipe.personalNotes ?? "" },
            set: { newValue in
                recipe.personalNotes = newValue.isEmpty ? nil : newValue
                recipe.touch()
            }
        )
    }

    // MARK: - Made this

    private var madeThisSection: some View {
        ZStack {
            SquishyButton(title: "I made this", systemImage: "checkmark.seal") {
                viewModel.isLoggingCook = true
            }
            .padding(.horizontal, CozySpacing.l)

            CrumbConfetti(isActive: viewModel.isCelebrating)
        }
    }

    private var historySection: some View {
        CrumbCard(fill: CozyColor.creamDeep) {
            VStack(alignment: .leading, spacing: CozySpacing.s) {
                Text("You've made this \(recipe.cookLogs.count) time\(recipe.cookLogs.count == 1 ? "" : "s")")
                    .cozyText(CozyFont.headline)

                ForEach(recipe.orderedCookLogs) { log in
                    HStack(spacing: CozySpacing.s) {
                        Text(log.date.formatted(date: .abbreviated, time: .omitted))
                            .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)

                        if let rating = log.rating {
                            HStack(spacing: 1) {
                                ForEach(0..<rating, id: \.self) { _ in
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(CozyColor.warning)
                                }
                            }
                        }

                        Spacer()
                    }

                    if let notes = log.notes {
                        Text(notes)
                            .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, CozySpacing.l)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var editButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isEditing = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(CozyColor.inkSecondary)
            }
            .accessibilityLabel("Edit this recipe")
        }
    }

    @ToolbarContentBuilder
    private var favoriteButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                recipe.isFavorite.toggle()
                recipe.touch()
                save("favourite")
            } label: {
                Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(recipe.isFavorite ? CozyColor.blushDeep : CozyColor.inkSecondary)
            }
            .accessibilityLabel(recipe.isFavorite ? "Remove from favourites" : "Add to favourites")
        }
    }

    // MARK: - Actions

    private func logCook(rating: Int?, notes: String?) {
        let log = CookLog(rating: rating, notes: notes)
        modelContext.insert(log)
        log.recipe = recipe

        recipe.lastCookedAt = log.date
        // A fresh rating replaces the old one; skipping it leaves it alone.
        if let rating {
            recipe.rating = rating
        }
        recipe.touch()

        save("cook log")

        viewModel.isCelebrating = true
        Task {
            try? await Task.sleep(for: .milliseconds(1400))
            viewModel.isCelebrating = false
        }
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

#Preview("Recipe detail") {
    NavigationStack {
        RecipeDetailView(recipe: SeedData.bananaBread())
    }
    .modelContainer(PreviewData.container)
}

#Preview("Recipe detail — dark") {
    NavigationStack {
        RecipeDetailView(recipe: SeedData.chickpeaCurry())
    }
    .modelContainer(PreviewData.container)
    .preferredColorScheme(.dark)
}

#Preview("Recipe detail — AX3") {
    NavigationStack {
        RecipeDetailView(recipe: SeedData.misoSalmon())
    }
    .modelContainer(PreviewData.container)
    .environment(\.dynamicTypeSize, .accessibility3)
}
