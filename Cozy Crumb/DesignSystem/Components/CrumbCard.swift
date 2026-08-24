//
//  CrumbCard.swift
//  Cozy Crumb
//
//  The base surface everything sits on: continuous corners and a hard block
//  offset in a warm tone. The block is what sells the enamel look — it reads
//  as a printed edge rather than a shadow, so the card looks stamped onto the
//  page instead of hovering over it.
//
//  The 1.5pt outline the first pass drew is gone, because a block and a stroke
//  together give the card two edges and it stops looking drawn. It comes back
//  automatically when the block does not: `hasBlock: false` swaps the offset
//  for a hairline, which is what a card nested inside another card wants — an
//  offset there would land on a surface the same colour and vanish.
//

import SwiftUI

struct CrumbCard<Content: View>: View {
    var padding: CGFloat = CozySpacing.l
    var fill: Color = CozyColor.card
    var cornerRadius: CGFloat = CozyRadius.card
    /// Set false for a card sitting on another card, or on a tinted tray of
    /// the same weight. See the note at the top of the file.
    var hasBlock: Bool = true

    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(fill, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .modifier(CrumbEdge(cornerRadius: cornerRadius, hasBlock: hasBlock))
    }
}

/// Card variant with no padding, for content that bleeds to the edge such as
/// a recipe hero image.
struct CrumbCardBleed<Content: View>: View {
    var cornerRadius: CGFloat = CozyRadius.card
    var hasBlock: Bool = true

    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .modifier(CrumbEdge(cornerRadius: cornerRadius, hasBlock: hasBlock))
    }
}

// MARK: - Edge

/// One place decides what a card's edge is, so the two card shapes can't drift
/// apart and neither can end up wearing both a block and a stroke.
private struct CrumbEdge: ViewModifier {
    let cornerRadius: CGFloat
    let hasBlock: Bool

    func body(content: Content) -> some View {
        if hasBlock {
            content.cozyBlockShadow()
        } else {
            content.overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(CozyColor.outline, lineWidth: 1)
            }
        }
    }
}

#Preview("Cards") {
    VStack(spacing: CozySpacing.xl) {
        CrumbCard {
            VStack(alignment: .leading, spacing: CozySpacing.s) {
                Text("Brown Butter Banana Bread")
                    .cozyText(CozyFont.title2)
                Text("A loaf that makes the whole flat smell like a bakery.")
                    .cozyText(CozyFont.subheadline, color: CozyColor.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        CrumbCardBleed {
            Rectangle()
                .fill(CozyColor.peach)
                .frame(height: 120)
                .overlay {
                    Text("Bleed card")
                        .cozyText(CozyFont.headline)
                }
        }

        // The nesting case: an inner card on a tinted tray, with the block
        // swapped for a hairline so it doesn't disappear into its own tray.
        CrumbCard(fill: CozyColor.creamDeep) {
            VStack(alignment: .leading, spacing: CozySpacing.s) {
                Text("Tuesday")
                    .cozyText(CozyFont.headline)
                CrumbCard(padding: CozySpacing.m, hasBlock: false) {
                    Text("Nested — hairline, no block.")
                        .cozyText(CozyFont.subheadline, color: CozyColor.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CozyColor.cream)
}
