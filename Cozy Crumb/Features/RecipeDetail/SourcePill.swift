//
//  SourcePill.swift
//  Cozy Crumb
//
//  The "where this came from" chip. When the recipe has a source URL, tapping
//  it opens the original — the blog post, the TikTok, the video.
//
//  Recipes typed in by hand have no URL, so the same chip renders as a plain,
//  non-tappable label rather than pretending to be a link.
//

import SwiftUI

struct SourcePill: View {
    @Environment(\.openURL) private var openURL

    let name: String
    let symbol: String
    let url: URL?

    var body: some View {
        if let url {
            Button {
                openURL(url)
            } label: {
                chip(isLink: true)
            }
            .buttonStyle(.squishy)
            .accessibilityLabel("Open the original on \(name)")
            .accessibilityHint("Opens in your browser")
            .accessibilityAddTraits(.isLink)
        } else {
            chip(isLink: false)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("From \(name)")
        }
    }

    private func chip(isLink: Bool) -> some View {
        HStack(spacing: CozySpacing.xs) {
            Image(systemName: symbol)
                .font(.caption2.weight(.semibold))

            Text(name)
                .font(CozyFont.caption)
                .lineLimit(1)

            if isLink {
                // A small, honest affordance: this one goes somewhere.
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(CozyColor.inkSecondary)
            }
        }
        .foregroundStyle(CozyColor.inkPrimary)
        .padding(.horizontal, CozySpacing.m)
        .padding(.vertical, CozySpacing.s)
        .background(
            isLink ? CozyColor.blushSoft : CozyColor.creamDeep,
            in: .rect(cornerRadius: CozyRadius.chip, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CozyRadius.chip, style: .continuous)
                .strokeBorder(CozyColor.outline, lineWidth: 1)
        }
        // Draws compact, stays comfortably tappable (§7.6).
        .frame(minHeight: CozyMetrics.minimumTouchTarget)
        .contentShape(.rect)
    }
}

extension SourcePill {
    /// Builds the chip for a recipe, falling back to the host when no source
    /// name was captured — "example.com" beats showing nothing.
    nonisolated static func label(for recipe: Recipe) -> String? {
        if let name = recipe.sourceName, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        return recipe.sourceURL?.host()
    }
}

#Preview("Source pills") {
    VStack(alignment: .leading, spacing: CozySpacing.m) {
        SourcePill(
            name: "@pastagrannies",
            symbol: "play.rectangle",
            url: URL(string: "https://www.tiktok.com/@pastagrannies")
        )
        SourcePill(
            name: "Bon Appétit",
            symbol: "globe",
            url: URL(string: "https://example.com/recipe")
        )
        SourcePill(name: "Mom's index card", symbol: "pencil", url: nil)
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(CozyColor.cream)
}
