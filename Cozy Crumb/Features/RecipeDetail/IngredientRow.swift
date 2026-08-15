//
//  IngredientRow.swift
//  Cozy Crumb
//
//  One ingredient line, scaled to the current servings and converted into the
//  chosen system. Section headers ("For the sauce:") render as headers rather
//  than as tickable items.
//

import SwiftUI

struct IngredientRow: View {
    let ingredient: Ingredient
    let originalServings: Int
    let targetServings: Int
    let system: MeasurementSystem
    let isChecked: Bool
    let onToggle: () -> Void

    private var scaled: ServingsScaler.Scaled {
        ServingsScaler.scale(
            ingredient,
            from: originalServings,
            to: targetServings,
            system: system
        )
    }

    var body: some View {
        if ingredient.isSectionHeader {
            header
        } else {
            row
        }
    }

    private var header: some View {
        Text(ingredient.rawText)
            .cozyText(CozyFont.headline, color: CozyColor.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, CozySpacing.m)
            .accessibilityAddTraits(.isHeader)
    }

    private var row: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: CozySpacing.m) {
                tickCircle

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayText)
                        .cozyText(CozyFont.body)
                        .strikethrough(isChecked, color: CozyColor.inkSecondary)
                        .opacity(isChecked ? 0.5 : 1)
                        .multilineTextAlignment(.leading)
                        .contentTransition(.numericText())

                    if let note = ingredient.note, !note.isEmpty {
                        Text(note)
                            .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                            .opacity(isChecked ? 0.5 : 1)
                    }

                    if let awkward = scaled.awkwardNote {
                        Text(awkward)
                            .cozyText(CozyFont.caption, color: CozyColor.inkPrimary)
                            .padding(.horizontal, CozySpacing.s)
                            .padding(.vertical, 3)
                            .background(CozyColor.warning.opacity(0.5),
                                        in: .rect(cornerRadius: 8, style: .continuous))
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(minHeight: CozyMetrics.minimumTouchTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .cozyAnimation(Motion.bouncy, value: isChecked)
        .cozyAnimation(Motion.snappy, value: targetServings)
        .accessibilityLabel(displayText)
        .accessibilityValue(isChecked ? "ticked off" : "not ticked off")
        .accessibilityHint("Double tap to tick off")
    }

    private var tickCircle: some View {
        ZStack {
            Circle()
                .strokeBorder(isChecked ? CozyColor.success : CozyColor.outlineStrong,
                              lineWidth: CozyBorder.card)
                .frame(width: 22, height: 22)

            if isChecked {
                Circle()
                    .fill(CozyColor.success)
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(CozyColor.inkPrimary)
            }
        }
        .padding(.top, 2)
    }

    /// Scaled amount plus the ingredient name. Falls back to the original
    /// verbatim line when there's no quantity to scale — "salt to taste"
    /// should read exactly as written.
    private var displayText: String {
        guard scaled.quantity != nil else {
            return ingredient.rawText
        }

        let amount = FractionFormatter.quantityString(
            quantity: scaled.quantity,
            unit: scaled.unit
        )

        return amount.isEmpty ? ingredient.name : "\(amount) \(ingredient.name)"
    }
}

#Preview("Ingredient rows") {
    let recipe = SeedData.chickpeaCurry()

    return ScrollView {
        VStack(alignment: .leading, spacing: CozySpacing.s) {
            ForEach(recipe.orderedIngredients) { ingredient in
                IngredientRow(
                    ingredient: ingredient,
                    originalServings: 4,
                    targetServings: 6,
                    system: .asWritten,
                    isChecked: false,
                    onToggle: {}
                )
            }
        }
        .padding()
    }
    .background(CozyColor.cream)
}
