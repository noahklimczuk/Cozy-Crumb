//
//  UnitConverter.swift
//  Cozy Crumb
//
//  Metric ⟷ imperial, but only where converting actually helps. "1 onion"
//  stays "1 onion" — the point is a usable recipe, not unit purity.
//
//  Metric answers in grams wherever it can, including for volumes: a metric
//  kitchen weighs its dry goods, and "125 g flour" is what a European recipe
//  says where an American one says "1 cup". Turning a volume into a weight
//  needs to know what is in the cup, so the ingredient's name comes in with
//  the quantity and `IngredientDensity` supplies the rest. When the ingredient
//  is not recognised the answer stays in millilitres rather than inventing a
//  weight from an average that is wrong for everything.
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
    private nonisolated static let millilitresPerPint = 473.176473
    private nonisolated static let millilitresPerQuart = 946.352946
    private nonisolated static let millilitresPerGallon = 3785.411784

    /// A US stick of butter. Written on the wrapper, invisible everywhere else.
    private nonisolated static let gramsPerStick = 113.398093

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
        ingredient: String? = nil,
        to system: MeasurementSystem
    ) -> Converted? {
        guard system != .asWritten else { return nil }
        guard let unit = unit?.lowercased(), !unit.isEmpty else { return nil }
        guard !nonConvertible.contains(unit) else { return nil }

        return switch system {
        case .metric: toMetric(quantity: quantity, unit: unit, ingredient: ingredient)
        case .imperial: toImperial(quantity: quantity, unit: unit)
        case .asWritten: nil
        }
    }

    // MARK: - Metric

    private nonisolated static func toMetric(
        quantity: Double,
        unit: String,
        ingredient: String?
    ) -> Converted? {
        // Mass in, grams out. No kilograms: a recipe that says 1.4 kg is
        // harder to weigh than one that says 1400 g, and the scale reads
        // grams either way.
        switch unit {
        case "oz", "ounce", "ounces":
            return Converted(quantity: quantity * gramsPerOunce, unit: "g")
        case "lb", "lbs", "pound", "pounds":
            return Converted(quantity: quantity * gramsPerPound, unit: "g")
        case "stick", "sticks":
            return Converted(quantity: quantity * gramsPerStick, unit: "g")
        default:
            break
        }

        // Volume in. Grams out when the ingredient is known, millilitres when
        // it is not — see the note at the top of the file.
        guard let volume = millilitres(quantity: quantity, unit: unit) else {
            return nil
        }

        if let gramsPerCup = IngredientDensity.gramsPerCup(of: ingredient) {
            let cups = volume / millilitresPerCup
            return Converted(quantity: cups * gramsPerCup, unit: "g")
        }

        // A spoon of something we can't weigh stays a spoon. Metric kitchens
        // own teaspoons; "1 tsp vanilla" is a perfectly metric instruction and
        // "4.93 ml vanilla" helps nobody. The weight is the only reason to
        // touch a spoon at all, so without one there is nothing to say.
        guard !spoons.contains(unit) else { return nil }

        return millilitresOrLitres(volume)
    }

    /// Spoon units, which only convert when there is a weight to convert to.
    private nonisolated static let spoons: Set<String> = [
        "tbsp", "tablespoon", "tablespoons", "tsp", "teaspoon", "teaspoons"
    ]

    /// Every volume unit a recipe might arrive in, in millilitres.
    ///
    /// `tsp` and `tbsp` are in here now. They used to be refused outright on
    /// the grounds that metric kitchens use spoons too — which is true of "1
    /// tsp vanilla" and untrue of "3 tbsp butter", where the whole point of
    /// switching to metric is to get a number for the scale. Whether a spoon
    /// is worth converting is decided above by whether the ingredient has a
    /// known weight, not here by the unit alone.
    private nonisolated static func millilitres(quantity: Double, unit: String) -> Double? {
        switch unit {
        case "cup", "cups": quantity * millilitresPerCup
        case "fl oz", "fluid ounce", "fluid ounces": quantity * millilitresPerFluidOunce
        case "tbsp", "tablespoon", "tablespoons": quantity * millilitresPerTablespoon
        case "tsp", "teaspoon", "teaspoons": quantity * millilitresPerTeaspoon
        case "pint", "pints": quantity * millilitresPerPint
        case "quart", "quarts": quantity * millilitresPerQuart
        case "gallon", "gallons": quantity * millilitresPerGallon
        default: nil
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
        case "g", "gram", "grams":
            return ouncesOrPounds(grams: quantity)

        case "kg", "kilogram", "kilograms":
            return ouncesOrPounds(grams: quantity * 1000)

        case "ml", "millilitre", "millilitres", "milliliter", "milliliters":
            return cupsOrSpoons(millilitres: quantity)

        case "l", "litre", "litres", "liter", "liters":
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
