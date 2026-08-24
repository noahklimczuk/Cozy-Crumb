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
    @Environment(\.accentPalette) private var accent
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
            // The whole screen is a painted ground here, not a cream page with
            // things on it. Cook Mode is the one screen you are not reading in
            // a room with the app — it is propped against a bag of flour — and
            // it should be unmistakable at a glance which of the two you are
            // looking at.
            AccentTileBackground()

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
                        total: steps.count,
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
        VStack(spacing: CozySpacing.l) {
            HStack(spacing: CozySpacing.m) {
                cookControl(systemImage: "xmark", label: "Leave cook mode") {
                    dismiss()
                }

                // Just the recipe's name, tracked out small. "Step 3 of 6" used
                // to be here as well, and it is now the line above the step
                // itself, where you are already looking.
                Text(recipe.title)
                    .cozyEyebrow(color: CozyColor.inkOnAccent)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)

                cookControl(systemImage: "list.bullet", label: "Show the ingredients") {
                    isShowingIngredients = true
                }
            }

            stepProgress
        }
        .padding(.horizontal, CozySpacing.l)
        .padding(.bottom, CozySpacing.m)
    }

    /// A control on the painted ground: translucent white, squared off, and
    /// big — this screen is operated with a knuckle and the side of a thumb.
    private func cookControl(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CozyColor.inkOnAccent)
                .frame(width: CozyMetrics.minimumTouchTarget,
                       height: CozyMetrics.minimumTouchTarget)
                .background(CozyColor.surfaceOnAccent,
                            in: .rect(cornerRadius: CozyRadius.field, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.squishy)
        .accessibilityLabel(label)
    }

    /// One segment per step rather than a continuous bar.
    ///
    /// A method has a countable number of steps and you are on one of them —
    /// a sliding bar answers "roughly how far through am I", which is a
    /// question about a download. Segments answer "how many left", which is
    /// the one a cook is actually asking.
    ///
    /// Above about a dozen steps the segments would be thinner than the gaps
    /// between them, so past that it goes back to a bar.
    @ViewBuilder
    private var stepProgress: some View {
        let done = min(index + 1, steps.count)

        if steps.count <= 12 {
            HStack(spacing: 6) {
                ForEach(0..<steps.count, id: \.self) { position in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(position < done ? accent.deep : CozyColor.surfaceOnAccent)
                        .frame(height: 8)
                }
            }
            .cozyAnimation(Motion.snappy, value: index)
            .accessibilityElement()
            .accessibilityLabel("Step \(done) of \(steps.count)")
        } else {
            ProgressView(value: Double(done), total: Double(steps.count))
                .tint(accent.deep)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: CozySpacing.m) {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(CozyColor.inkOnAccent)
                    .frame(width: 60, height: 60)
                    .background(CozyColor.surfaceOnAccent,
                                in: .rect(cornerRadius: CozyRadius.sheet, style: .continuous))
                    .contentShape(.rect)
            }
            .buttonStyle(.squishy)
            .accessibilityLabel("Previous step")
            .disabled(index == 0)
            .opacity(index == 0 ? 0.4 : 1)

            // Both are the same 60pt bar. The label changes at the end of the
            // method, the shape does not — the last step is not a different
            // kind of press.
            if isOnLastStep {
                SquishyButton(title: "I made this", systemImage: "checkmark.seal", minHeight: 60) {
                    finish()
                }
            } else {
                SquishyButton(title: "Next step", systemImage: "chevron.right", minHeight: 60) {
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
            .cozyScreenBackground()
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
    let total: Int
    let recipeTitle: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CozySpacing.l) {
                Text(Self.stepLabel(number: number, of: total))
                    .font(CozyFont.eyebrowDisplay)
                    .cozyDisplayTracking(CozyTracking.eyebrowStep, relativeTo: .subheadline)
                    .textCase(.uppercase)
                    .foregroundStyle(CozyColor.inkOnAccent)
                    .accessibilityHidden(true)

                Text(step.text)
                    .cozyText(CozyFont.cookStep, color: CozyColor.inkOnAccent)
                    .cozyDisplayTracking(CozyTracking.cookStep, relativeTo: .title)
                    .cozyDisplayLeading(CozyLeading.cookStep)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                CookTimerChip(step: step, recipeTitle: recipeTitle, number: number,
                              isProminent: true)

                Spacer(minLength: CozySpacing.xxl)
            }
            .padding(.horizontal, CozySpacing.l)
            .padding(.top, CozySpacing.l)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(number). \(step.text)")
    }

    /// "STEP ONE OF SIX" rather than "STEP 1 OF 6".
    ///
    /// Words, because this line is read at a glance from a distance and a
    /// spelled-out number holds its shape at 15pt where a lone digit doesn't.
    /// It goes back to digits past twenty, where the words get longer than the
    /// line they are set on, and it is hidden from VoiceOver either way — the
    /// step's own accessibility label already says which one this is.
    private static func stepLabel(number: Int, of total: Int) -> String {
        guard total <= 20 else { return "Step \(number) of \(total)" }

        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        guard let position = formatter.string(from: NSNumber(value: number)),
              let count = formatter.string(from: NSNumber(value: total)) else {
            return "Step \(number) of \(total)"
        }
        return "Step \(position) of \(count)"
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
