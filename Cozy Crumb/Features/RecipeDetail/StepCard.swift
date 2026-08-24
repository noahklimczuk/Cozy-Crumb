//
//  StepCard.swift
//  Cozy Crumb
//
//  A numbered instruction card. Steps that state an explicit time show a
//  duration chip.
//
//  As of Phase 6 that chip is live: tapping it starts a kitchen timer against
//  this step, and the chip becomes the countdown. The timer belongs to
//  `KitchenTimers`, not to this card, so it keeps running when the card
//  scrolls away or the user moves into Cook Mode.
//

import SwiftUI

struct StepCard: View {
    @Environment(\.accentPalette) private var accent

    let step: RecipeStep
    let number: Int
    /// Named on the timer's notification, so an alert that arrives an hour
    /// later says what it was for.
    var recipeTitle: String = ""

    var body: some View {
        CrumbCard(padding: CozySpacing.m, cornerRadius: CozyRadius.button) {
            HStack(alignment: .top, spacing: CozySpacing.m) {
                numberBadge

                VStack(alignment: .leading, spacing: CozySpacing.s) {
                    Text(step.text)
                        .cozyText(CozyFont.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    CookTimerChip(step: step, recipeTitle: recipeTitle, number: number)
                }
            }
        }
        // `.contain` rather than `.combine`: the timer chip is a button now,
        // and combining children would bury it.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(number). \(step.text)")
    }

    /// A rounded square rather than a circle, and set in the display face.
    ///
    /// The number is what you look for when you glance back at the page to
    /// find your place, so it takes the deep accent and the heaviest type in
    /// the app at that size. Squaring it off is what makes it read as a
    /// stamped tile rather than a bullet.
    private var numberBadge: some View {
        Text("\(number)")
            .cozyText(CozyFont.title3, color: CozyColor.inkOnAccent)
            .frame(width: 34, height: 34)
            .background(accent.deep,
                        in: .rect(cornerRadius: CozyRadius.chip, style: .continuous))
            .accessibilityHidden(true)
    }
}

#Preview("Step cards") {
    let recipe = SeedData.bananaBread()

    return ScrollView {
        VStack(spacing: CozySpacing.m) {
            ForEach(Array(recipe.orderedSteps.enumerated()), id: \.element.id) { index, step in
                StepCard(step: step, number: index + 1, recipeTitle: recipe.title)
            }
        }
        .padding()
    }
    .cozyScreenBackground()
    .environment(KitchenTimers(usesNotifications: false))
}
