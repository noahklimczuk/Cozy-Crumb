//
//  RecipeCard.swift
//  Cozy Crumb
//
//  One tile in the Library grid: hero image, title, a small pill row, and a
//  heart that bounces when tapped.
//
//  The entrance is staggered by grid index so the grid rises in a wave rather
//  than snapping in — flattened under Reduce Motion.
//

import SwiftUI

struct RecipeCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accentPalette) private var accent

    let recipe: Recipe
    /// Position in the grid, used to stagger the entrance.
    var index: Int = 0
    var onToggleFavorite: () -> Void

    @State private var hasAppeared = false
    @State private var heartPop = false

    /// Grows with the text size, so the picture keeps its share of a card that
    /// got taller to fit larger type instead of being squeezed by it.
    @ScaledMetric(relativeTo: .headline) private var heroHeight = CozyMetrics.cardHeroHeight

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            details
        }
        // Fill the row's height so two cards side by side line up even when one
        // title wraps to two lines and the other doesn't.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CozyColor.card, in: .rect(cornerRadius: CozyRadius.card, style: .continuous))
        .cozyBlockShadow()
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 18)
        .animation(entrance, value: hasAppeared)
        .onAppear { hasAppeared = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Pieces

    private var hero: some View {
        RecipeHeroView(recipe: recipe)
            // Capped so an accessibility text size can't turn the picture into
            // most of the card.
            .frame(height: min(heroHeight, CozyMetrics.cardHeroHeightCap))
            .frame(maxWidth: .infinity)
            // Clip the image before the overlays go on, so the heart and the
            // review pill are never trimmed by the card's rounded corners.
            .clipShape(
                .rect(
                    topLeadingRadius: CozyRadius.card,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: CozyRadius.card,
                    style: .continuous
                )
            )
            .overlay(alignment: .topTrailing) {
                favoriteButton
                    .padding(CozySpacing.xs)
            }
            .overlay(alignment: .bottomLeading) {
                if recipe.needsReview {
                    // Bottom-left, opposite the heart, and tracked-out capitals
                    // rather than a sentence with an icon: it is a stamp on the
                    // picture, not a label on the recipe.
                    Text("Check me")
                        .cozyEyebrow(color: CozyColor.inkOnBlush,
                                     tracking: CozyTracking.eyebrowTight)
                        .padding(.horizontal, CozySpacing.s)
                        .padding(.vertical, 4)
                        .background(accent.color,
                                    in: .rect(cornerRadius: CozyRadius.pill, style: .continuous))
                        .padding(CozySpacing.s)
                }
            }
    }

    private var favoriteButton: some View {
        Button {
            onToggleFavorite()
            heartPop = true
        } label: {
            // Butter when it's on, translucent white when it isn't. A filled
            // heart in blush on a blush-ish photo was doing the same job as
            // the picture behind it; butter is the one colour on a recipe card
            // that means nothing else.
            Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                .font(.footnote.weight(.bold))
                .foregroundStyle(recipe.isFavorite ? CozyColor.inkOnBlush : CozyColor.inkPrimary)
                .frame(width: 26, height: 26)
                .background(recipe.isFavorite ? CozyColor.butter : CozyColor.cardOnBlush,
                            in: .circle)
                .scaleEffect(heartPop ? 1.25 : 1)
                .animation(reduceMotion ? Motion.reduced : Motion.bouncy, value: heartPop)
                // Keep a full-size hit area behind the small drawn circle.
                .frame(width: CozyMetrics.minimumTouchTarget,
                       height: CozyMetrics.minimumTouchTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(recipe.isFavorite ? "Remove from favourites" : "Add to favourites")
        .accessibilityAddTraits(recipe.isFavorite ? [.isSelected] : [])
        .onChange(of: heartPop) { _, popped in
            guard popped else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(180))
                heartPop = false
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: CozySpacing.s) {
            // The display face, not SF Rounded semibold. A card's title is the
            // thing the grid is read for, and in the old weight it was losing
            // to the picture above it and competing with the pills below.
            Text(recipe.title)
                .cozyText(CozyFont.cardTitle)
                .cozyDisplayTracking(CozyTracking.cardTitle, relativeTo: .headline)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            // Two pills fit side by side on a half-width card at normal type,
            // and stack rather than being clipped once the text grows.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: CozySpacing.xs) { pills }
                VStack(alignment: .leading, spacing: CozySpacing.xs) { pills }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CozySpacing.m)
    }

    /// Bare numbers, no icons and no "Serves". On a half-width card the icons
    /// took as much room as the values and said the same thing twice; the
    /// accessibility label below still spells both out in full, which is where
    /// "serves 8" actually needed to be all along.
    @ViewBuilder
    private var pills: some View {
        if let time = recipe.totalTimeDisplay {
            PillTag(text: time)
        }
        PillTag(text: "\(recipe.servings)")
    }

    // MARK: - Detail

    private var entrance: Animation {
        guard !reduceMotion else { return Motion.reduced }
        return Motion.bouncy.delay(Double(index) * 0.05)
    }

    private var accessibilityLabel: String {
        var parts = [recipe.title]
        if let time = recipe.totalTimeDisplay { parts.append(time) }
        parts.append("serves \(recipe.servings)")
        if recipe.isFavorite { parts.append("favourite") }
        return parts.joined(separator: ", ")
    }
}

#Preview("Recipe cards") {
    let samples = SeedData.allSamples
    return ScrollView {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: CozySpacing.m),
                      GridItem(.flexible(), spacing: CozySpacing.m)],
            spacing: CozySpacing.m
        ) {
            ForEach(Array(samples.enumerated()), id: \.element.id) { index, recipe in
                RecipeCard(recipe: recipe, index: index) {}
            }
        }
        .padding(CozySpacing.l)
    }
    .cozyScreenBackground()
}
