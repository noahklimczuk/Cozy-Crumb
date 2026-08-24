//
//  CheckRow.swift
//  Cozy Crumb
//
//  One tickable line. The shopping list and a recipe's ingredients had grown
//  a checkbox each — same idea, different circle, different strikethrough,
//  different VoiceOver wording — and the two had already drifted. This is the
//  one of them.
//
//  The line through a ticked title is drawn rather than toggled, so it sweeps
//  across the words instead of appearing all at once. That timing is the whole
//  reason ticking something off feels good, and it is the sort of detail that
//  quietly goes missing when two screens each own a copy.
//
//  The row now carries its own surface — white unticked, the accent once
//  ticked — instead of being a bare line inside a shared card with dividers
//  between. Rows are laid out in a stack with a small gap, not glued into a
//  list, and there is nothing left for a divider to do.
//

import SwiftUI

struct CheckRow<Accessory: View>: View {
    @Environment(\.accentPalette) private var accent

    let title: String
    var subtitle: String?
    let isChecked: Bool

    /// Fill of the whole row once it is ticked. Defaults to the accent.
    ///
    /// This used to be the fill of the tick alone, on a row that had no
    /// surface of its own and lived inside a shared card. The row is its own
    /// surface now, and ticking one paints all of it — which is the state
    /// change you can see from across a kitchen, and the reason the tick
    /// itself no longer needs to carry the colour.
    var tint: Color?

    /// Whether ticking strikes the title through.
    var strikesThrough: Bool = true

    /// What VoiceOver reads for the two states. "Got it" / "still to buy" on
    /// a shopping list, "ticked off" / "not ticked off" on a recipe.
    var checkedValue: String = "ticked off"
    var uncheckedValue: String = "not ticked off"
    var hint: String = "Double-tap to tick off"

    /// Always passed with its label at call sites, never as a bare trailing
    /// closure: the accessory slot is also a closure, and an unlabelled one
    /// would make the two overloads below ambiguous.
    let action: () -> Void

    /// Anything that belongs on the right of the row — a warning about an
    /// awkward quantity, a use-by date, a swipe affordance.
    let accessory: Accessory

    init(
        title: String,
        subtitle: String? = nil,
        isChecked: Bool,
        tint: Color? = nil,
        strikesThrough: Bool = true,
        checkedValue: String = "ticked off",
        uncheckedValue: String = "not ticked off",
        hint: String = "Double-tap to tick off",
        action: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isChecked = isChecked
        self.tint = tint
        self.strikesThrough = strikesThrough
        self.checkedValue = checkedValue
        self.uncheckedValue = uncheckedValue
        self.hint = hint
        self.action = action
        self.accessory = accessory()
    }

    private var rowFill: Color { isChecked ? (tint ?? accent.color) : CozyColor.card }

