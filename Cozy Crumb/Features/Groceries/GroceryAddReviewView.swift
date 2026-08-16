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

/// A wrapper for GroceryLineItem to provide an identifiable ID for the review list
private struct GroceryLineEntry: Identifiable {
    let id: UUID
    let line: GroceryLineItem
    
    init(line: GroceryLineItem) {
        self.id = UUID()
        self.line = line
    }
}

struct GroceryAddReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accentPalette) private var accent
    @Environment(\.cozyMotion) private var motion
    @Environment(\.dismiss) private var dismiss

    let lines: [GroceryLineItem]
    let sourceTitle: String

    @State private var selectedEntries: Set<UUID> = []
    
    private let entries: [GroceryLineEntry]

    init(lines: [GroceryLineItem], sourceTitle: String) {
        self.lines = lines
        self.sourceTitle = sourceTitle
        self.entries = lines.map(GroceryLineEntry.init)
    }

    private var selectedItemLines: [GroceryLineItem] {
        entries.filter { selectedEntries.contains($0.id) }.map { $0.line }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(entries) { entry in
                        listRow(for: entry)
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

    private func listRow(for entry: GroceryLineEntry) -> some View {
        Button {
            toggleSelection(for: entry)
        } label: {
            HStack(spacing: CozySpacing.m) {
                Image(systemName: selectedEntries.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selectedEntries.contains(entry.id) ? accent.color : CozyColor.inkSecondary)
                    .contentTransition(.symbolEffect(.replace))

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.line.name)
                        .cozyText(CozyFont.body)

                    if let quantity = entry.line.quantity, let unit = entry.line.unit {
                        Text(FractionFormatter.quantityString(quantity: quantity, unit: unit))
                            .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
                    }
                }

                Spacer()

                if entry.line.quantity != nil,
                   let unit = entry.line.unit,
                   let dimension = GroceryMerge.dimension(of: unit),
                   let existing = findExistingItem(name: entry.line.name, dimension: dimension) {
                    HStack(spacing: 2) {
                        Image(systemName: "plus.circle")
                            .font(.caption)
                        Text("Merge with \(existing.name)")
                            .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
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
        let list = GroceryService.activeList(in: modelContext)

        let normalizedName = GroceryMerge.normalizedName(name)
        return list.items.first { item in
            !item.isChecked &&
            GroceryMerge.normalizedName(item.name) == normalizedName &&
            GroceryMerge.dimension(of: item.unit) == dimension
        }
    }

    private func toggleSelection(for entry: GroceryLineEntry) {
        let id = entry.id
        if selectedEntries.contains(id) {
            selectedEntries.remove(id)
        } else {
            selectedEntries.insert(id)
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
        selectedEntries = Set(entries.map { $0.id })
    }

    private func addSelectedItems() {
        guard !selectedItemLines.isEmpty else { return }

        let list = GroceryService.activeList(in: modelContext)
        _ = GroceryService.add(selectedItemLines, to: list, in: modelContext)

        Haptics.notify(.success)
        dismiss()
    }
}

// MARK: - Previews

#Preview("Add review") {
    NavigationStack {
        GroceryAddReviewView(lines: PreviewLines.lines, sourceTitle: "Test Recipe")
            .modelContainer(PreviewData.container)
    }
}

private enum PreviewLines {
    static var lines: [GroceryLineItem] {
        [
            GroceryLineItem(name: "Flour", quantity: 2, unit: "cups", category: .bakery),
            GroceryLineItem(name: "Sugar", quantity: 1, unit: "cup", category: .bakery),
            GroceryLineItem(name: "Eggs", quantity: 3, unit: "large", category: .dairy),
            GroceryLineItem(name: "Butter", quantity: 100, unit: "g", category: .dairy),
            GroceryLineItem(name: "Vanilla extract", quantity: 1, unit: "tsp", category: .bakery),
        ]
    }
}
