//
//  ShoppingListView.swift
//  Cozy Crumb
//
//  The list you actually shop from (§5.5): auto-grouped by category in
//  supermarket-walk order, smart-merged as things arrive, and exportable to
//  Reminders, Notes, or the clipboard.
//
//  Amounts are rounded up to buyable quantities on the way out — see
//  ShoppingRounder. The stored amount stays exact so merging never compounds
//  a rounding error.
//

import Foundation
import SwiftData
import SwiftUI
import os

struct ShoppingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accentPalette) private var accent
    @Environment(\.cozyMotion) private var motion

    @Query(sort: \GroceryList.createdAt) private var lists: [GroceryList]

    @AppStorage(CozyDefaultsKey.checkOffAddsToPantry) private var checkOffAddsToPantry = false
    @AppStorage(CozyDefaultsKey.roundUpShoppingAmounts) private var roundUpAmounts = true

    @State private var newItemText = ""
    /// Items mid-strikethrough: ticked by the user, not yet moved to "Got it".
    @State private var striking: Set<UUID> = []
    @State private var isConfirmingClearCompleted = false
    @State private var isConfirmingClearAll = false
    @State private var isSendingToReminders = false
    @State private var toast: String?
    @State private var exportError: CozyError?

    private var list: GroceryList? { lists.first }

    private var outstandingLines: [GroceryLineItem] {
        guard let list else { return [] }
        return list.itemsByCategory
            .flatMap(\.items)
            .map { GroceryService.lineItem(for: $0) }
    }

    var body: some View {
        content
            .background { BlobBackground() }
            .toolbar { clearMenu }
            .safeAreaInset(edge: .top) { addField }
            .safeAreaInset(edge: .bottom) { exportBar }
            .task { ensureList() }
            .confirmationDialog(
                "Clear the ticked-off items?",
                isPresented: $isConfirmingClearCompleted,
                titleVisibility: .visible
            ) {
                Button("Clear them", role: .destructive) { clearCompleted() }
                Button("Keep them", role: .cancel) {}
            } message: {
                Text("Everything still to buy stays put.")
            }
            .confirmationDialog(
                "Clear the whole list?",
                isPresented: $isConfirmingClearAll,
                titleVisibility: .visible
            ) {
                Button("Clear everything", role: .destructive) { clearAll() }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("Every item goes, ticked off or not.")
            }
            .alert(
                "Couldn't send that over",
                isPresented: .init(
                    get: { exportError != nil },
                    set: { if !$0 { exportError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { exportError = nil }
            } message: {
                Text(exportError?.friendlyMessage ?? "")
            }
            .overlay(alignment: .bottom) { toastBanner }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let list, !list.items.isEmpty {
            List {
                ForEach(list.itemsByCategory) { group in
                    Section {
                        ForEach(group.items) { item in
                            row(for: item)
                        }
                    } header: {
                        categoryHeader(group.category, count: group.items.count)
                    }
                }

                if !list.completedItems.isEmpty {
                    Section {
                        ForEach(list.completedItems) { item in
                            row(for: item)
                        }
                    } header: {
                        Text("Got it")
                            .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
        } else {
            EmptyStateView(
                title: "Nothing on the list yet.",
                message: "Open a recipe and tap \"Add to groceries\" — or type something in above.",
                pose: .idle
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .padding(.horizontal, CozySpacing.s)
        .padding(.vertical, 6)
        .background(category.tint.opacity(0.55), in: .rect(cornerRadius: CozyRadius.chip, style: .continuous))
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: CozySpacing.s, leading: 0, bottom: CozySpacing.xs, trailing: 0))
    }

    private func row(for item: GroceryItem) -> some View {
        GroceryRow(
            item: item,
            isStruckThrough: item.isChecked || striking.contains(item.id),
            roundUp: roundUpAmounts
        ) {
            toggle(item)
        }
        .listRowBackground(CozyColor.cream)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                withAnimation(motion(Motion.gentle)) {
                    GroceryService.delete(item, in: modelContext)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Manual add

    private var addField: some View {
        HStack(spacing: CozySpacing.s) {
            CozyTextField(
                placeholder: "2 cups flour, milk, a lemon…",
                text: $newItemText,
                systemImage: "plus.circle",
                submitLabel: .done
            ) {
                addTypedItem()
            }

            if !newItemText.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: addTypedItem) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(CozyColor.inkPrimary)
                        .frame(width: 38, height: 38)
                        .background(accent.color, in: .circle)
                        .overlay { Circle().strokeBorder(accent.deep, lineWidth: 1.5) }
                }
                .buttonStyle(.squishy)
                .accessibilityLabel("Add to the list")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, CozySpacing.l)
        .padding(.vertical, CozySpacing.m)
        .background(.ultraThinMaterial)
        .cozyAnimation(Motion.snappy, value: newItemText.isEmpty)
    }

    // MARK: - Export

    @ViewBuilder
    private var exportBar: some View {
        if let list, !list.outstandingItems.isEmpty {
            // Export what the screen shows, not the exact arithmetic behind it.
            let items = roundUpAmounts ? ShoppingRounder.rounded(outstandingLines) : outstandingLines

            HStack(spacing: CozySpacing.s) {
                Button {
                    sendToReminders(named: list.name)
                } label: {
                    exportLabel("Reminders", systemImage: "checklist", isProminent: true)
                }
                .buttonStyle(.squishy)
                .disabled(isSendingToReminders)

                ShareLink(item: GroceryExport.checklistText(for: items)) {
                    exportLabel("Notes", systemImage: "square.and.pencil", isProminent: false)
                }
                .buttonStyle(.squishy)

                Button {
                    GroceryExport.copyToClipboard(items)
                    Haptics.notify(.success)
                    show(toast: "Copied \(items.count) item\(items.count == 1 ? "" : "s").")
                } label: {
                    exportLabel("Copy", systemImage: "doc.on.doc", isProminent: false)
                }
                .buttonStyle(.squishy)
            }
            .padding(.horizontal, CozySpacing.l)
            .padding(.vertical, CozySpacing.m)
            .background(.ultraThinMaterial)
        }
    }

    private func exportLabel(_ title: String, systemImage: String, isProminent: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
            Text(title)
                .font(CozyFont.caption2.weight(.semibold))
        }
        .foregroundStyle(CozyColor.inkPrimary)
        .frame(maxWidth: .infinity)
        .frame(height: CozyMetrics.minimumTouchTarget)
        .background(
            isProminent ? accent.color : CozyColor.creamDeep,
            in: .rect(cornerRadius: CozyRadius.chip, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CozyRadius.chip, style: .continuous)
                .strokeBorder(isProminent ? accent.deep : CozyColor.creamDeep, lineWidth: 1.5)
        }
    }

    @ToolbarContentBuilder
    private var clearMenu: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let list, !list.items.isEmpty {
                Button(role: .destructive) {
                    isConfirmingClearAll = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Clear list")
            }

            Menu {
                Toggle("Round up to shop sizes", isOn: $roundUpAmounts)
                Toggle("Ticking adds to Pantry", isOn: $checkOffAddsToPantry)

                Divider()

                Button(role: .destructive) {
                    isConfirmingClearCompleted = true
                } label: {
                    Label("Clear ticked-off", systemImage: "checkmark.circle")
                }
                .disabled(list?.completedItems.isEmpty ?? true)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("List options")
        }
    }

    @ViewBuilder
    private var toastBanner: some View {
        if let toast {
            Text(toast)
                .cozyText(CozyFont.caption, color: CozyColor.inkPrimary)
                .padding(.horizontal, CozySpacing.m)
                .padding(.vertical, CozySpacing.s)
                .background(CozyColor.creamDeep, in: .capsule)
                .cozyLiftShadow()
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    // MARK: - Actions

    private func ensureList() {
        guard lists.isEmpty else { return }
        _ = GroceryService.activeList(in: modelContext)
        GroceryService.save(modelContext, "new grocery list")
    }

    private func addTypedItem() {
        let text = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Typed lines go through the same parser as an imported recipe, so
        // "2 cups flour" arrives with its amount and aisle already worked out.
        let parsed = IngredientLineParser.parse(text, order: 0)
        let line = GroceryLineItem(
            name: parsed.name.isEmpty ? text : parsed.name,
            quantity: parsed.quantity,
            unit: parsed.unit,
            category: parsed.groceryCategory
        )

        let target = list ?? GroceryService.activeList(in: modelContext)

        newItemText = ""
        Haptics.soft()
        withAnimation(motion(Motion.gentle)) {
            _ = GroceryService.add([line], to: target, in: modelContext)
        }
    }

    /// Ticking runs in two beats: the strikethrough draws across the row,
    /// then the row sinks down into "Got it". Doing both at once reads as the
    /// row simply vanishing.
    private func toggle(_ item: GroceryItem) {
        guard !item.isChecked else {
            Haptics.soft()
            withAnimation(motion(Motion.gentle)) {
                item.isChecked = false
            }
            GroceryService.save(modelContext, "untick")
            return
        }

        Haptics.impact(.light)
        withAnimation(motion(Motion.snappy)) {
            _ = striking.insert(item.id)
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))

            withAnimation(motion(Motion.gentle)) {
                item.isChecked = true
                striking.remove(item.id)
            }

            if checkOffAddsToPantry {
                GroceryService.addToPantry(item, in: modelContext)
            } else {
                GroceryService.save(modelContext, "tick")
            }
        }
    }

    private func clearCompleted() {
        withAnimation(motion(Motion.gentle)) {
            guard let list else { return }
            GroceryService.clearCompleted(from: list, in: modelContext)
        }
    }

    private func clearAll() {
        withAnimation(motion(Motion.gentle)) {
            guard let list else { return }
            GroceryService.clearAll(from: list, in: modelContext)
        }
    }

    private func sendToReminders(named listName: String) {
        let items = outstandingLines
        guard !items.isEmpty else { return }

        isSendingToReminders = true

        Task { @MainActor in
            defer { isSendingToReminders = false }

            do {
                let count = try await RemindersExport.send(items, toListNamed: listName)
                Haptics.notify(.success)
                show(toast: "\(count) item\(count == 1 ? "" : "s") sent to Reminders.")
            } catch let error as CozyError {
                exportError = error
            } catch {
                Log.data.error(
                    "Reminders export failed: \(error.localizedDescription, privacy: .public)"
                )
                exportError = .remindersUnavailable
            }
        }
    }

    private func show(toast message: String) {
        withAnimation(motion(Motion.snappy)) { toast = message }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(motion(Motion.gentle)) { toast = nil }
        }
    }
}

// MARK: - Row

private struct GroceryRow: View {
    let item: GroceryItem
    let isStruckThrough: Bool
    let roundUp: Bool
    let onToggle: () -> Void

    private var shopping: ShoppingAmount {
        guard roundUp else {
            return ShoppingAmount(quantity: item.quantity, unit: item.unit)
        }
        return ShoppingRounder.round(quantity: item.quantity, unit: item.unit)
    }

    private var amount: String {
        FractionFormatter.quantityString(quantity: shopping.quantity, unit: shopping.unit)
    }

    /// What the recipes actually asked for, shown only when it differs from
    /// the amount you'd buy — otherwise the number on screen would quietly
    /// stop matching the recipe.
    private var exactNeed: String? {
        guard shopping.wasRounded else { return nil }
        let exact = FractionFormatter.quantityString(quantity: item.quantity, unit: item.unit)
        return exact.isEmpty ? nil : "needs \(exact)"
    }

    private var caption: String? {
        let parts = [item.sourceCaption, exactNeed].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: CozySpacing.s) {
                Image(systemName: isStruckThrough ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isStruckThrough ? item.category.tint : CozyColor.inkSecondary)
                    .contentTransition(.symbolEffect(.replace))

                VStack(alignment: .leading, spacing: 2) {
                    label
                    if let caption {
                        Text(caption)
                            .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .frame(minHeight: CozyMetrics.minimumTouchTarget - CozySpacing.s)
            .contentShape(.rect)
            .opacity(isStruckThrough ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(amount.isEmpty ? item.name : "\(amount) \(item.name)")
        .accessibilityValue(item.isChecked ? "Got it" : "Still to buy")
        .accessibilityHint("Double-tap to tick off")
    }

    /// The strikethrough is drawn rather than toggled so it sweeps across the
    /// text instead of appearing all at once.
    private var label: some View {
        Text(amount.isEmpty ? item.name : "\(amount) \(item.name)")
            .cozyText(CozyFont.body)
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(CozyColor.inkSecondary)
                    .frame(height: 1.5)
                    .scaleEffect(x: isStruckThrough ? 1 : 0, anchor: .leading)
                    .cozyAnimation(Motion.snappy, value: isStruckThrough)
            }
    }
}

// MARK: - Previews

#Preview("Shopping list") {
    NavigationStack { ShoppingListView() }
        .modelContainer(PreviewData.groceriesContainer)
}

#Preview("Shopping list — dark") {
    NavigationStack { ShoppingListView() }
        .modelContainer(PreviewData.groceriesContainer)
        .preferredColorScheme(.dark)
}

#Preview("Shopping list — empty") {
    NavigationStack { ShoppingListView() }
        .modelContainer(PreviewData.emptyContainer)
}
