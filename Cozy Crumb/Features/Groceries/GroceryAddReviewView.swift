//
//  GroceryAddReviewView.swift
//  Cozy Crumb
//
//  The last look before things land on the shopping list.
//
//  This is where a week's worth of recipes becomes one shop, so the screen's
//  job is to make the consolidation *visible*: seven recipes asking for olive
//  oil should read as one line saying 7 tbsp, with the recipes it came from
//  underneath. A flat list of everything every recipe wanted is exactly the
//  thing this screen exists to prevent.
//
//  Folding happens here as well as in the caller, deliberately. Callers can
//  and do pass raw lines, and the user should never see a duplicate on the
//  screen whose whole purpose is not showing duplicates.
//
//  Everything starts ticked. Someone who tapped "add the week to my list"
//  wants the week; unticking the two things they already have is the
//  exception, not the default.
//

import Foundation
import SwiftData
import SwiftUI

/// One row: a folded line plus a stable identity for selection.
private struct GroceryLineEntry: Identifiable {
    let id = UUID()
    let line: GroceryLineItem
}

private struct GroceryLineGroup: Identifiable {
    let category: GroceryCategory
    let entries: [GroceryLineEntry]

    var id: GroceryCategory { category }
}

struct GroceryAddReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accentPalette) private var accent
    @Environment(\.dismiss) private var dismiss

    let sourceTitle: String

    @State private var selected: Set<UUID>

    private let groups: [GroceryLineGroup]
    private let entries: [GroceryLineEntry]

    init(lines: [GroceryLineItem], sourceTitle: String) {
        self.sourceTitle = sourceTitle

        // Fold first, then group: merging has to happen across categories
        // before anything is split by them.
        let folded = GroceryMerge.folded(lines).map { GroceryLineEntry(line: $0) }
        self.entries = folded

        self.groups = Dictionary(grouping: folded) { $0.line.category }
            .map { GroceryLineGroup(category: $0.key, entries: $0.value) }
            .sorted { $0.category.sortOrder < $1.category.sortOrder }

        _selected = State(initialValue: Set(folded.map(\.id)))
    }

    private var selectedLines: [GroceryLineItem] {
        entries.filter { selected.contains($0.id) }.map(\.line)
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    EmptyStateView(
                        title: "Nothing to buy here.",
                        message: "Every ingredient on this one is a pinch of something, or has no amount to shop for.",
                        pose: .idle
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
            .background { BlobBackground() }
            .navigationTitle("Add to list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(allSelected ? "None" : "All") {
                        toggleAll()
                    }
                    .font(CozyFont.subheadline)
                }
            }
            .safeAreaInset(edge: .bottom) { addBar }
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CozySpacing.l) {
                summary

                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: CozySpacing.s) {
                        categoryHeader(group.category, count: group.entries.count)

                        CrumbCard(padding: CozySpacing.s) {
                            VStack(spacing: 0) {
                                ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                                    if index > 0 {
                                        Divider()
                                            .overlay(CozyColor.outline)
                                            .padding(.leading, CozySpacing.xl + CozySpacing.s)
                                    }

                                    row(for: entry)
                                }
                            }
                        }
                    }
                }
            }
            .padding(CozySpacing.l)
        }
    }

    private var summary: some View {
        CrumbCard(fill: CozyColor.creamDeep) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sourceTitle)
                    .cozyText(CozyFont.headline)
                Text("\(entries.count) \(entries.count == 1 ? "thing" : "things") to buy, "
                    + "with anything that appeared twice added together.")
                    .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func categoryHeader(_ category: GroceryCategory, count: Int) -> some View {
        HStack(spacing: CozySpacing.xs) {
            Image(systemName: category.symbol)
                .font(.caption.weight(.semibold))
            Text(category.displayName)
                .font(CozyFont.caption.weight(.semibold))
            Spacer()
            Text("\(count)")
                .font(CozyFont.caption2)
        }
        .foregroundStyle(CozyColor.inkPrimary)
        .padding(.horizontal, CozySpacing.m)
        .padding(.vertical, CozySpacing.s)
        .background(category.tint.opacity(0.55), in: .rect(cornerRadius: CozyRadius.chip, style: .continuous))
    }

    private func row(for entry: GroceryLineEntry) -> some View {
        let isSelected = selected.contains(entry.id)

        return Button {
            toggle(entry)
        } label: {
            HStack(alignment: .top, spacing: CozySpacing.s) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? accent.deep : CozyColor.inkSecondary)
                    .contentTransition(.symbolEffect(.replace))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: CozySpacing.xs) {
                        Text(entry.line.name)
                            .cozyText(CozyFont.body)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: CozySpacing.s)

                        // The amount is the point of the fold, so it gets the
                        // emphasis rather than sitting in a caption.
                        if let amount = amountText(for: entry.line) {
                            Text(amount)
                                .cozyText(CozyFont.bodyEmphasis, color: CozyColor.inkSecondary)
                                .monospacedDigit()
                        }
                    }

                    if let caption = caption(for: entry.line) {
                        Text(caption)
                            .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .opacity(isSelected ? 1 : 0.5)
            .padding(.vertical, CozySpacing.s)
            .padding(.horizontal, CozySpacing.s)
            .frame(minHeight: CozyMetrics.minimumTouchTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: entry.line))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func amountText(for line: GroceryLineItem) -> String? {
        let text = FractionFormatter.quantityString(quantity: line.quantity, unit: line.unit)
        return text.isEmpty ? nil : text
    }

    /// Says where a line came from, and — when it came from more than one
    /// recipe — that it was added together rather than listed twice.
    private func caption(for line: GroceryLineItem) -> String? {
        var parts: [String] = []

        switch line.sourceRecipeTitles.count {
        case 0:
            break
        case 1:
            parts.append(line.sourceRecipeTitles[0])
        case let count:
            parts.append("\(line.sourceRecipeTitles[0]) + \(count - 1) more")
        }

        if let existing = existingMatch(for: line) {
            parts.append("adds to the \(FractionFormatter.quantityString(quantity: existing.quantity, unit: existing.unit)) already on your list")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The row on the list this one will fold into, if there is one. Uses the
    /// same rule the save path uses, so the hint can't promise a merge that
    /// won't happen.
    private func existingMatch(for line: GroceryLineItem) -> GroceryItem? {
        let list = GroceryService.activeList(in: modelContext)

        return list.items.first { item in
            !item.isChecked && GroceryMerge.canMerge(GroceryService.lineItem(for: item), line)
        }
    }

    private func accessibilityLabel(for line: GroceryLineItem) -> String {
        let amount = amountText(for: line)
        return [amount, line.name].compactMap { $0 }.joined(separator: " ")
    }

    // MARK: - Selection

    private var allSelected: Bool {
        selected.count == entries.count
    }

    private func toggle(_ entry: GroceryLineEntry) {
        if selected.contains(entry.id) {
            selected.remove(entry.id)
        } else {
            selected.insert(entry.id)
        }
        Haptics.selection()
    }

    private func toggleAll() {
        selected = allSelected ? [] : Set(entries.map(\.id))
        Haptics.soft()
    }

    // MARK: - Adding

    private var addBar: some View {
        VStack(spacing: CozySpacing.s) {
            SquishyButton(
                title: selectedLines.isEmpty
                    ? "Nothing selected"
                    : "Add \(selectedLines.count) to my list",
                systemImage: "checklist"
            ) {
                add()
            }
            .disabled(selectedLines.isEmpty)
            .opacity(selectedLines.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, CozySpacing.l)
        .padding(.vertical, CozySpacing.m)
        .background(.ultraThinMaterial)
    }

    private func add() {
        guard !selectedLines.isEmpty else { return }

        let list = GroceryService.activeList(in: modelContext)
        _ = GroceryService.add(selectedLines, to: list, in: modelContext)

        Haptics.notify(.success)
        dismiss()
    }
}

// MARK: - Previews

#Preview("Add review") {
    GroceryAddReviewView(lines: PreviewLines.lines, sourceTitle: "This week's meals")
        .modelContainer(PreviewData.container)
}

private enum PreviewLines {
    static var lines: [GroceryLineItem] {
        [
            GroceryLineItem(name: "Onion", quantity: 2, unit: nil, category: .produce,
                            sourceRecipeTitles: ["Chickpea Curry"]),
            GroceryLineItem(name: "chopped onions", quantity: 1, unit: nil, category: .produce,
                            sourceRecipeTitles: ["Bolognese"]),
            GroceryLineItem(name: "Olive oil", quantity: 3, unit: "tbsp", category: .condiment,
                            sourceRecipeTitles: ["Chickpea Curry", "Bolognese", "Miso Salmon"]),
            GroceryLineItem(name: "Flour", quantity: 500, unit: "g", category: .bakery,
                            sourceRecipeTitles: ["Banana Bread"]),
            GroceryLineItem(name: "Eggs", quantity: 6, unit: nil, category: .dairy,
                            sourceRecipeTitles: ["Banana Bread", "Shakshuka"])
        ]
    }
}
