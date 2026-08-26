//
//  RecipeHeroView.swift
//  Cozy Crumb
//
//  A recipe's hero image, or — until one is imported — a procedural pastel
//  stand-in derived from the title, so a hand-typed recipe never looks broken.
//

import SwiftUI
import UIKit

struct RecipeHeroView: View {
    let recipe: Recipe
    var cornerRadius: CGFloat = 0
    /// Longest edge to decode to. Cards want a card-sized photo; the recipe
    /// screen draws it full width and asks for more.
    var maxPixelSize: CGFloat = HeroImageLoader.cardPixelSize

    /// Seeded from the cache so an image already decoded appears immediately
    /// rather than flashing the placeholder on every scroll.
    @State private var decoded: UIImage?

    var body: some View {

        // The image is drawn as an overlay on a zero-weight shape rather than
        // being laid out itself: `scaledToFill` reports the *filled* size, so a
        // portrait photo in a landscape box used to hand its oversize back to
        // the parent and bleed past the corners it was meant to be clipped by.
        // Laying out the box first means the clip always matches the frame it
        // was given, at any card width.
        Color.clear
            .overlay {
                // Never decodes here. `UIImage(data:)` in this position
                // decoded the photo at full size while SwiftUI was evaluating
                // the body around it, which is what stopped the app launching:
                // a grid of full-size decodes on the main thread before the
                // first frame. The placeholder stands in until the real one
                // arrives from `task` below.
                if let decoded {
                    Image(uiImage: decoded)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
            .task(id: recipe.id) { await load() }
    }

    private func load() async {
        // A cache hit is free and synchronous, so a photo that has already
        // been decoded never flashes its placeholder again.
        if let hit = HeroImageLoader.cached(for: recipe.id, maxPixelSize: maxPixelSize) {
            decoded = hit
            return
        }

        guard let data = recipe.heroImageData else { return }

        let id = recipe.id
        let size = maxPixelSize
        let image = await Task.detached(priority: .userInitiated) {
            HeroImageLoader.decode(data, id: id, maxPixelSize: size)
        }.value

        decoded = image
    }

    private var placeholder: some View {
        ZStack {
            // Both stops opaque: a fade to `tint.opacity(0.55)` used to let
            // whatever was behind the card show through the bottom of every
            // recipe without a photo, which is now a ruled page.
            //
            // It runs to the tint's *deep* rather than to a paled version of
            // it. Fading toward the page made a placeholder look like an image
            // that hadn't finished loading; running toward the saturated end
            // makes it look painted, which is what it is.
            LinearGradient(
                colors: [tint, deepTint],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(CozyColor.inkOnAccent.opacity(0.3))
        }
    }

    private var tint: Color {
        CozyColor.rotatedAccent(for: recipe.title)
    }

    private var deepTint: Color {
        CozyColor.rotatedAccentDeep(for: recipe.title)
    }

    /// Picks a glyph from the recipe's tags, falling back to cutlery.
    private var symbol: String {
        let tags = Set(recipe.tags.map { $0.lowercased() })

        if tags.contains("baking") || tags.contains("dessert") { return "birthday.cake" }
        if tags.contains("pasta") { return "fork.knife" }
        if tags.contains("fish") { return "fish" }
        if tags.contains("vegan") || tags.contains("vegetarian") { return "leaf" }
        if tags.contains("roast") || tags.contains("sunday") { return "flame" }
        if tags.contains("breakfast") { return "cup.and.saucer" }
        return "fork.knife"
    }
}

#Preview("Hero placeholders") {
    let samples = SeedData.allSamples
    return ScrollView {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: CozySpacing.m) {
            ForEach(samples) { recipe in
                RecipeHeroView(recipe: recipe, cornerRadius: CozyRadius.image)
                    .frame(height: 120)
            }
        }
        .padding()
    }
    .background(CozyColor.cream)
}
