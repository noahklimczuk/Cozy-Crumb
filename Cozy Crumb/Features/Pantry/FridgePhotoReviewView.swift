//
//  FridgePhotoReviewView.swift
//  Cozy Crumb
//
//  What the camera thought it saw, before any of it is believed.
//
//  Nothing from a photo reaches the pantry without passing through here — the
//  same rule imported recipes follow. A model looking at a fridge is confident
//  and often wrong, and a pantry quietly full of things you don't own is worse
//  than an empty one, because the Sous Chef reads it.
//
//  The unsure rows aren't hidden. "Is that mustard?" is a useful question, and
//  it costs a glance to answer — so anything below the confidence floor is
//  shown under its own heading, starting unticked.
//

import SwiftUI

struct FridgePhotoReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accentPalette) private var accent

    let items: [SpottedPantryItem]
    let onAccept: ([SpottedPantryItem]) -> Void
    let onCancel: () -> Void

    @State private var selected: Set<UUID>

    init(
        items: [SpottedPantryItem],
        onAccept: @escaping ([SpottedPantryItem]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.items = items
        self.onAccept = onAccept
        self.onCancel = onCancel

        // Sure things start ticked; guesses start unticked and wait to be
        // agreed with.
        _selected = State(initialValue: Set(items.filter(\.isConfident).map(\.id)))
    }

    private var confident: [SpottedPantryItem] { items.filter(\.isConfident) }
    private var unsure: [SpottedPantryItem] { items.filter { !$0.isConfident } }

    private var keptItems: [SpottedPantryItem] {
        items.filter { selected.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CozySpacing.l) {
                    intro

                    if !confident.isEmpty {
                        section(title: "Spotted", symbol: "checkmark.circle", tint: CozyColor.mint, items: confident)
                    }

                    if !unsure.isEmpty {
                        section(
                            title: "Not sure about these",
                            symbol: "questionmark.circle",
                            tint: CozyColor.warning,
                            items: unsure
                        )
                    }
                }
                .padding(CozySpacing.l)
            }
            .background { BlobBackground() }
            .navigationTitle("In the fridge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { addBar }
        }
    }

    private var intro: some View {
        CrumbCard(fill: CozyColor.creamDeep) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tick what's really there")
                    .cozyText(CozyFont.headline)
                Text("I'm reading a photo, so I get things wrong. Nothing goes in the pantry until you say so.")
                    .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section(
        title: String,
        symbol: String,
        tint: Color,
        items: [SpottedPantryItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: CozySpacing.s) {
            HStack(spacing: CozySpacing.xs) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(CozyFont.caption.weight(.semibold))
                Spacer()
                Text("\(items.count)")
                    .font(CozyFont.caption2)
            }
            .foregroundStyle(CozyColor.inkPrimary)
            .padding(.horizontal, CozySpacing.m)
            .padding(.vertical, CozySpacing.s)
            .background(tint.opacity(0.55), in: .rect(cornerRadius: CozyRadius.chip, style: .continuous))

            CrumbCard(padding: CozySpacing.s) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider()
                                .overlay(CozyColor.outline)
                                .padding(.leading, CozySpacing.xl)
                        }

                        row(for: item)
                    }
                }
            }
        }
    }

    private func row(for item: SpottedPantryItem) -> some View {
        let isSelected = selected.contains(item.id)

        return Button {
            toggle(item)
        } label: {
            HStack(spacing: CozySpacing.s) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? accent.deep : CozyColor.inkSecondary)
                    .contentTransition(.symbolEffect(.replace))

                Text(item.name)
                    .cozyText(CozyFont.body)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: CozySpacing.s)

                if let amount = amountText(for: item) {
                    Text(amount)
                        .cozyText(CozyFont.bodyEmphasis, color: CozyColor.inkSecondary)
                        .monospacedDigit()
                }
            }
            .opacity(isSelected ? 1 : 0.55)
            .padding(.vertical, CozySpacing.s)
            .padding(.horizontal, CozySpacing.s)
            .frame(minHeight: CozyMetrics.minimumTouchTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func amountText(for item: SpottedPantryItem) -> String? {
        let text = FractionFormatter.quantityString(quantity: item.quantity, unit: item.unit)
        return text.isEmpty ? nil : text
    }

    private func toggle(_ item: SpottedPantryItem) {
        if selected.contains(item.id) {
            selected.remove(item.id)
        } else {
            selected.insert(item.id)
        }
        Haptics.selection()
    }

    private var addBar: some View {
        SquishyButton(
            title: keptItems.isEmpty ? "Nothing ticked" : "Put \(keptItems.count) in the pantry",
            systemImage: "refrigerator"
        ) {
            onAccept(keptItems)
            dismiss()
        }
        .disabled(keptItems.isEmpty)
        .opacity(keptItems.isEmpty ? 0.5 : 1)
        .padding(.horizontal, CozySpacing.l)
        .padding(.vertical, CozySpacing.m)
        .background(.ultraThinMaterial)
    }
}

#Preview("Fridge review") {
    FridgePhotoReviewView(
        items: [
            SpottedPantryItem(name: "Milk", quantity: 1, unit: "l", category: .dairy, confidence: 0.95),
            SpottedPantryItem(name: "Red peppers", quantity: 3, category: .produce, confidence: 0.88),
            SpottedPantryItem(name: "Cheddar", category: .dairy, confidence: 0.71),
            SpottedPantryItem(name: "Mustard", category: .condiment, confidence: 0.34)
        ],
        onAccept: { _ in },
        onCancel: {}
    )
}
