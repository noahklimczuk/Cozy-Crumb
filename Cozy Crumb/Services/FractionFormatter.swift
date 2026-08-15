//
//  FractionFormatter.swift
//  Cozy Crumb
//
//  Turns a Double into something a person would actually write on a recipe
//  card: 1½, not 1.5. ⅓, not 0.3333333.
//
//  Pure and nonisolated so model code and tests can call it freely.
//

import Foundation

enum FractionFormatter {

    /// Fractions common enough in cooking to be worth a glyph. Ordered by
    /// value so the nearest-match search reads naturally.
    private nonisolated static let fractions: [(value: Double, glyph: String)] = [
        (1.0 / 8.0, "⅛"),
        (1.0 / 4.0, "¼"),
        (1.0 / 3.0, "⅓"),
        (3.0 / 8.0, "⅜"),
        (1.0 / 2.0, "½"),
        (5.0 / 8.0, "⅝"),
        (2.0 / 3.0, "⅔"),
        (3.0 / 4.0, "¾"),
        (7.0 / 8.0, "⅞")
    ]

    /// How close to a whole number counts as that whole number.
    private nonisolated static let wholeTolerance = 0.02

    /// How close to a listed fraction counts as that fraction.
    private nonisolated static let fractionTolerance = 0.04

    /// Above this, fractions stop helping — nobody writes 212½ g.
    private nonisolated static let fractionCeiling = 10.0

    /// Formats a quantity for display.
    ///
    /// - 0.5 → "½", 1.5 → "1½", 0.333 → "⅓", 150 → "150"
    /// - Values with no clean fraction fall back to a trimmed decimal.
    nonisolated static func string(for value: Double) -> String {
        guard value.isFinite else { return "" }
        guard value > 0 else { return "0" }

        // Large quantities read better as plain numbers.
        if value >= fractionCeiling {
            return String(Int(value.rounded()))
        }

        let whole = Int(value)
        let remainder = value - Double(whole)

        // Effectively a whole number already.
        if remainder <= wholeTolerance {
            return String(whole)
        }
        if remainder >= 1 - wholeTolerance {
            return String(whole + 1)
        }

        let nearest = fractions.min { lhs, rhs in
            abs(lhs.value - remainder) < abs(rhs.value - remainder)
        }

        if let nearest, abs(nearest.value - remainder) <= fractionTolerance {
            return whole == 0 ? nearest.glyph : "\(whole)\(nearest.glyph)"
        }

        return trimmedDecimal(value)
    }

    /// "1½ cup", "150 g", "2 cloves", or just the name when there's no amount.
    nonisolated static func quantityString(quantity: Double?, unit: String?) -> String {
        guard let quantity else {
            return unit ?? ""
        }

        let amount = string(for: quantity)

        guard let unit, !unit.isEmpty else {
            return amount
        }

        return "\(amount) \(pluralised(unit, for: quantity))"
    }

    /// Only the count-style units read wrong in the singular. "2 gs" would be
    /// worse than leaving it alone, so mass and volume units never pluralise.
    nonisolated static func pluralised(_ unit: String, for quantity: Double) -> String {
        let countable: Set<String> = ["clove", "piece", "pinch", "can", "bunch"]

        guard countable.contains(unit), quantity > 1 else {
            return unit
        }

        return unit + "s"
    }

    /// Up to two decimal places, with trailing zeros removed.
    private nonisolated static func trimmedDecimal(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100

        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }

        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") {
            text.removeLast()
        }
        return text
    }
}
