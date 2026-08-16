//
//  CookModeView.swift
//  Cozy Crumb
//
//  Phase 6. One step at a time, big enough to read from the other side of the
//  kitchen with your hands covered in flour.
//
//  What the screen is for decides what's on it. Cooking is not browsing:
//
//    - The step text is the screen. Everything else is a small control at an
//      edge, out of the way of the one sentence being followed.
//    - The screen never sleeps while it's open, and the phone can be put down
//      mid-step without losing your place.
//    - Timers start from the step that mentions them, keep running as you move
//      through the method, and stay running if you leave — the rice does not
//      care which screen you're looking at.
//    - The ingredients are one tap away rather than a screen away, at whatever
//      servings the detail screen was dialled to.
//    - Finishing lands on "I made this", because that is what happens next.
//

import SwiftData
import SwiftUI
import UIKit

struct CookModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cozyMotion) private var motion
    @Environment(KitchenTimers.self) private var timers

    let recipe: Recipe
    /// Servings and units as they were set on the detail screen, so the
    /// quantities here match the ones just read.
    var servings: Int
    var system: MeasurementSystem
    /// Called after the last step, once this screen has closed.
    var onFinish: () -> Void

    @State private var index = 0
    @State private var isShowingIngredients = false
    @State private var checkedIngredientIDs: Set<UUID> = []

    private var steps: [RecipeStep] { recipe.orderedSteps }

    var body: some View {
        ZStack {
            CozyColor.cream.ignoresSafeArea()
            BlobBackground().ignoresSafeArea()

            if steps.isEmpty {
                noMethod
            } else {
                cooking
            }
        }
        .sheet(isPresented: $isShowingIngredients) { ingredientsSheet }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: - Nothing to follow

    private var noMethod: some View {
        VStack(spacing: CozySpacing.l) {
            EmptyStateView(
                title: "There's no method saved.",
                message: "Add the steps to this recipe and I'll walk you through them.",
                pose: .idle
            )

            SquishyButton(title: "Back to the recipe", emphasis: .secondary) {
                dismiss()
            }
            .padding(.horizontal, CozySpacing.l)
        }
    }

    // MARK: - Cooking

    private var cooking: some View {
        VStack(spacing: 0) {
            topBar

            TabView(selection: $index) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { position, step in
                    CookStepPage(
                        step: step,
                        number: position + 1,
                        recipeTitle: recipe.title
                    )
                    .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            bottomBar
        }
        .safeAreaInset(edge: .bottom) {
            CookTimerBar()
                .padding(.horizontal, CozySpacing.l)
        }
    }

    private var topBar: some View {
        VStack(spacing: CozySpacing.s) {
            HStack(spacing: CozySpacing.m) {
                SquishyIconButton(systemImage: "xmark", accessibilityLabel: "Leave cook mode") {
                    dismiss()
                }

                VStack(spacing: 2) {
                    Text("Step \(min(index + 1, steps.count)) of \(steps.count)")
                        .cozyText(CozyFont.headline)
                    Text(recipe.title)
                        .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)

                SquishyIconButton(systemImage: "list.bullet", accessibilityLabel: "Show the ingredients") {
                    isShowingIngredients = true
                }
            }

            ProgressView(value: Double(index + 1), total: Double(max(steps.count, 1)))
                .tint(CozyColor.blushDeep)
        }
        .padding(.horizontal, CozySpacing.l)
        .padding(.bottom, CozySpacing.m)
        .background(.ultraThinMaterial)
    }

    private var bottomBar: some View {
        HStack(spacing: CozySpacing.m) {
            SquishyIconButton(systemImage: "chevron.left", accessibilityLabel: "Previous step") {
                goBack()
            }
            .disabled(index == 0)
            .opacity(index == 0 ? 0.4 : 1)

            if isOnLastStep {
                SquishyButton(title: "I made this", systemImage: "checkmark.seal") {
                    finish()
                }
            } else {
                SquishyButton(title: "Next step", systemImage: "chevron.right") {
                    goForward()
                }
            }
        }
        .padding(.horizontal, CozySpacing.l)
        .padding(.top, CozySpacing.m)
    }

    private var isOnLastStep: Bool {
        index >= steps.count - 1
    }

    // MARK: - Ingredients

    private var ingredientsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CozySpacing.s) {
                    ForEach(recipe.orderedIngredients) { ingredient in
                        IngredientRow(
                            ingredient: ingredient,
                            originalServings: max(1, recipe.servings),
                            targetServings: servings,
                            system: system,
                            isChecked: checkedIngredientIDs.contains(ingredient.id)
                        ) {
                            toggle(ingredient)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(CozySpacing.l)
            }
            .background { BlobBackground() }
            .navigationTitle("Ingredients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isShowingIngredients = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func toggle(_ ingredient: Ingredient) {
        if checkedIngredientIDs.contains(ingredient.id) {
            checkedIngredientIDs.remove(ingredient.id)
        } else {
            checkedIngredientIDs.insert(ingredient.id)
        }
        Haptics.selection()
    }

    // MARK: - Moving through the method

    private func goForward() {
        guard index < steps.count - 1 else { return }
        withAnimation(motion(Motion.snappy)) { index += 1 }
        Haptics.soft()
    }

    private func goBack() {
        guard index > 0 else { return }
        withAnimation(motion(Motion.snappy)) { index -= 1 }
        Haptics.soft()
    }

    /// Leaves any running timers alone on the way out: something is often
    /// still in the oven when the last step is read.
    ///
    /// `onFinish` runs *before* the dismissal so the caller can raise the cook
    /// log once this screen has actually gone — presenting a sheet from a
    /// screen that is mid-dismiss gets swallowed.
    private func finish() {
        Haptics.notify(.success)
        onFinish()
        dismiss()
    }
}

// MARK: - One step

private struct CookStepPage: View {
    let step: RecipeStep
    let number: Int
    let recipeTitle: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CozySpacing.l) {
                Text("Step \(number)")
                    .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                    .accessibilityHidden(true)

                Text(step.text)
                    .cozyText(CozyFont.cookStep)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                CookTimerChip(step: step, recipeTitle: recipeTitle, number: number)

                Spacer(minLength: CozySpacing.xxl)
            }
            .padding(.horizontal, CozySpacing.l)
            .padding(.top, CozySpacing.xl)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(number). \(step.text)")
    }
}

// MARK: - Previews

#Preview("Cook mode") {
    CookModeView(
        recipe: SeedData.bananaBread(),
        servings: 8,
        system: .asWritten,
        onFinish: {}
    )
    .environment(KitchenTimers(usesNotifications: false))
}

#Preview("Cook mode — no method") {
    CookModeView(
        recipe: Recipe(title: "A recipe with no steps"),
        servings: 4,
        system: .asWritten,
        onFinish: {}
    )
    .environment(KitchenTimers(usesNotifications: false))
}
