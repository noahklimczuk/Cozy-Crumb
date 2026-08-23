//
//  IngredientRow.swift
//  Cozy Crumb
//
//  One ingredient line, scaled to the current servings and converted into the
//  chosen system. Section headers ("For the sauce:") render as headers rather
//  than as tickable items.
//
//  The tickable line is a `CheckRow`. What is left here is the part that is
//  actually about ingredients: working out what the line says at these
//  servings in these units, and warning when the scaled amount is awkward to
//  measure. The circle, the swept strikethrough and the VoiceOver wording are
//  shared with the shopping list, which is where they had already drifted
//  apart from these.
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
        CheckRow(
            title: displayText,
            subtitle: ingredient.note,
            isChecked: isChecked,
            action: onToggle
        ) {
            if let awkward = scaled.awkwardNote {
                Text(awkward)
                    .cozyText(CozyFont.caption, color: CozyColor.inkPrimary)
                    .padding(.horizontal, CozySpacing.s)
                    .padding(.vertical, 3)
                    .background(CozyColor.warning.cozyPaled(0.3),
                                in: .rect(cornerRadius: 8, style: .continuous))
                    .padding(.top, 2)
            }
        }
        // The tick's own animation lives in CheckRow. This one is for the
        // quantity re-scaling under the servings stepper, which is this
        // screen's business and nothing to do with ticking.
        .cozyAnimation(Motion.snappy, value: targetServings)
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
