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

    var body: some View {
        // The image is drawn as an overlay on a zero-weight shape rather than
        // being laid out itself: `scaledToFill` reports the *filled* size, so a
        // portrait photo in a landscape box used to hand its oversize back to
        // the parent and bleed past the corners it was meant to be clipped by.
        // Laying out the box first means the clip always matches the frame it
        // was given, at any card width.
        Color.clear
            .overlay {
                if let data = recipe.heroImageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [tint, tint.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(CozyColor.inkPrimary.opacity(0.35))
        }
    }

    private var tint: Color {
        CozyColor.rotatedAccent(for: recipe.title)
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
