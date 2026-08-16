//
//  GroceryAddReviewView.swift
//  Cozy Crumb
//
//  A review screen that appears before adding items to the grocery list.
//  Allows users to skip items they already have, with smart merging hints.
//

import Foundation
import SwiftData
import SwiftUI

struct GroceryAddReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accentPalette) private var accent
    @Environment(\.cozyMotion) private var motion
    @Environment(\.dismiss) private var dismiss

    let lines: [GroceryLineItem]
    let sourceTitle: String

    @State private var selectedItems: Set<UUID> = []

    private var selectedItemLines: [GroceryLineItem] {
        lines.filter { selectedItems.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                content
            }
            .background { BlobBackground() }
            .navigationTitle("Add to list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addSelectedItems()
                    } label: {
                        Text("Add \(selectedItemLines.count)")
                    }
                    .disabled(selectedItemLines.isEmpty)
                    .foregroundStyle(accent.color)
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
    }

    @ViewBuilder
    private var content: some View {
        if lines.isEmpty {
            EmptyStateView(
                title: "Nothing to add",
                message: "There are no items from \(sourceTitle) to add to the list.",
                pose: .idle
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    ForEach(lines) { line in
                        listRow(for: line)
                    }
                } header: {
                    Text("Items from \(sourceTitle)")
                        .cozyText(CozyFont.body, color: CozyColor.inkSecondary)
                        .padding(.horizontal, CozySpacing.s)
                        .padding(.vertical, 6)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    private func listRow(for line: GroceryLineItem) -> some View {
        Button {
            toggleSelection(for: line)
        } label: {
            HStack(spacing: CozySpacing.m) {
                Image(systemName: selectedItems.contains(line.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selectedItems.contains(line.id) ? accent.color : CozyColor.inkSecondary)
                    .contentTransition(.symbolEffect(.replace))

                VStack(alignment: .leading, spacing: 2) {
                    Text(line.name)
                        .cozyText(CozyFont.body)

                    if let quantity = line.quantity, let unit = line.unit {
                        Text(FractionFormatter.quantityString(quantity: quantity, unit: unit))
                            .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
                    }
                }

                Spacer()

                if let quantity = line.quantity {
                    if let unit = line.unit, let dimension = GroceryMerge.dimension(of: unit) {
                        let existing = findExistingItem(name: line.name, dimension: dimension)
                        if existing != nil {
                            HStack(spacing: 2) {
                                Image(systemName: "plus.circle")
                                    .font(.caption)
                                Text("Merge with \(existing!.name)")
                                    .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
                            }
                        }
                    }
                }
            }
            .frame(minHeight: CozyMetrics.minimumTouchTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(CozyColor.cream)
    }

    private func findExistingItem(name: String, dimension: GroceryMerge.Dimension) -> GroceryItem? {
        guard let list = GroceryService.activeList(in: modelContext) else { return nil }

        let normalizedName = GroceryMerge.normalizedName(name)
        return list.items.first { item in
            !item.isChecked &&
            GroceryMerge.normalizedName(item.name) == normalizedName &&
            GroceryMerge.dimension(of: item.unit) == dimension
        }
    }

    private func toggleSelection(for line: GroceryLineItem) {
        let id = line.id
        if selectedItems.contains(id) {
            selectedItems.remove(id)
        } else {
            selectedItems.insert(id)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: CozySpacing.m) {
            Button {
                selectAll()
            } label: {
                Text("Select all")
                    .font(CozyFont.caption)
            }

            Spacer()

            Text("\(selectedItemLines.count) selected")
                .font(CozyFont.caption)
                .foregroundStyle(CozyColor.inkSecondary)
        }
        .padding(.horizontal, CozySpacing.l)
        .padding(.vertical, CozySpacing.m)
        .background(.ultraThinMaterial)
    }

    private func selectAll() {
        selectedItems = Set(lines.map { $0.id })
    }

    private func addSelectedItems() {
        guard !selectedItemLines.isEmpty else { return }

        let list = GroceryService.activeList(in: modelContext)
        let outcome = GroceryService.add(selectedItemLines, to: list, in: modelContext)

        Haptics.notify(.success)
        dismiss()
    }
}

// MARK: - Previews

#Preview("Add review") {
    NavigationStack { GroceryAddReviewView(lines: PreviewLines.lines, sourceTitle: "Test Recipe") }
}

private enum PreviewLines {
    static var lines: [GroceryLineItem] {
        [
            GroceryLineItem(name: "Flour", quantity: 2, unit: "cups", category: .bakery),
            GroceryLineItem(name: "Sugar", quantity: 1, unit: "cup", category: .bakery),
            GroceryLineItem(name: "Eggs", quantity: 3, unit: "large", category: .dairy),
            GroceryLineItem(name: "Butter", quantity: 100, unit: "g", category: .dairy),
            GroceryLineItem(name: "Vanilla extract", quantity: 1, unit: "tsp", category: .baking),
        ]
    }
}
