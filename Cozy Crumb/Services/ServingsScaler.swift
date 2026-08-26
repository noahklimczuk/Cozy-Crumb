//
//  ServingsScaler.swift
//  Cozy Crumb
//
//  Scales an ingredient's quantity when the servings stepper moves, and is
//  honest when the result is silly. Half an egg is not a thing, and the app
//  should say so rather than printing "1½ eggs" with a straight face.
//

import Foundation

enum ServingsScaler {

    struct Scaled: Equatable, Sendable {
        /// nil for "salt to taste" — lines with no number never scale.
        let quantity: Double?
        let unit: String?
        /// True when the result is a fraction of something you can't halve.
        let isAwkward: Bool

        /// Explicitly nonisolated: the target defaults actor isolation to
        /// MainActor, which would isolate the implicit memberwise init and
        /// make it uncallable from the nonisolated functions below.
        nonisolated init(quantity: Double?, unit: String?, isAwkward: Bool) {
            self.quantity = quantity
            self.unit = unit
            self.isAwkward = isAwkward
        }

        /// Gentle nudge shown beside an awkward amount, or nil.
        nonisolated var awkwardNote: String? {
            guard isAwkward, let quantity else { return nil }
            let rounded = Int(quantity.rounded(.up))
            return "that's \(FractionFormatter.string(for: quantity)) — maybe round up to \(rounded)?"
        }
    }

    /// Units you can't sensibly have a fraction of.
    private nonisolated static let discreteUnits: Set<String> = [
        "clove", "piece", "can", "bunch"
    ]

    /// How close to a whole number still counts as whole.
    private nonisolated static let wholeTolerance = 0.05

    nonisolated static func factor(from original: Int, to target: Int) -> Double {
        guard original > 0, target > 0 else { return 1 }
        return Double(target) / Double(original)
    }

    /// Scales one ingredient, then converts into the chosen system.
    ///
    /// Order matters: scale first, convert second. Converting first would
    /// compound rounding error across the multiply.
    ///
    /// `ingredient` is the ingredient's name, and it is not decoration: going
    /// metric answers volumes in grams where it can, and a cup only has a
    /// weight once you know what is in it. Without the name, "1 cup flour"
    /// converts to 237 ml instead of 125 g.
    nonisolated static func scale(
        quantity: Double?,
        unit: String?,
        ingredient: String? = nil,
        from original: Int,
        to target: Int,
        system: MeasurementSystem = .asWritten
    ) -> Scaled {
        guard let quantity else {
            return Scaled(quantity: nil, unit: unit, isAwkward: false)
        }

        let scaled = quantity * factor(from: original, to: target)

        if let converted = UnitConverter.convert(
            quantity: scaled,
            unit: unit,
            ingredient: ingredient,
            to: system
        ) {
            // A converted amount is already approximate — flagging it as
            // awkward would be noise.
            return Scaled(quantity: converted.quantity, unit: converted.unit, isAwkward: false)
        }

        return Scaled(
            quantity: scaled,
            unit: unit,
            isAwkward: isAwkward(quantity: scaled, unit: unit)
        )
    }

    /// Convenience for scaling a stored ingredient.
    nonisolated static func scale(
        _ ingredient: Ingredient,
        from original: Int,
        to target: Int,
        system: MeasurementSystem = .asWritten
    ) -> Scaled {
        scale(
            quantity: ingredient.quantity,
            unit: ingredient.unit,
            ingredient: ingredient.name,
            from: original,
            to: target,
            system: system
        )
    }

    /// A fractional amount of a countable thing.
    nonisolated static func isAwkward(quantity: Double, unit: String?) -> Bool {
        guard let unit = unit?.lowercased(), discreteUnits.contains(unit) else {
            return false
        }

        let distanceFromWhole = abs(quantity - quantity.rounded())
        return distanceFromWhole > wholeTolerance
    }
}
