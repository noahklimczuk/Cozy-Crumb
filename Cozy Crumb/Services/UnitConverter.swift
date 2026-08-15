//
//  UnitConverter.swift
//  Cozy Crumb
//
//  Metric ⟷ imperial, but only where converting actually helps. "1 onion"
//  stays "1 onion" — the point is a usable recipe, not unit purity.
//

import Foundation

enum MeasurementSystem: String, CaseIterable, Codable, Sendable {
    /// Leave every quantity exactly as the source wrote it.
    case asWritten
    case metric
    case imperial

    nonisolated var displayName: String {
        switch self {
        case .asWritten: "As written"
        case .metric: "Metric"
        case .imperial: "Imperial"
        }
    }
}

enum UnitConverter {

    /// A quantity after conversion. `unit` may differ from the input — 500 g
    /// becomes 1.1 lb, 300 ml becomes 1¼ cup.
    struct Converted: Equatable, Sendable {
        let quantity: Double
        let unit: String

        /// Explicitly nonisolated: the target defaults actor isolation to
        /// MainActor, which would isolate the implicit memberwise init and
        /// make it uncallable from the nonisolated functions below.
        nonisolated init(quantity: Double, unit: String) {
            self.quantity = quantity
            self.unit = unit
        }
    }

    // Mass
    private nonisolated static let gramsPerOunce = 28.349523125
    private nonisolated static let gramsPerPound = 453.59237

    // Volume
    private nonisolated static let millilitresPerCup = 236.5882365
    private nonisolated static let millilitresPerTablespoon = 14.78676478
    private nonisolated static let millilitresPerTeaspoon = 4.92892159
    private nonisolated static let millilitresPerFluidOunce = 29.5735295625

    /// Units that describe a count or a vague amount. Converting these is
    /// meaningless, so they're always passed through untouched.
    private nonisolated static let nonConvertible: Set<String> = [
        "clove", "piece", "pinch", "can", "bunch"
    ]

    /// Converts a quantity into the requested system.
    ///
    /// Returns nil when no conversion applies — the unit is already in the
    /// target system, is a count, or isn't recognised. A nil result means
    /// "show the original", not "something went wrong".
    nonisolated static func convert(
        quantity: Double,
        unit: String?,
        to system: MeasurementSystem
    ) -> Converted? {
        guard system != .asWritten else { return nil }
        guard let unit = unit?.lowercased(), !unit.isEmpty else { return nil }
        guard !nonConvertible.contains(unit) else { return nil }

        return switch system {
        case .metric: toMetric(quantity: quantity, unit: unit)
        case .imperial: toImperial(quantity: quantity, unit: unit)
        case .asWritten: nil
        }
    }

    // MARK: - Metric

    private nonisolated static func toMetric(quantity: Double, unit: String) -> Converted? {
        switch unit {
        case "oz":
            let grams = quantity * gramsPerOunce
            return grams >= 1000
                ? Converted(quantity: grams / 1000, unit: "kg")
                : Converted(quantity: grams, unit: "g")

        case "lb":
            let grams = quantity * gramsPerPound
            return grams >= 1000
                ? Converted(quantity: grams / 1000, unit: "kg")
                : Converted(quantity: grams, unit: "g")

        case "cup":
            return millilitresOrLitres(quantity * millilitresPerCup)

        case "fl oz":
            return millilitresOrLitres(quantity * millilitresPerFluidOunce)

        // tsp and tbsp are used in metric kitchens too. Converting 1 tsp to
        // 4.9 ml helps nobody.
        default:
            return nil
        }
    }

    private nonisolated static func millilitresOrLitres(_ millilitres: Double) -> Converted {
        millilitres >= 1000
            ? Converted(quantity: millilitres / 1000, unit: "l")
            : Converted(quantity: millilitres, unit: "ml")
    }

    // MARK: - Imperial

    private nonisolated static func toImperial(quantity: Double, unit: String) -> Converted? {
        switch unit {
        case "g":
            return ouncesOrPounds(grams: quantity)

        case "kg":
            return ouncesOrPounds(grams: quantity * 1000)

        case "ml":
            return cupsOrSpoons(millilitres: quantity)

        case "l":
            return cupsOrSpoons(millilitres: quantity * 1000)

        default:
            return nil
        }
    }

    private nonisolated static func ouncesOrPounds(grams: Double) -> Converted {
        grams >= gramsPerPound
            ? Converted(quantity: grams / gramsPerPound, unit: "lb")
            : Converted(quantity: grams / gramsPerOunce, unit: "oz")
    }

    /// Small volumes read better as spoons than as fractions of a cup.
    private nonisolated static func cupsOrSpoons(millilitres: Double) -> Converted {
        if millilitres >= millilitresPerCup / 4 {
            return Converted(quantity: millilitres / millilitresPerCup, unit: "cup")
        }
        if millilitres >= millilitresPerTablespoon {
            return Converted(quantity: millilitres / millilitresPerTablespoon, unit: "tbsp")
        }
        return Converted(quantity: millilitres / millilitresPerTeaspoon, unit: "tsp")
    }
}
