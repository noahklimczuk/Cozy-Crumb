//
//  PillTag.swift
//  Cozy Crumb
//
//  Small pastel chips: recipe metadata (time, servings), tags, grocery
//  categories, and the selectable Collection chips above the Library grid.
//
//  Tags stay flat. They almost always sit inside something that already has a
//  block, and a block inside a block is noise — the hairline is enough to
//  separate a chip from the card it's on. Chips you can press are the
//  exception: those get a small block, because a control that lifts should
//  look like it can be pushed back down.
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

/// The heading over a run of grocery or pantry rows — "Produce", "Going off".
///
/// Same shape as a `PillTag`, but it carries a count and knows it is a header,
/// so VoiceOver announces it as one instead of reading it as another chip.
struct AisleTag: View {
    let title: String
    var systemImage: String?
    var count: Int?
    var tint: Color = CozyColor.creamDeep

    var body: some View {
        HStack(spacing: CozySpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
            }
            Text(title)
                .font(CozyFont.caption.weight(.semibold))

            if let count {
                Spacer(minLength: CozySpacing.s)
                Text("\(count)")
                    .font(CozyFont.numeralSmall)
            }
        }
        .foregroundStyle(CozyColor.inkPrimary)
        .padding(.horizontal, CozySpacing.m)
        .padding(.vertical, CozySpacing.s)
        .background(tint, in: .rect(cornerRadius: CozyRadius.chip, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Tappable chip with a selected state — Collections, filters, Sous Chef
/// suggestion chips. Keeps a full 44pt hit area even though it draws smaller.
struct SelectableChip: View {
    @Environment(\.accentPalette) private var accent

    let text: String
    var systemImage: String?
    /// The selected fill. Defaults to whatever the user has set as the app
    /// accent, which is what most call sites want; pass a colour only where
    /// the chip stands for something that already has one of its own (a
    /// collection, a grocery aisle).
    var tint: Color?
    let isSelected: Bool
    let action: () -> Void

    private var selectedFill: Color { tint ?? accent.color }

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
                isSelected ? selectedFill : CozyColor.card,
                in: .rect(cornerRadius: CozyRadius.chip, style: .continuous)
            )
            // Draws compact, but stays comfortably tappable (§7.6).
            .frame(minHeight: CozyMetrics.minimumTouchTarget)
            .contentShape(.rect)
            // Selected chips sit up off the page on a block. Unselected ones
            // lie flat and need the hairline, because card-on-cream is nearly
            // the same colour and the shape would otherwise disappear.
            .modifier(ChipEdge(isSelected: isSelected))
        }
        .buttonStyle(.squishy)
        .accessibilityLabel(text)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct ChipEdge: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content.cozyBlockShadow(CozyDepth.small)
        } else {
            content.overlay {
                RoundedRectangle(cornerRadius: CozyRadius.chip, style: .continuous)
                    .strokeBorder(CozyColor.outline, lineWidth: 1)
            }
        }
    }
}

#Preview("Pills & chips") {
    @Previewable @State var selected = "Weeknight"

    VStack(alignment: .leading, spacing: CozySpacing.l) {
        HStack {
            PillTag(text: "35 min", systemImage: "clock")
            PillTag(text: "Serves 4", systemImage: "person.2", tint: CozyColor.butter)
            PillTag(text: "Baking", tint: CozyColor.lavender)
        }

        AisleTag(title: "Produce", systemImage: "carrot", count: 6, tint: CozyColor.mint)
        AisleTag(title: "Going off", systemImage: "clock.badge.exclamationmark", count: 2,
                 tint: CozyColor.warning.cozyPaled(0.3))

        ScrollView(.horizontal) {
            HStack(spacing: CozySpacing.s) {
                ForEach(["Weeknight", "Baking", "Mom's", "Slow"], id: \.self) { name in
                    SelectableChip(text: name, isSelected: selected == name) {
                        selected = name
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, CozySpacing.xs)
        }
        .scrollIndicators(.hidden)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CozyColor.cream)
}
