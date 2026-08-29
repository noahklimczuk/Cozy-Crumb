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
    @Environment(\.dynamicTypeSize) private var typeSize

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
        // Width only. `maxHeight: .infinity` here asked the cell to fill its
        // row's height — but in a LazyVGrid the row's height is decided by the
        // cells in it, so the cell was asking the row for a number the row was
        // waiting on the cell to supply. With `ViewThatFits` measuring inside
        // that same unresolved negotiation, the layout had no fixed point to
        // settle on and body evaluation never returned.
        //
        // The two cards in a row no longer match heights exactly when one
        // title wraps and its neighbour doesn't. The reserved two lines on
        // the title keep them close at ordinary sizes — see `title`, which
        // gives that up past AX1 — and a few points of difference is a far
        // better trade than a launch that hangs.
        .frame(maxWidth: .infinity, alignment: .top)
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

    private var favoriteButton: some View {
        Button {
            onToggleFavorite()
            heartPop = true
        } label: {
            // Butter when it's on, translucent white when it isn't. A filled
            // heart in blush on a blush-ish photo was doing the same job as
            // the picture behind it; butter is the one colour on a recipe card
            // that means nothing else.
            //
            // `inkOnAccent` in both states, not just the favourited one. Both
            // fills are light surfaces that stay light after dark, and the
            // unfavourited heart was drawn in `inkPrimary` — which goes light
            // with the page. On a dark phone that was a pale outline on a white
            // disc: the heart was there, and invisible.
            // A fixed point size, not `.footnote`, because the disc under it
            // is a fixed 26pt. A text style scales with Dynamic Type and the
            // frame does not, so at AX5 the heart grew to roughly three times
            // its badge and sat on the photo as a bare black glyph with the
            // disc lost somewhere behind it. Every other glyph-in-a-badge in
            // the app is already sized this way — the tab bar, the header
            // buttons, the send button.
            Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CozyColor.inkOnAccent)
                .frame(width: 26, height: 26)
                .background(recipe.isFavorite ? CozyColor.butter : CozyColor.surfaceOnAccent,
                            in: .circle)
                // A hairline, because the disc has to read on a hero of any
                // colour and the heroes are the same palette it is drawn from.
                // A butter badge on the butter-tinted placeholder was one shape
                // in one colour.
                .overlay {
                    Circle().strokeBorder(CozyColor.inkOnAccent.opacity(0.14), lineWidth: 1)
                }
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

    /// The recipe's name, capped at two lines — until it can't be.
    ///
    /// Two lines with the space reserved is what keeps the two cards in a row
    /// roughly level when one title wraps and its neighbour doesn't. At an
    /// accessibility size two lines is no longer enough to hold a recipe
    /// name: the AX5 capture read "Sunda / y Ro…" for a recipe called Sunday
    /// Roast Chicken, on a card whose picture is a coloured placeholder. Two
    /// cards you cannot tell apart is a worse grid than two cards of unequal
    /// height, so past AX1 the title takes the lines it needs.
    ///
    /// Nothing here reserves or fills height — the cell's own height is still
    /// decided by its contents, which is what keeps this clear of the layout
    /// hang described on `body`.
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
            // The display face, not SF Rounded semibold. A card's title is the
            // thing the grid is read for, and in the old weight it was losing
            // to the picture above it and competing with the pills below.
            title

            // A plain row, not `ViewThatFits`. Fitting two short pills is not
            // worth a construct that measures every candidate against a
            // proposed size — inside a lazy grid cell whose own height was
            // still being negotiated, that measurement is half of why this
            // card could not finish laying out.
            //
            // They are "35 min" and "4". At an accessibility text size the row
            // wraps to two lines rather than being clipped, which is what the
            // stacking candidate was there to achieve anyway.
            HStack(spacing: CozySpacing.xs) {
                pills
            }
            .fixedSize(horizontal: false, vertical: true)
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
        // Capped. The stagger is 0.05s per grid position, which is a pleasant
        // ripple across the first screenful and a bug beyond it: the 200th
        // card in a real cookbook was waiting ten seconds to become visible,
        // and the 500th nearly half a minute. The wave is over long before
        // anyone scrolls that far, so past `staggerCap` they simply appear.
        return Motion.bouncy.delay(min(Double(index) * 0.05, Self.staggerCap))
    }

    /// Longest entrance delay any card will wait, however far down it sits.
    private static let staggerCap: Double = 0.6

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
