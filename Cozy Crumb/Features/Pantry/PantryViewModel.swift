//
//  PantryViewModel.swift
//  Cozy Crumb
//
//  What's in, and what's about to go off (§5.8).
//
//  The pantry earns its place by being the thing the Sous Chef reads and the
//  thing that stops you buying a third jar of tahini, so the two states it has
//  to get right are: adding something takes one line of typing, and anything
//  about to expire is impossible to miss.
//

import Foundation
import SwiftData
import SwiftUI
import os

@Observable
@MainActor
final class PantryViewModel {

    /// How a section of the pantry is presented. Expiry beats aisle: a
    /// yoghurt going off tomorrow matters more than which shelf it lives on.
    nonisolated enum Section: Identifiable, Sendable, Equatable {
        case expiring
        case category(GroceryCategory)

        nonisolated var id: String {
            switch self {
            case .expiring: "expiring"
            case .category(let category): category.rawValue
            }
        }

        nonisolated var title: String {
            switch self {
            case .expiring: "Use me soon"
            case .category(let category): category.displayName
            }
        }

        nonisolated var symbol: String {
            switch self {
            case .expiring: "clock.badge.exclamationmark"
            case .category(let category): category.symbol
            }
        }
    }

    /// Not `Sendable`: it holds `PantryItem`s, which are SwiftData models tied
    /// to the context that fetched them. Grouping is pure and stays on one
    /// side of the boundary, so nothing here needs to cross.
    nonisolated struct Group: Identifiable {
        var section: Section
        var items: [PantryItem]

        nonisolated var id: String { section.id }
    }

    var draft = ""
    var isPickingPhotos = false
    var isReadingPhotos = false
    var spotted: [SpottedPantryItem] = []
    var failure: CozyError?

    private let reader: FridgePhotoReader
    private let keychain: KeychainStore

    init(reader: FridgePhotoReader = FridgePhotoReader(), keychain: KeychainStore = .shared) {
        self.reader = reader
        self.keychain = keychain
    }

    var canReadPhotos: Bool {
        keychain.hasValue(for: .geminiAPIKey)
    }

    // MARK: - Grouping

    /// Expiring first, then aisles in supermarket-walk order. An expiring item
    /// appears only in the expiring section — showing it twice would make the
    /// pantry look like it has more in it than it does.
    nonisolated func groups(from items: [PantryItem], now: Date = .now) -> [Group] {
        let expiring = items
            .filter { $0.isExpiringSoon(now: now) }
            .sorted { ($0.daysUntilExpiry(now: now) ?? .max) < ($1.daysUntilExpiry(now: now) ?? .max) }

        let expiringIDs = Set(expiring.map(\.id))

        let rest = items.filter { !expiringIDs.contains($0.id) }

        let byCategory = Dictionary(grouping: rest, by: \.category)
            .map { Group(section: .category($0.key), items: $0.value.sorted { $0.name < $1.name }) }
            .sorted { left, right in
                guard case .category(let a) = left.section, case .category(let b) = right.section else {
                    return false
                }
                return a.sortOrder < b.sortOrder
            }

        guard !expiring.isEmpty else { return byCategory }

        return [Group(section: .expiring, items: expiring)] + byCategory
    }

    // MARK: - Adding by hand

    /// Typed lines go through the recipe importer's parser, so "2 cartons of
    /// oat milk" arrives with its amount and aisle already worked out.
    func addTyped(in context: ModelContext) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let parsed = IngredientLineParser.parse(text, order: 0)
        let name = parsed.name.isEmpty ? text : parsed.name

        draft = ""
        Haptics.soft()

        add(
            name: name,
            quantity: parsed.quantity,
            unit: parsed.unit,
            category: parsed.groceryCategory,
            source: .manual,
            in: context
        )
    }

    /// Merges by name rather than stacking a second row for the same thing —
    /// the point of a pantry is knowing whether you have any, not how many
    /// times you've told the app about it.
    func add(
        name: String,
        quantity: Double?,
        unit: String?,
        category: GroceryCategory,
        source: PantryItemSource,
        in context: ModelContext
    ) {
        let key = GroceryMerge.normalizedName(name)
        let existing = fetchAll(in: context).first { GroceryMerge.normalizedName($0.name) == key }

        if let existing {
            existing.addedAt = .now
            if existing.quantity == nil {
                existing.quantity = quantity
                existing.unit = unit
            } else if let quantity, existing.unit == unit {
                existing.quantity = (existing.quantity ?? 0) + quantity
            }
        } else {
            context.insert(
                PantryItem(
                    name: name,
                    quantity: quantity,
                    unit: unit,
                    category: category,
                    source: source
                )
            )
        }

        save(context, "pantry addition")
    }

    func remove(_ item: PantryItem, in context: ModelContext) {
        context.delete(item)
        save(context, "pantry removal")
    }

    func setExpiry(_ date: Date?, on item: PantryItem, in context: ModelContext) {
        item.expiresAt = date
        save(context, "pantry expiry")
    }

    /// "I've used that up" — the everyday action, and the one that keeps the
    /// pantry honest enough for the Sous Chef to trust.
    func useUp(_ item: PantryItem, in context: ModelContext) {
        Haptics.notify(.success)
        remove(item, in: context)
    }

    // MARK: - Fridge photos

    func read(photos: [Data]) async {
        guard !photos.isEmpty else { return }

        failure = nil
        isReadingPhotos = true
        defer { isReadingPhotos = false }

        switch await reader.read(photos: photos) {
        case .success(let items):
            guard !items.isEmpty else {
                failure = .noRecipeFound
                return
            }
            spotted = items

        case .failure(let error):
            Log.ai.info("Fridge photo failed: \(String(describing: error), privacy: .public)")
            failure = error
        }
    }

    /// Writes the rows the user kept. Nothing from a photo lands without this.
    func accept(_ items: [SpottedPantryItem], in context: ModelContext) {
        for item in items {
            add(
                name: item.name,
                quantity: item.quantity,
                unit: item.unit,
                category: item.category,
                source: .fridgePhoto,
                in: context
            )
        }

        spotted = []
        Haptics.notify(.success)
    }

    func discardSpotted() {
        spotted = []
    }

    // MARK: - Store

    private func fetchAll(in context: ModelContext) -> [PantryItem] {
        (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
    }

    private func save(_ context: ModelContext, _ what: String) {
        do {
            try context.save()
        } catch {
            Log.data.error("Could not save \(what, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
