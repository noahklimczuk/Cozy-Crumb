//
//  PillTag.swift
//  Cozy Crumb
//
//  Small pastel chips: recipe metadata (time, servings), tags, grocery
//  categories, and the selectable Collection chips above the Library grid.
//

import SwiftUI

/// Read-only metadata chip.
struct PillTag: View {
    let text: String
    var systemImage: String?
    var tint: Color = CozyColor.creamDeep

    var body: some View {
        HStack(spacing: CozySpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .font(CozyFont.caption)
        }
        .foregroundStyle(CozyColor.inkPrimary)
        .padding(.horizontal, CozySpacing.m)
        .padding(.vertical, CozySpacing.s)
        .background(tint, in: .rect(cornerRadius: CozyRadius.chip, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CozyRadius.chip, style: .continuous)
                .strokeBorder(CozyColor.outline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Tappable chip with a selected state — Collections, filters, Sous Chef
/// suggestion chips. Keeps a full 44pt hit area even though it draws smaller.
struct SelectableChip: View {
    let text: String
    var systemImage: String?
    var tint: Color = CozyColor.mint
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: CozySpacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                }
                Text(text)
                    .font(CozyFont.caption)
            }
            .foregroundStyle(CozyColor.inkPrimary)
            .padding(.horizontal, CozySpacing.l)
            .padding(.vertical, CozySpacing.s)
            .background(
                isSelected ? tint : CozyColor.card,
                in: .rect(cornerRadius: CozyRadius.chip, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CozyRadius.chip, style: .continuous)
                    .strokeBorder(
                        isSelected ? CozyColor.outlineStrong : CozyColor.outline,
                        lineWidth: isSelected ? CozyBorder.illustrative : 1
                    )
            }
            // Draws compact, but stays comfortably tappable (§7.6).
            .frame(minHeight: CozyMetrics.minimumTouchTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.squishy)
        .accessibilityLabel(text)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview("Pills & chips") {
    VStack(alignment: .leading, spacing: CozySpacing.l) {
        HStack {
            PillTag(text: "35 min", systemImage: "clock")
            PillTag(text: "Serves 4", systemImage: "person.2", tint: CozyColor.butter)
            PillTag(text: "Baking", tint: CozyColor.lavender)
        }

        ScrollView(.horizontal) {
            HStack(spacing: CozySpacing.s) {
                SelectableChip(text: "Weeknight", tint: CozyColor.mint, isSelected: true) {}
                SelectableChip(text: "Baking", tint: CozyColor.butter, isSelected: false) {}
                SelectableChip(text: "Mom's", tint: CozyColor.peach, isSelected: false) {}
                SelectableChip(text: "Slow", tint: CozyColor.sky, isSelected: false) {}
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CozyColor.cream)
}