    /// Ink for everything in the row. A ticked row is a blush surface, so it
    /// takes the ink blush surfaces take, in both appearances.
    private var ink: Color { isChecked ? CozyColor.inkOnBlush : CozyColor.inkPrimary }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: CozySpacing.m) {
                tick

                VStack(alignment: .leading, spacing: 2) {
                    label

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .cozyText(CozyFont.caption2,
                                      color: isChecked ? ink.opacity(0.8) : CozyColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    accessory
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, CozySpacing.m)
            .padding(.vertical, CozySpacing.s)
            .frame(minHeight: 52, alignment: .center)
            .background(rowFill, in: .rect(cornerRadius: CozyRadius.field, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .cozyAnimation(Motion.bouncy, value: isChecked)
        // A Button already reads as one element; the labels below only
        // replace what it would have read out of its own contents.
        .accessibilityLabel([title, subtitle].compactMap { $0 }.joined(separator: ", "))
        .accessibilityValue(isChecked ? checkedValue : uncheckedValue)
        .accessibilityHint(hint)
        .accessibilityAddTraits(isChecked ? [.isSelected] : [])
    }

    /// A rounded square, not a circle, and butter when it is on.
    ///
    /// Butter rather than the row's own colour: the row underneath has just
    /// gone blush, and a blush tick on a blush row is a shape with nothing to
    /// sit against. The one warm yellow thing on the screen is the thing you
    /// just did.
    private var tick: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isChecked ? CozyColor.butter : .clear)

            if !isChecked {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(CozyColor.outlineStrong, lineWidth: 2.5)
            }

            Image(systemName: "checkmark")
                .font(.caption2.weight(.black))
                .foregroundStyle(CozyColor.inkOnBlush)
                .opacity(isChecked ? 1 : 0)
        }
        .frame(width: 22, height: 22)
        // Sits on the title's first line rather than the middle of a
        // three-line row.
        .padding(.top, 1)
        .accessibilityHidden(true)
    }

    /// The strikethrough is a capsule scaled from its leading edge, not
    /// `.strikethrough(_:)`, so it draws across the words.
    ///
    /// A ticked title fades, but only to 0.8. The mockup takes it to 0.5,
    /// which lands at 3.0:1 on blush and 2.6:1 on the dark blush — a line of
    /// text nobody can read is not a subtler way of saying "done", and this
    /// row already says it twice over with the fill and the line through.
    private var label: some View {
        Text(title)
            .cozyText(CozyFont.body, color: isChecked ? ink.opacity(0.8) : ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.numericText())
            .overlay(alignment: .leading) {
                if strikesThrough {
                    Capsule()
                        .fill(ink.opacity(0.8))
                        .frame(height: 1.5)
                        .scaleEffect(x: isChecked ? 1 : 0, anchor: .leading)
                        .cozyAnimation(Motion.snappy, value: isChecked)
                }
            }
    }
}

// MARK: - No accessory

extension CheckRow where Accessory == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        isChecked: Bool,
        tint: Color? = nil,
        strikesThrough: Bool = true,
        checkedValue: String = "ticked off",
        uncheckedValue: String = "not ticked off",
        hint: String = "Double-tap to tick off",
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            isChecked: isChecked,
            tint: tint,
            strikesThrough: strikesThrough,
            checkedValue: checkedValue,
            uncheckedValue: uncheckedValue,
            hint: hint,
            action: action,
            accessory: { EmptyView() }
        )
    }
}

// MARK: - Preview

#Preview("Check rows") {
    @Previewable @State var ticked: Set<String> = ["2 cups plain flour"]

    VStack(alignment: .leading, spacing: CozySpacing.s) {
        AisleTag(title: "Baking", systemImage: "birthday.cake", count: 4, tint: CozyColor.butter)

        VStack(spacing: 6) {
            ForEach(Array(CheckRowPreviewData.rows.enumerated()), id: \.offset) { _, row in
                CheckRow(
                    title: row.title,
                    subtitle: row.subtitle,
                    isChecked: ticked.contains(row.title),
                    action: {
                        if ticked.contains(row.title) {
                            ticked.remove(row.title)
                        } else {
                            ticked.insert(row.title)
                        }
                    }
                )
            }
        }

        CheckRow(title: "3 tbsp tahini", isChecked: false, action: {}) {
            Text("that's most of a jar")
                .cozyText(CozyFont.caption, color: CozyColor.inkPrimary)
                .padding(.horizontal, CozySpacing.s)
                .padding(.vertical, 3)
                .background(CozyColor.warning.cozyPaled(0.3),
                            in: .rect(cornerRadius: 8, style: .continuous))
                .padding(.top, 2)
        }
        .padding(.top, CozySpacing.l)
    }
    .padding(CozySpacing.l)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .cozyScreenBackground()
}

private enum CheckRowPreviewData {
    struct Row: Sendable {
        let title: String
        let subtitle: String?
    }

    static let rows: [Row] = [
        Row(title: "2 cups plain flour", subtitle: nil),
        Row(title: "1 tsp baking soda", subtitle: "sifted"),
        Row(title: "3 very ripe bananas", subtitle: "needs 4 · from Banana Bread"),
        Row(title: "A pinch of salt", subtitle: nil)
    ]
}
