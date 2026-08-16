//
//  ShoppingRounder.swift
//  Cozy Crumb
//
//  A recipe asks for 375 g of flour. A shop sells it in 500 g bags, and you
//  can't buy 1.4 onions. This turns a merged amount into something you can
//  actually put in a basket.
//
//  Rounding is always *up* — coming home short is worse than a little left
//  over — and only ever happens at the point of display or export. The stored
//  quantity stays exact, so merging two recipes never compounds a rounding
//  error into a third one.
//

import Foundation

nonisolated struct ShoppingAmount: Sendable, Equatable {
    var quantity: Double?
    var unit: String?
    /// True when this differs from what the recipes actually asked for, so
    /// the UI can show the exact need alongside it.
    var wasRounded: Bool

    nonisolated init(quantity: Double?, unit: String?, wasRounded: Bool = false) {
        self.quantity = quantity
        self.unit = unit
        self.wasRounded = wasRounded
    }
}

enum ShoppingRounder {

    /// Things sold as whole objects. Half a clove is not a purchase.
    private nonisolated static let countUnits: Set<String> = [
        "clove", "piece", "pinch", "can", "bunch", "slice"
    ]

    /// Units that measure out of a container you buy whole. Rounding "1.4
    /// tbsp of vanilla" up to 2 tbsp tells the user nothing about what to
    /// buy, so these are left exactly as they are.
    private nonisolated static let measuringUnits: Set<String> = ["tsp", "tbsp"]

    /// Rounds one merged amount to something buyable.
    nonisolated static func round(quantity: Double?, unit: String?) -> ShoppingAmount {
        guard let quantity, quantity > 0 else {
            return ShoppingAmount(quantity: quantity, unit: unit)
        }

        let normalized = unit?.lowercased().trimmingCharacters(in: .whitespaces)

        guard let normalized, !normalized.isEmpty else {
            return result(ceilToWhole(quantity), normalized, from: quantity)
        }

        if measuringUnits.contains(normalized) {
            return ShoppingAmount(quantity: quantity, unit: unit)
        }

        if countUnits.contains(normalized) {
            return result(ceilToWhole(quantity), normalized, from: quantity)
        }

        return switch normalized {
        case "g": metricMass(grams: quantity, from: quantity, unit: normalized)
        case "kg": metricMass(grams: quantity * 1000, from: quantity, unit: normalized)
        case "ml": metricVolume(millilitres: quantity, from: quantity, unit: normalized)
        case "l": metricVolume(millilitres: quantity * 1000, from: quantity, unit: normalized)
        case "oz": result(ceil(quantity), normalized, from: quantity)
        case "lb": result(ceilToStep(quantity, step: 0.25), normalized, from: quantity)
        case "cup": result(ceilToStep(quantity, step: 0.25), normalized, from: quantity)
        default: ShoppingAmount(quantity: quantity, unit: unit)
        }
    }

    nonisolated static func round(_ line: GroceryLineItem) -> ShoppingAmount {
        round(quantity: line.quantity, unit: line.unit)
    }

    /// Applies the rounding to a whole list, for export.
    nonisolated static func rounded(_ lines: [GroceryLineItem]) -> [GroceryLineItem] {
        lines.map { line in
            var copy = line
            let amount = round(line)
            copy.quantity = amount.quantity
            copy.unit = amount.unit
            return copy
        }
    }

    // MARK: - Ladders

    /// The sizes things actually come in. Below a kilo this is a ladder of
    /// real pack sizes rather than a fixed step, so 375 g lands on a 400 g
    /// pack instead of a 380 g one that doesn't exist. Above a kilo the
    /// ladder gives way to quarter-kilo steps — 1,050 g of potatoes is a
    /// worse answer than 1.25 kg.
    private nonisolated static let packSizes: [Double] = [
        10, 25, 50, 75, 100, 125, 150, 200, 250, 300, 400, 500, 600, 750, 1000
    ]

    private nonisolated static func ceilToPackSize(_ amount: Double) -> Double {
        if let size = packSizes.first(where: { $0 >= amount - tolerance }) {
            return size
        }
        return ceilToStep(amount, step: 250)
    }

    private nonisolated static func metricMass(
        grams: Double,
        from original: Double,
        unit: String
    ) -> ShoppingAmount {
        let roundedGrams = ceilToPackSize(grams)

        // Above a kilo, kilos read better — and the 250 g ladder means the
        // result is always a clean quarter.
        if roundedGrams >= 1000 {
            return result(roundedGrams / 1000, "kg", from: original, comparingTo: unit == "kg")
        }
        return result(roundedGrams, "g", from: original, comparingTo: unit == "g")
    }

    private nonisolated static func metricVolume(
        millilitres: Double,
        from original: Double,
        unit: String
    ) -> ShoppingAmount {
        let roundedMillilitres = ceilToPackSize(millilitres)

        if roundedMillilitres >= 1000 {
            return result(roundedMillilitres / 1000, "l", from: original, comparingTo: unit == "l")
        }
        return result(roundedMillilitres, "ml", from: original, comparingTo: unit == "ml")
    }

    // MARK: - Arithmetic

    private nonisolated static func ceilToWhole(_ value: Double) -> Double {
        ceil(value - tolerance)
    }

    private nonisolated static func ceilToStep(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return (ceil((value - tolerance) / step) * step)
    }

    /// Floating-point slack, so 500.0000001 g doesn't round up to 550 g.
    private nonisolated static let tolerance = 0.000_001

    private nonisolated static func result(
        _ quantity: Double,
        _ unit: String?,
        from original: Double,
        comparingTo sameUnit: Bool = true
    ) -> ShoppingAmount {
        let changed = !sameUnit || abs(quantity - original) > tolerance
        return ShoppingAmount(quantity: quantity, unit: unit, wasRounded: changed)
    }
}
