//
//  StepCard.swift
//  Cozy Crumb
//
//  A numbered instruction card. Steps that state an explicit time show a
//  duration chip.
//
//  The chip is display-only for now — tapping it to start a live timer needs
//  the timer service that arrives with Cook Mode in Phase 6.
//

import SwiftUI

struct StepCard: View {
    let step: RecipeStep
    let number: Int

    var body: some View {
        CrumbCard {
            HStack(alignment: .top, spacing: CozySpacing.m) {
                numberBadge

                VStack(alignment: .leading, spacing: CozySpacing.s) {
                    Text(step.text)
                        .cozyText(CozyFont.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let duration = step.durationDisplay {
                        PillTag(text: duration, systemImage: "timer", tint: CozyColor.butter)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(step.text)")
    }

    private var numberBadge: some View {
        Text("\(number)")
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(CozyColor.inkPrimary)
            .frame(width: 28, height: 28)
            .background(CozyColor.blushSoft, in: .circle)
            .overlay {
                Circle().strokeBorder(CozyColor.outline, lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

#Preview("Step cards") {
    let recipe = SeedData.bananaBread()

    return ScrollView {
        VStack(spacing: CozySpacing.m) {
            ForEach(Array(recipe.orderedSteps.enumerated()), id: \.element.id) { index, step in
                StepCard(step: step, number: index + 1)
            }
        }
        .padding()
    }
    .background { BlobBackground() }
}
