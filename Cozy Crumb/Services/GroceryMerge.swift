//
//  GroceryMerge.swift
//  Cozy Crumb
//
//  The smart merge (§5.5): adding "2 cloves garlic" when "3 cloves garlic" is
//  already on the list produces "5 cloves garlic", not a second row.
//
//  All of this is deliberately pure — plain values in, plain values out, no
//  SwiftData — so it can be unit tested without a store. `GroceryService` is
//  the thin layer that applies these results to the model objects.
//
//  Every member is `nonisolated`: the target defaults actor isolation to
//  MainActor and this is arithmetic on strings and doubles, none of which
//  belongs on the UI thread.
//

import Foundation

// MARK: - Value

/// One line destined for the grocery list, before it meets the store.
nonisolated struct GroceryLineItem: Sendable, Equatable {
    var name: String
    var quantity: Double?
    var unit: String?
    var category: GroceryCategory
    var sourceRecipeTitles: [String]

    nonisolated init(
        name: String,
        quantity: Double? = nil,
        unit: String? = nil,
        category: GroceryCategory = .other,
        sourceRecipeTitles: [String] = []
    ) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.sourceRecipeTitles = sourceRecipeTitles
    }
}

// MARK: - Merge

enum GroceryMerge {

    /// Which physical quantity a unit measures. Units without one — "clove",
    /// "piece", or no unit at all — only ever merge with themselves.
    nonisolated enum Dimension: Sendable, Equatable {
        case mass
        case volume
    }

    /// unit → (dimension, how many base units one of it is worth).
    /// Base units are grams and millilitres.
    private nonisolated static let unitTable: [String: (dimension: Dimension, factor: Double)] = [
        "g": (.mass, 1),
        "kg": (.mass, 1000),
        "oz": (.mass, 28.349523125),
        "lb": (.mass, 453.59237),

        "ml": (.volume, 1),
        "l": (.volume, 1000),
        "tsp": (.volume, 4.92892159),
        "tbsp": (.volume, 14.78676478),
        "cup": (.volume, 236.5882365),
        "fl oz": (.volume, 29.5735295625)
    ]

    // MARK: Normalisation

    /// Words that end in "s" but aren't plurals. Stripping the "s" would turn
    /// "asparagus" into "asparagu", which is harmless for matching but reads
    /// badly if it ever leaks into a display string.
    private nonisolated static let singularEndings = ["us", "ss", "is"]

    private nonisolated static let leadingArticles = ["a ", "an ", "the "]

    /// The key two lines must agree on to be the same shopping item.
    ///
    /// Consistency matters more than linguistic accuracy here: two spellings
    /// of the same food need the same key, and it's fine if that key isn't a
    /// real word.
    nonisolated static func normalizedName(_ raw: String) -> String {
        var name = raw
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        name = name.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?()"))

        for article in leadingArticles where name.hasPrefix(article) {
            name.removeFirst(article.count)
            break
        }

        // Only the head noun gets singularised — "sweet potatoes" should match
        // "sweet potato", but "sweets" in the middle of a name is left alone.
        guard let lastSpace = name.lastIndex(of: " ") else {
            return singularised(name)
        }

        let head = String(name[name.index(after: lastSpace)...])
        return String(name[..<lastSpace]) + " " + singularised(head)
    }

