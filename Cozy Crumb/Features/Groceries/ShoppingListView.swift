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
    /// Which half of the Groceries tab is showing. Owned by `GroceriesView`;
    /// this screen only draws the switch in its header. Defaults to a constant
    /// so the previews below can stand the screen up on its own.
    var mode: Binding<GroceryTabMode> = .constant(.list)

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
        VStack(spacing: 0) {
            header
            content
        }
        .cozyScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
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

    // MARK: - Header

    private var header: some View {
        ScreenHeader(
            title: "Groceries",
            eyebrow: AppBranding.appName,
            caption: summary,
            trailing: { listMenu },
            below: {
                VStack(spacing: CozySpacing.m) {
                    GroceryModePicker(mode: mode)
                    addField
                }
            }
        )
    }

    /// The live line under the title. Nil rather than "0 to buy" on an empty
    /// list — the empty state already says that, in better words.
    private var summary: String? {
        guard let list, !list.items.isEmpty else { return nil }

        let toBuy = list.outstandingItems.count
        let got = list.completedItems.count

        var parts = ["\(toBuy) to buy"]
        if got > 0 {
            parts.append("\(got) in the basket")
        }
        return parts.joined(separator: " · ")
    }

    /// Everything that used to be two separate toolbar buttons. One glyph in
    /// the header, because the header has room for exactly one and clearing
    /// the list is not something to put a finger's width from the quick-add.
    private var listMenu: some View {
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

            Button(role: .destructive) {
                isConfirmingClearAll = true
            } label: {
                Label("Clear the whole list", systemImage: "trash")
            }
            .disabled(list?.items.isEmpty ?? true)
        } label: {
            HeaderGlyphLabel(systemImage: "ellipsis")
        }
        .accessibilityLabel("List options")
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
                        AisleTag(
                            title: "Got it",
                            systemImage: "checkmark.circle.fill",
                            count: list.completedItems.count,
                            tint: accent.color
                        )
                        .textCase(nil)
                        .listRowInsets(EdgeInsets(
                            top: CozySpacing.xl,
                            leading: CozySpacing.l,
                            bottom: CozySpacing.xs,
                            trailing: CozySpacing.l
                        ))
                    }
                }
            }
            // Plain, with each row carrying its own card: inset-grouped
            // brings iOS's grey chrome with it, which fights the warm
            // background every other screen sits on.
            .listStyle(.plain)
            .listRowSpacing(CozySpacing.xs)
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
        // The full category colour, not a paled one. The tag is a small hard
        // tile now rather than a soft wash behind a word, and at that size a
        // 45%-paled mint is indistinguishable from a 45%-paled sage.
        AisleTag(
            title: category.displayName,
            systemImage: category.symbol,
            count: count,
            tint: category.tint
        )
        .textCase(nil)
        .listRowInsets(EdgeInsets(
            top: CozySpacing.m,
            leading: CozySpacing.l,
            bottom: CozySpacing.xs,
            trailing: CozySpacing.l
        ))
    }

    private func row(for item: GroceryItem) -> some View {
        GroceryRow(
            item: item,
            isStruckThrough: item.isChecked || striking.contains(item.id),
            roundUp: roundUpAmounts
        ) {
            toggle(item)
        }
        // No row background: the CheckRow inside brings its own surface, and a
        // white card behind it would sit in front of the blush a ticked row
        // paints itself.
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(
            top: 2,
            leading: CozySpacing.l,
            bottom: 2,
            trailing: CozySpacing.l
        ))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                // Logged before the delete, while the item still has a name.
                SignalLog.groceryDeleted(item, in: modelContext)

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
                submitLabel: .done,
                // On the slab rather than on the page, so it takes the
                // slab's fill *and* the slab's ink. Solid white here would
                // punch a hole in the header.
                surface: .onAccent
            ) {
                addTypedItem()
            }

            if !newItemText.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: addTypedItem) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(CozyColor.inkOnAccent)
                        .frame(width: 44, height: 44)
                        .background(CozyColor.butter,
                                    in: .rect(cornerRadius: CozyRadius.field, style: .continuous))
                }
                .buttonStyle(.squishy)
                .accessibilityLabel("Add to the list")
                .transition(.scale.combined(with: .opacity))
            }
        }
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
            .background(CozyColor.cream)
        }
    }

    /// Three buttons on blocks rather than three outlined tiles. The prominent
    /// one takes the accent's own block; the other two the generic beige, so
    /// the row reads as one loud and two quiet rather than three of a kind.
    private func exportLabel(_ title: String, systemImage: String, isProminent: Bool) -> some View {
        HStack(spacing: CozySpacing.xs) {
            Image(systemName: systemImage)
                // Paired with the label beside it, so it scales with it.
                .font(.subheadline.weight(.semibold))
            Text(title)
                .font(CozyFont.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(isProminent ? CozyColor.inkOnAccent : CozyColor.inkPrimary)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(
            isProminent ? accent.deep : CozyColor.card,
            in: .rect(cornerRadius: CozyRadius.field, style: .continuous)
        )
        .cozyBlockShadow(CozyDepth.small, color: isProminent ? accent.block : CozyColor.block)
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
                // Clear of the tab bar, from the same number the bar is
                // built from. 96 was a guess at a bar that is 108 tall,
                // so every one of these was appearing behind it.
                .padding(.bottom, CozyMetrics.tabBarTotalHeight + CozySpacing.m)
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

            SignalLog.groceryPurchased(item, in: modelContext)
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

/// A grocery line as a `CheckRow`. What is left here is the shopping-specific
/// part: rounding an exact amount up to something you can actually buy, and
/// saying what the recipes asked for when the two differ.
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

    private var title: String {
        amount.isEmpty ? item.name : "\(amount) \(item.name)"
    }

    var body: some View {
        CheckRow(
            title: title,
            subtitle: caption,
            // The strike leads the tick by a beat — see `toggle(_:)` above —
            // so the row reads from this rather than from `item.isChecked`.
            isChecked: isStruckThrough,
            // No tint, so a ticked row goes the same accent here as it does on
            // a recipe. It used to keep its aisle colour, which was a nice
            // touch when `tint` only coloured a 24pt circle; now that ticking
            // paints the whole row, six different fills down the "Got it"
            // section is a fruit salad, and it would mean "ticked" looked like
            // a different thing on each of the two screens that do it.
            checkedValue: "got it",
            uncheckedValue: "still to buy",
            action: onToggle
        )
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
