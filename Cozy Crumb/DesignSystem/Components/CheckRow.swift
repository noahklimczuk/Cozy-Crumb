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

import SwiftUI

struct CheckRow<Accessory: View>: View {
    let title: String
    var subtitle: String?
    let isChecked: Bool

    /// Fill of the tick once it is on. Defaults to the app's success green;
    /// the grocery list passes its aisle colour so a ticked row still says
    /// which shelf it came off.
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

    private var tickFill: Color { tint ?? CozyColor.success }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: CozySpacing.m) {
                tick

                VStack(alignment: .leading, spacing: 2) {
                    label

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .cozyText(CozyFont.caption2, color: CozyColor.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    accessory
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, CozySpacing.xs)
            .frame(minHeight: CozyMetrics.minimumTouchTarget)
            .contentShape(.rect)
            .opacity(isChecked ? 0.6 : 1)
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

    private var tick: some View {
        ZStack {
            Circle()
                .fill(isChecked ? tickFill : CozyColor.card)

            Circle()
                .strokeBorder(isChecked ? tickFill : CozyColor.outlineStrong,
                              lineWidth: CozyBorder.card)

            Image(systemName: "checkmark")
                .font(.caption2.weight(.black))
                .foregroundStyle(CozyColor.inkPrimary)
                .opacity(isChecked ? 1 : 0)
        }
        .frame(width: 24, height: 24)
        // Sits on the title's first line rather than the middle of a
        // three-line row.
        .padding(.top, 1)
        .accessibilityHidden(true)
    }

    /// The strikethrough is a capsule scaled from its leading edge, not
    /// `.strikethrough(_:)`, so it draws across the words.
    private var label: some View {
        Text(title)
            .cozyText(CozyFont.body)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.numericText())
            .overlay(alignment: .leading) {
                if strikesThrough {
                    Capsule()
                        .fill(CozyColor.inkSecondary)
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

    VStack(spacing: 0) {
        AisleTag(title: "Baking", systemImage: "birthday.cake", count: 4, tint: CozyColor.butter)
            .padding(.bottom, CozySpacing.s)

        CrumbCard(padding: CozySpacing.m) {
            VStack(spacing: 0) {
                ForEach(Array(CheckRowPreviewData.rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Divider().overlay(CozyColor.outline)
                    }

                    CheckRow(
                        title: row.title,
                        subtitle: row.subtitle,
                        isChecked: ticked.contains(row.title),
                        tint: CozyColor.butter,
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
