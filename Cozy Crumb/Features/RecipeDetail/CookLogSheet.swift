//
//  CookLogSheet.swift
//  Cozy Crumb
//
//  "I made this" — records a cook with an optional rating and note.
//
//  CookLog already models a photo, but attaching one needs PhotosPicker and
//  an async Transferable load; that lands with the image pipeline in Phase 4
//  rather than being half-built here.
//

import SwiftUI

struct CookLogSheet: View {
    @Environment(\.dismiss) private var dismiss

    let recipeTitle: String
    let onSave: (Int?, String?) -> Void

    @State private var rating: Int?
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CozySpacing.xl) {
                    VStack(spacing: CozySpacing.s) {
                        MascotView(pose: .celebrating, size: 96)
                        Text("You made \(recipeTitle)!")
                            .cozyText(CozyFont.title2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, CozySpacing.l)

                    CrumbCard {
                        VStack(spacing: CozySpacing.m) {
                            Text("How did it go?")
                                .cozyText(CozyFont.headline)
                            stars
                        }
                        .frame(maxWidth: .infinity)
                    }

                    CrumbCard {
                        VStack(alignment: .leading, spacing: CozySpacing.s) {
                            Text("Anything to remember?")
                                .cozyText(CozyFont.headline)
                            TextField(
                                "Needed 5 more minutes…",
                                text: $notes,
                                axis: .vertical
                            )
                            .font(CozyFont.body)
                            .foregroundStyle(CozyColor.inkPrimary)
                            .lineLimit(3...6)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    SquishyButton(title: "Log it", systemImage: "checkmark") {
                        onSave(rating, notes.isEmpty ? nil : notes)
                        dismiss()
                    }
                }
                .padding(CozySpacing.l)
            }
            .background { BlobBackground() }
            .navigationTitle("I made this")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(CozyRadius.sheet)
        .presentationDragIndicator(.visible)
    }

    private var stars: some View {
        HStack(spacing: CozySpacing.s) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    // Tapping the current rating clears it.
                    rating = (rating == value) ? nil : value
                } label: {
                    Image(systemName: (rating ?? 0) >= value ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundStyle((rating ?? 0) >= value ? CozyColor.warning : CozyColor.inkSecondary)
                        .frame(width: CozyMetrics.minimumTouchTarget,
                               height: CozyMetrics.minimumTouchTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.squishy)
                .accessibilityLabel("\(value) star\(value == 1 ? "" : "s")")
                .accessibilityAddTraits((rating ?? 0) >= value ? [.isSelected] : [])
            }
        }
        .cozyAnimation(Motion.bouncy, value: rating)
    }
}

#Preview("Cook log") {
    CookLogSheet(recipeTitle: "Brown Butter Banana Bread") { _, _ in }
}
