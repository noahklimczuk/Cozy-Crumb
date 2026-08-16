//
//  MealPlanView.swift
//  Cozy Crumb
//
//  A week at a glance: what you're cooking, which day, and a single button to
//  turn the whole week into a shopping list.
//
//  The week follows the user's own calendar, so the first column is whatever
//  day their locale starts on.
//
//  Planned meals are shown as recipe cards rather than list rows, here and in
//  the picker. A plan is something you look at to decide whether you fancy it,
//  and a line of text can't do that — the picture is the point.
//

import Foundation
import SwiftData
import SwiftUI

struct MealPlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accentPalette) private var accent
    @Environment(\.cozyMotion) private var motion

    @Query private var plannedMeals: [PlannedMeal]

    /// Any date inside the week being shown.
    @State private var anchor = Date.now
    @State private var addingTo: DaySlot?
    @State private var isConfirmingClearWeek = false
    @State private var toast: String?
    @State private var isPresentingAddReview = false

    private var days: [Date] { MealPlanService.days(ofWeekContaining: anchor) }

    /// Two cards to a row: a day rarely holds more than three meals, and any
    /// wider and the pictures stop being worth showing.
    private let mealColumns = [
        GridItem(.flexible(), spacing: CozySpacing.m),
        GridItem(.flexible(), spacing: CozySpacing.m)
    ]

    private var weekMeals: [PlannedMeal] {
        MealPlanService.meals(inWeekContaining: anchor, from: plannedMeals)
    }

    var body: some View {
        ScrollView {
            week
        }
        .background { BlobBackground() }
        .safeAreaInset(edge: .bottom) { shopBar }
        .sheet(item: $addingTo) { target in
            RecipePickerSheet(day: target.day, slot: target.slot) { recipe, slot, servings in
                withAnimation(motion(Motion.bouncy)) {
                    _ = MealPlanService.add(
                        recipe,
                        on: target.day,
                        slot: slot,
                        servings: servings,
                        in: modelContext
                    )
                }
            }
        }
        .sheet(isPresented: $isPresentingAddReview) {
            let lines = MealPlanService.groceryLines(for: weekMeals)
            GroceryAddReviewView(lines: lines, sourceTitle: "This week's meals")
        }
        .confirmationDialog(
            "Clear this week's plan?",
            isPresented: $isConfirmingClearWeek,
            titleVisibility: .visible
        ) {
            Button("Clear it", role: .destructive) {
                withAnimation(motion(Motion.gentle)) {
                    MealPlanService.clear(weekMeals, in: modelContext)
                }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Your recipes stay in the cookbook — only the plan goes.")
        }
        .overlay(alignment: .bottom) { toastBanner }
    }

    // MARK: - Week

    private var week: some View {
        VStack(spacing: CozySpacing.m) {
            weekBar

            ForEach(days, id: \.self) { day in
                dayCard(day)
            }

            if !weekMeals.isEmpty {
                clearWeekButton
            }
        }
        .padding(.horizontal, CozySpacing.l)
        .padding(.bottom, CozySpacing.xxl)
    }

    private var clearWeekButton: some View {
        Button {
            isConfirmingClearWeek = true
        } label: {
            Text("Clear this week")
                .font(CozyFont.caption)
                .foregroundStyle(CozyColor.inkSecondary)
                .frame(minHeight: CozyMetrics.minimumTouchTarget)
        }
    }

    private var weekBar: some View {
        HStack(spacing: CozySpacing.s) {
            SquishyIconButton(systemImage: "chevron.left", accessibilityLabel: "Previous week") {
                withAnimation(motion(Motion.snappy)) {
                    anchor = MealPlanService.week(offsetBy: -1, from: anchor)
                }
            }

            VStack(spacing: 0) {
                Text(MealPlanService.weekLabel(for: anchor))
                    .cozyText(CozyFont.headline)
                if !MealPlanService.isCurrentWeek(anchor) {
                    Button("Back to this week") {
                        withAnimation(motion(Motion.snappy)) { anchor = .now }
                    }
                    .font(CozyFont.caption2)
                    .foregroundStyle(CozyColor.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity)

            SquishyIconButton(systemImage: "chevron.right", accessibilityLabel: "Next week") {
                withAnimation(motion(Motion.snappy)) {
                    anchor = MealPlanService.week(offsetBy: 1, from: anchor)
                }
            }
        }
        .padding(.top, CozySpacing.s)
    }

    // MARK: - Days

    private func dayCard(_ day: Date) -> some View {
        let meals = MealPlanService.meals(on: day, from: plannedMeals)
        let isToday = Calendar.current.isDateInToday(day)

        // The day is a tinted tray now rather than a white card, so the recipe
        // cards sitting in it have something to stand against.
        return CrumbCard(fill: isToday ? accent.soft : CozyColor.creamDeep) {
            VStack(alignment: .leading, spacing: CozySpacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text(day.formatted(.dateTime.weekday(.wide)))
                        .cozyText(CozyFont.bodyEmphasis)
                    Text(day.formatted(.dateTime.day().month(.abbreviated)))
                        .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)

                    Spacer()

                    Button {
                        addingTo = DaySlot(day: day, slot: suggestedSlot(for: meals))
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CozyColor.inkPrimary)
                            .frame(width: 30, height: 30)
                            .background(accent.color, in: .circle)
                            .overlay { Circle().strokeBorder(accent.deep, lineWidth: 1.5) }
                    }
                    .buttonStyle(.squishy)
                    .accessibilityLabel("Plan something for \(day.formatted(.dateTime.weekday(.wide)))")
                }

                if meals.isEmpty {
                    Text("Nothing planned.")
                        .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                } else {
                    LazyVGrid(columns: mealColumns, spacing: CozySpacing.m) {
                        ForEach(meals) { meal in
                            mealCard(meal)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Fills the day out in meal order rather than stacking three dinners.
    private func suggestedSlot(for meals: [PlannedMeal]) -> MealSlot {
        let taken = Set(meals.map(\.slot))
        return MealSlot.allCases.first { !taken.contains($0) } ?? .dinner
    }

    @ViewBuilder
    private func mealCard(_ meal: PlannedMeal) -> some View {
        if let recipe = meal.recipe {
            NavigationLink {
                RecipeDetailView(recipe: recipe)
            } label: {
                PlannedMealCard(recipe: recipe, slot: meal.slot, servings: meal.servings)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Menu("Move to") {
                    ForEach(days, id: \.self) { day in
                        Button(day.formatted(.dateTime.weekday(.wide))) {
                            withAnimation(motion(Motion.gentle)) {
                                MealPlanService.move(meal, to: day, slot: meal.slot, in: modelContext)
                            }
                        }
                    }
                }

                Menu("Change meal") {
                    ForEach(MealSlot.allCases) { slot in
                        Button(slot.displayName) {
                            withAnimation(motion(Motion.gentle)) {
                                MealPlanService.move(meal, to: meal.date, slot: slot, in: modelContext)
                            }
                        }
                    }
                }

                Button(role: .destructive) {
                    withAnimation(motion(Motion.gentle)) {
                        MealPlanService.remove(meal, in: modelContext)
                    }
                } label: {
                    Label("Take off the plan", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Shop bar

    @ViewBuilder
    private var shopBar: some View {
        if !weekMeals.isEmpty {
            SquishyButton(title: "Add the week to my list", systemImage: "checklist") {
                addWeekToList()
            }
            .padding(.horizontal, CozySpacing.l)
            .padding(.vertical, CozySpacing.m)
            .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var toastBanner: some View {
        if let toast {
            Text(toast)
                .cozyText(CozyFont.caption, color: CozyColor.inkPrimary)
                .padding(.horizontal, CozySpacing.m)
                .padding(.vertical, CozySpacing.s)
                .background(CozyColor.creamDeep, in: .capsule)
                .cozyLiftShadow()
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    // MARK: - Actions

    /// Every meal in the week, costed at its planned servings, merged into one
    /// shop. Adding twice merges rather than duplicating, so a mid-week change
    /// of plan doesn't mean starting the list again.
    private func addWeekToList() {
        let lines = MealPlanService.groceryLines(for: weekMeals)
        guard !lines.isEmpty else {
            show(toast: "Nothing on this week's recipes to buy.")
            return
        }

        // Present review sheet with the lines
        isPresentingAddReview = true
    }

    private func show(toast message: String) {
        withAnimation(motion(Motion.snappy)) { toast = message }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(motion(Motion.gentle)) { toast = nil }
        }
    }
}

// MARK: - Sheet target

/// Which day and meal the picker is filling. A struct rather than two pieces
/// of state so `.sheet(item:)` can't open half-configured.
private struct DaySlot: Identifiable {
    let id = UUID()
    let day: Date
    let slot: MealSlot
}

// MARK: - Recipe picker

private struct RecipePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Recipe.title) private var recipes: [Recipe]

    let day: Date
    let slot: MealSlot
    let onPick: (Recipe, MealSlot, Int) -> Void

    @State private var search = ""
    @State private var chosenSlot: MealSlot

    private let columns = [
        GridItem(.flexible(), spacing: CozySpacing.m),
        GridItem(.flexible(), spacing: CozySpacing.m)
    ]

    init(day: Date, slot: MealSlot, onPick: @escaping (Recipe, MealSlot, Int) -> Void) {
        self.day = day
        self.slot = slot
        self.onPick = onPick
        _chosenSlot = State(initialValue: slot)
    }

    private var matches: [Recipe] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return recipes }

        return recipes.filter { recipe in
            recipe.title.lowercased().contains(query)
                || recipe.tags.contains { $0.lowercased().contains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if recipes.isEmpty {
                    EmptyStateView(
                        title: "No recipes yet",
                        message: "Save something to your cookbook and it'll show up here.",
                        pose: .sleeping
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: CozySpacing.l) {
                            Picker("Meal", selection: $chosenSlot) {
                                ForEach(MealSlot.allCases) { slot in
                                    Text(slot.displayName).tag(slot)
                                }
                            }
                            .pickerStyle(.segmented)

                            if matches.isEmpty {
                                Text("Nothing matches “\(search)”.")
                                    .cozyText(CozyFont.subheadline, color: CozyColor.inkSecondary)
                                    .padding(.top, CozySpacing.xl)
                            } else {
                                LazyVGrid(columns: columns, spacing: CozySpacing.m) {
                                    ForEach(matches) { recipe in
                                        Button {
                                            onPick(recipe, chosenSlot, max(1, recipe.servings))
                                            dismiss()
                                        } label: {
                                            PlannedMealCard(recipe: recipe)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityHint("Adds it to \(chosenSlot.displayName.lowercased())")
                                    }
                                }
                            }
                        }
                        .padding(CozySpacing.l)
                    }
                    .searchable(text: $search, prompt: "Find a recipe")
                }
            }
            .background { BlobBackground() }
            .navigationTitle(day.formatted(.dateTime.weekday(.wide)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Week") {
    NavigationStack { MealPlanView() }
        .modelContainer(PreviewData.plannerContainer)
}

#Preview("Week — empty") {
    NavigationStack { MealPlanView() }
        .modelContainer(PreviewData.emptyContainer)
}
