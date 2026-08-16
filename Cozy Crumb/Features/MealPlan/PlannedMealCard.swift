//
//  PlannedMealCard.swift
//  Cozy Crumb
//
//  A recipe on the week's plan, drawn the way the Cookbook draws recipes:
//  picture first, then the title and the details worth knowing at a glance.
//
//  It deliberately isn't `RecipeCard`. The Library's card carries a favourite
//  heart, which has no meaning while you're planning, and it shows the recipe's
//  own servings — the planner needs the servings *this meal* was planned for,
//  which is often different. The chrome is shared by eye rather than by
//  inheritance: same corners, same outline, same shadow.
//

import SwiftUI

struct PlannedMealCard: View {
    let recipe: Recipe

    /// Shown as a badge over the picture. Nil in the recipe picker, where every
    /// card would say the same thing.
    var slot: MealSlot?
    /// Servings this meal was planned for, which overrides the recipe's own.
    var servings: Int?

    /// Grows with the text size, so the picture keeps its share of a card that
    /// got taller to fit larger type.
    @ScaledMetric(relativeTo: .headline) private var heroHeight: CGFloat = 112

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            details
        }
        // Fill the row so two cards side by side line up, however their titles
        // wrap.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CozyColor.card, in: .rect(cornerRadius: CozyRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CozyRadius.card, style: .continuous)
                .strokeBorder(CozyColor.outline, lineWidth: CozyBorder.card)
        }
        .cozyCardShadow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Pieces

    private var hero: some View {
        RecipeHeroView(recipe: recipe)
            // Capped so an accessibility text size can't turn the picture into
            // most of the card.
            .frame(height: min(heroHeight, 170))
            .frame(maxWidth: .infinity)
            // Clipped before the badge goes on, so the badge is never trimmed
            // by the card's rounded corners.
            .clipShape(
                .rect(
                    topLeadingRadius: CozyRadius.card,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: CozyRadius.card,
                    style: .continuous
                )
            )
            .overlay(alignment: .topLeading) {
                if let slot {
                    PillTag(text: slot.displayName, systemImage: slot.symbol)
                        .padding(CozySpacing.s)
                }
            }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: CozySpacing.s) {
            Text(recipe.title)
                .cozyText(CozyFont.headline)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            // Two pills fit side by side at normal type, and stack rather than
            // clipping once the text grows.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: CozySpacing.xs) { pills }
                VStack(alignment: .leading, spacing: CozySpacing.xs) { pills }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CozySpacing.m)
    }

    @ViewBuilder
    private var pills: some View {
        if let time = recipe.totalTimeDisplay {
            PillTag(text: time, systemImage: "clock")
        }
        PillTag(text: "\(plannedServings)", systemImage: "person.2", tint: CozyColor.creamDeep)
    }

    // MARK: - Detail

    private var plannedServings: Int {
        max(1, servings ?? recipe.servings)
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if let slot { parts.append(slot.displayName) }
        parts.append(recipe.title)
        if let time = recipe.totalTimeDisplay { parts.append(time) }
        parts.append("serves \(plannedServings)")
        return parts.joined(separator: ", ")
    }
}

#Preview("Planned meal cards") {
    let samples = SeedData.allSamples

    return ScrollView {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: CozySpacing.m),
                      GridItem(.flexible(), spacing: CozySpacing.m)],
            spacing: CozySpacing.m
        ) {
            ForEach(Array(samples.enumerated()), id: \.element.id) { index, recipe in
                PlannedMealCard(
                    recipe: recipe,
                    slot: MealSlot.allCases[index % MealSlot.allCases.count],
                    servings: 2
                )
            }
        }
        .padding(CozySpacing.l)
    }
    .background { BlobBackground() }
}