    private nonisolated static func singularised(_ word: String) -> String {
        guard word.count > 3 else { return word }

        for ending in singularEndings where word.hasSuffix(ending) {
            return word
        }

        if word.hasSuffix("ies") {
            return String(word.dropLast(3)) + "y"
        }
        if word.hasSuffix("es") {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("s") {
            return String(word.dropLast())
        }
        return word
    }

    nonisolated static func normalizedUnit(_ raw: String?) -> String? {
        guard let trimmed = raw?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    nonisolated static func dimension(of unit: String?) -> Dimension? {
        guard let unit = normalizedUnit(unit) else { return nil }
        return unitTable[unit]?.dimension
    }

    // MARK: Compatibility

    /// Two lines merge when they name the same thing *and* carry units that
    /// can be added together. "200 g butter" and "1 cup butter" stay apart —
    /// mass and volume aren't interchangeable without knowing the density,
    /// and guessing would put a wrong number on a shopping list.
    nonisolated static func canMerge(_ a: GroceryLineItem, _ b: GroceryLineItem) -> Bool {
        guard normalizedName(a.name) == normalizedName(b.name) else { return false }
        return unitsAreCompatible(a.unit, b.unit)
    }

    nonisolated static func unitsAreCompatible(_ a: String?, _ b: String?) -> Bool {
        let left = normalizedUnit(a)
        let right = normalizedUnit(b)

        // Covers both-nil and both-the-same-count-unit ("clove" + "clove").
        if left == right { return true }

        guard let leftDimension = dimension(of: left),
              let rightDimension = dimension(of: right) else { return false }

        return leftDimension == rightDimension
    }

    // MARK: Merging

    /// Folds `incoming` into `existing`, keeping the unit the list already
    /// shows so a row doesn't change shape under the user mid-shop.
    nonisolated static func merging(_ existing: GroceryLineItem, with incoming: GroceryLineItem) -> GroceryLineItem {
        var merged = existing

        // An amount-less line ("salt, to taste") adds nothing we can count,
        // but it must not wipe out an amount the list already has either.
        merged.quantity = mergedQuantity(existing: existing, incoming: incoming)

        if let promoted = promoted(quantity: merged.quantity, unit: merged.unit) {
            merged.quantity = promoted.quantity
            merged.unit = promoted.unit
        }

        // A parsed category beats the fallback, whichever side it came from.
        if merged.category == .other {
            merged.category = incoming.category
        }

        for title in incoming.sourceRecipeTitles where !merged.sourceRecipeTitles.contains(title) {
            merged.sourceRecipeTitles.append(title)
        }

        return merged
    }

    private nonisolated static func mergedQuantity(
        existing: GroceryLineItem,
        incoming: GroceryLineItem
    ) -> Double? {
        switch (existing.quantity, incoming.quantity) {
        case (nil, nil):
            return nil
        case (let have?, nil):
            return have
        case (nil, let added?):
            return converted(quantity: added, from: incoming.unit, to: existing.unit)
        case (let have?, let added?):
            return have + converted(quantity: added, from: incoming.unit, to: existing.unit)
        }
    }

    /// Expresses `quantity` in `target`. Units that share no dimension are
    /// never passed here — `canMerge` has already ruled them out — so an
    /// unconvertible pair means the units are identical and the number stands.
    nonisolated static func converted(quantity: Double, from source: String?, to target: String?) -> Double {
        guard let source = normalizedUnit(source),
              let target = normalizedUnit(target),
              source != target,
              let from = unitTable[source],
              let to = unitTable[target],
              from.dimension == to.dimension else {
            return quantity
        }

        return quantity * from.factor / to.factor
    }

    /// 1500 g is a worse thing to read on a list than 1.5 kg.
    private nonisolated static func promoted(quantity: Double?, unit: String?) -> (quantity: Double, unit: String)? {
        guard let quantity, quantity >= 1000, let unit = normalizedUnit(unit) else { return nil }

        return switch unit {
        case "g": (quantity / 1000, "kg")
        case "ml": (quantity / 1000, "l")
        default: nil
        }
    }

    // MARK: Batch

    /// Collapses a batch of lines against each other, preserving the order
    /// they first appeared in.
    nonisolated static func folded(_ items: [GroceryLineItem]) -> [GroceryLineItem] {
        var result: [GroceryLineItem] = []

        for item in items {
            if let index = result.firstIndex(where: { canMerge($0, item) }) {
                result[index] = merging(result[index], with: item)
            } else {
                result.append(item)
            }
        }

        return result
    }
}
