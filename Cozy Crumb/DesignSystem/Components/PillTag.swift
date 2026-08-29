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

/// Read-only metadata chip — "1h 15m", "8".
///
/// Flat, borderless and small. The hairline is gone because these sit in twos
/// and threes under a card title, where an outline each turned a line of
/// metadata into a row of little boxes; and the icons are gone with it,
/// because a clock beside "1h 15m" was saying the same word twice.
struct PillTag: View {
    let text: String
    var systemImage: String?
    var tint: Color = CozyColor.creamDeep
    /// Ink for the text. Defaults to the quiet one, since metadata is what you
    /// read *after* the title; a pill on a coloured surface passes its own.
    var ink: Color = CozyColor.inkSecondary

    var body: some View {
        HStack(spacing: CozySpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .font(CozyFont.caption.weight(.semibold))
        }
        .foregroundStyle(ink)
        .padding(.horizontal, CozySpacing.s)
        .padding(.vertical, 5)
        .background(tint, in: .rect(cornerRadius: CozyRadius.pill, style: .continuous))
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
    /// What the count is counting, in the singular. "3 items", "1 item".
    ///
    /// It used to be the plural and was used verbatim, so a shelf with one
    /// thing on it read "1 items". Every Pantry category with a single
    /// ingredient said so, in every capture.
    var countNoun: String = "item"

    /// The plural, where adding an "s" is wrong — "2 going off" is the same
    /// phrase at any count.
    var countNounPlural: String?

    /// "1 item", "5 items", or nothing when there is no count to show.
    private var countLabel: String? {
        guard let count else { return nil }
        let noun = count == 1 ? countNoun : (countNounPlural ?? countNoun + "s")
        return "\(count) \(noun)"
    }

    var body: some View {
        HStack(spacing: CozySpacing.s) {
            HStack(spacing: CozySpacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption2.weight(.bold))
                }
                Text(title)
                    // A shelf name is one word, and one word must never break
                    // across two lines: the AX5 Pantry capture read "PANT /
                    // RY" inside the butter tile. Tracked-out capitals are
                    // wide, so the last of the slack comes from scaling.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .cozyEyebrow(color: CozyColor.inkOnAccent, tracking: CozyTracking.eyebrowTight)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(tint, in: .rect(cornerRadius: CozyRadius.pill, style: .continuous))

            // Outside the tag rather than inside it. The tag names a shelf and
            // is a fixed, coloured, tracked-out label; the count is live and
            // changes as things are ticked off, and the two stopped reading as
            // one object the moment the tag became a small hard-edged tile.
            if let countLabel {
                Text(countLabel)
                    .cozyText(CozyFont.caption.weight(.semibold), color: CozyColor.inkSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(countLabel.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Tappable chip with a selected state — Collections, filters, Sous Chef
/// suggestion chips. Keeps a full 44pt hit area even though it draws smaller.
struct SelectableChip: View {
    @Environment(\.accentPalette) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize

    let text: String
    var systemImage: String?

    /// Drop the written label at accessibility sizes and keep the glyph alone.
    ///
    /// Only for a chip whose glyph already says the whole thing — the "+" that
    /// makes a new collection. A collection's *name* can never do this: there
    /// is no icon for "Weeknight", and a row of identical folder glyphs is
    /// worse than a row that scrolls.
    ///
    /// The chip keeps its full name in `accessibilityLabel`, so this changes
    /// what is drawn and nothing about what VoiceOver reads.
    var iconOnlyAtAccessibilitySizes = false
    /// The selected fill. Defaults to whatever the user has set as the app
    /// accent, which is what most call sites want; pass a colour only where
    /// the chip stands for something that already has one of its own (a
    /// collection, a grocery aisle).
    var tint: Color?
    let isSelected: Bool
    let action: () -> Void

    private var selectedFill: Color { tint ?? accent.color }

    private var isIconOnly: Bool {
        iconOnlyAtAccessibilitySizes && systemImage != nil && typeSize.isAccessibilitySize
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: CozySpacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                }
                if !isIconOnly {
                    Text(text)
                        .font(CozyFont.caption.weight(.semibold))
                }
            }
            .foregroundStyle(isSelected ? CozyColor.inkOnAccent : CozyColor.inkPrimary)
            .padding(.horizontal, CozySpacing.l)
            .padding(.vertical, 9)
            .background(isSelected ? selectedFill : CozyColor.card, in: .capsule)
            // Draws compact, but stays comfortably tappable (§7.6).
            .frame(minHeight: CozyMetrics.minimumTouchTarget)
            .contentShape(.capsule)
            // An unselected chip is a drawn outline; a selected one is filled
            // and needs none. Neither carries a block: these come in a row of
            // five or six, and a row of little blocks is a row of buttons.
            .overlay {
                if !isSelected {
                    Capsule().strokeBorder(CozyColor.outlineStrong,
                                           lineWidth: CozyBorder.illustrative)
                }
            }
        }
        .buttonStyle(.squishy)
        .accessibilityLabel(text)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
