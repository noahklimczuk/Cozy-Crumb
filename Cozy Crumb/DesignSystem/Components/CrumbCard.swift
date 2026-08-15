//
//  CrumbCard.swift
//  Cozy Crumb
//
//  The base surface everything sits on: continuous 24pt corners, a 1.5pt warm
//  outline, and a soft warm-tinted shadow. The outline is what sells the
//  illustrated look — don't drop it.
//

import SwiftUI

struct CrumbCard<Content: View>: View {
    var padding: CGFloat = CozySpacing.l
    var fill: Color = CozyColor.card
    var cornerRadius: CGFloat = CozyRadius.card

    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(fill, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(CozyColor.outline, lineWidth: CozyBorder.card)
            }
            .cozyCardShadow()
    }
}

/// Card variant with no padding, for content that bleeds to the edge such as
/// a recipe hero image.
struct CrumbCardBleed<Content: View>: View {
    var cornerRadius: CGFloat = CozyRadius.card

    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(CozyColor.outline, lineWidth: CozyBorder.card)
            }
            .cozyCardShadow()
    }
}

#Preview("Cards") {
    VStack(spacing: CozySpacing.l) {
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
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CozyColor.cream)
}
