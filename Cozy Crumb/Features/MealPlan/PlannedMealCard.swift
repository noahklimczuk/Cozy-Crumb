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
//  inheritance: same corners, same block.
//

import SwiftUI

struct PlannedMealCard: View {
    @Environment(\.accentPalette) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize

    let recipe: Recipe

    /// Shown as a badge over the picture. Nil in the recipe picker, where every
    /// card would say the same thing.
    var slot: MealSlot?
    /// Servings this meal was planned for, which overrides the recipe's own.
    var servings: Int?

    /// Grows with the text size, so the picture keeps its share of a card that
    /// got taller to fit larger type. Same number as the Cookbook's card: a
    /// meal on the plan should look like the recipe it came from, not like a
    /// smaller relative of it.
    @ScaledMetric(relativeTo: .headline) private var heroHeight = CozyMetrics.cardHeroHeight

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            details
        }
        // Fill the row so two cards side by side line up, however their titles
        // wrap.
        // Width only — same reasoning as RecipeCard: a cell cannot ask its
        // grid row for a height the row is computing from that cell.
        .frame(maxWidth: .infinity, alignment: .top)
        .background(CozyColor.card, in: .rect(cornerRadius: CozyRadius.card, style: .continuous))
        .cozyBlockShadow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Pieces

    private var hero: some View {
        RecipeHeroView(recipe: recipe)
            // Capped so an accessibility text size can't turn the picture into
            // most of the card.
            .frame(height: min(heroHeight, CozyMetrics.cardHeroHeightCap))
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
                    PillTag(text: slot.displayName,
                            systemImage: slot.symbol,
                            tint: CozyColor.surfaceOnAccent,
                            ink: CozyColor.inkOnAccent)
                        .padding(CozySpacing.s)
                }
            }
            .overlay(alignment: .bottomLeading) {
                // Same warning the Cookbook shows. Finding out a recipe was
                // never checked over is worth more on the night you planned to
                // cook it than it is while browsing.
                if recipe.needsReview {
                    Text("Check me")
                        .cozyEyebrow(color: CozyColor.inkOnAccent,
                                     tracking: CozyTracking.eyebrowTight)
                        .padding(.horizontal, CozySpacing.s)
                        .padding(.vertical, 4)
                        .background(accent.color,
                                    in: .rect(cornerRadius: CozyRadius.pill, style: .continuous))
                        .padding(CozySpacing.s)
                }
            }
    }

    /// The recipe's name, capped at two lines until an accessibility size,
    /// where two lines cannot hold one. Same rule as `RecipeCard`, for the
    /// same reason and deliberately in step with it — see the note there.
    @ViewBuilder
    private var title: some View {
        let text = Text(recipe.title)
            .cozyText(CozyFont.cardTitle)
            .cozyDisplayTracking(CozyTracking.cardTitle, relativeTo: .headline)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)

        if typeSize.isAccessibilitySize {
            text
        } else {
            text.lineLimit(2, reservesSpace: true)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: CozySpacing.s) {
            // Matches the Cookbook's card exactly — same face, same size, same
            // tracking. These two cards sit in grids one tab apart and any
            // drift between them is visible immediately.
            title

            // A plain row, same as RecipeCard. Two short pills do not justify
            // measuring candidates inside a grid cell that is still working
            // out its own height.
            HStack(spacing: CozySpacing.xs) {
                pills
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CozySpacing.m)
    }

    @ViewBuilder
    private var pills: some View {
        if let time = recipe.totalTimeDisplay {
            PillTag(text: time)
        }
        PillTag(text: "\(plannedServings)")
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
    .cozyScreenBackground()
}
