//
//  IngredientLineParser.swift
//  Cozy Crumb
//
//  Turns "115 g unsalted butter, softened" into its parts so servings can
//  scale it and the grocery list can group it.
//
//  The original line is always kept verbatim. Every field below it is an
//  interpretation, and the raw line is what the UI falls back to when the
//  interpretation comes out empty.
//

import Foundation

enum IngredientLineParser {

    /// Source spellings mapped onto the normalised unit set.
    private nonisolated static let unitAliases: [String: String] = [
        "g": "g", "gram": "g", "grams": "g", "gr": "g", "gm": "g",
        "kg": "kg", "kilo": "kg", "kilos": "kg", "kilogram": "kg", "kilograms": "kg",
        "ml": "ml", "milliliter": "ml", "milliliters": "ml", "millilitre": "ml", "millilitres": "ml",
        "l": "l", "liter": "l", "liters": "l", "litre": "l", "litres": "l",
        "tsp": "tsp", "teaspoon": "tsp", "teaspoons": "tsp", "tsps": "tsp",
        "tbsp": "tbsp", "tablespoon": "tbsp", "tablespoons": "tbsp", "tbs": "tbsp", "tbsps": "tbsp",
        "cup": "cup", "cups": "cup",
        "oz": "oz", "ounce": "oz", "ounces": "oz",
        "lb": "lb", "lbs": "lb", "pound": "lb", "pounds": "lb",
        "clove": "clove", "cloves": "clove",
        "can": "can", "cans": "can", "tin": "can", "tins": "can",
        "bunch": "bunch", "bunches": "bunch",
        "pinch": "pinch", "pinches": "pinch",
        "piece": "piece", "pieces": "piece"
    ]

    /// Words that describe preparation rather than the ingredient itself.
    private nonisolated static let prepWords: Set<String> = [
        "chopped", "diced", "sliced", "minced", "grated", "crushed", "melted",
        "softened", "divided", "packed", "sifted", "beaten", "peeled", "halved",
        "quartered", "drained", "rinsed", "trimmed", "shredded", "cubed",
        "roughly", "finely", "thinly", "freshly", "optional", "room"
    ]

    nonisolated static func parse(_ line: String, order: Int) -> ImportedIngredient {
        let raw = HTMLScanner.collapseWhitespace(line)

        guard !raw.isEmpty else {
            return ImportedIngredient(rawText: line, name: line)
        }

        if isSectionHeader(raw) {
            return ImportedIngredient(
                rawText: raw,
                name: raw,
                isSectionHeader: true
            )
        }

        var remainder = raw
        var quantity: Double?

        if let leading = QuantityParser.leadingQuantity(in: remainder) {
            quantity = leading.value
            remainder = leading.remainder
        }

        var unit: String?
        var tokens = remainder.split(separator: " ").map(String.init)

        if let first = tokens.first {
            let key = first
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
            if let normalised = unitAliases[key] {
                unit = normalised
                tokens.removeFirst()
            }
        }

        remainder = tokens.joined(separator: " ")

        // "of" after a unit — "2 cups of flour".
        if remainder.lowercased().hasPrefix("of ") {
            remainder = String(remainder.dropFirst(3))
        }

        let (name, note) = splitNameAndNote(remainder)

        return ImportedIngredient(
            rawText: raw,
            quantity: quantity,
            unit: unit,
            name: name.isEmpty ? raw : name,
            note: note,
            isSectionHeader: false,
            groceryCategory: GroceryCategoryGuesser.category(for: name.isEmpty ? raw : name)
        )
    }

    /// "For the sauce:" — a divider, not something you buy.
    nonisolated static func isSectionHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix(":") else { return false }
        // "2 eggs:" would be odd, but a header shouldn't lead with a number.
        guard let first = trimmed.first else { return false }
        return !first.isNumber
    }

    /// Splits "unsalted butter, softened" into name and note. Parenthesised
    /// asides count as notes too.
    private nonisolated static func splitNameAndNote(_ text: String) -> (name: String, note: String?) {
        var working = text.trimmingCharacters(in: .whitespaces)
        var notes: [String] = []

        // Parenthesised aside.
        while let open = working.firstIndex(of: "("),
              let close = working[open...].firstIndex(of: ")") {
            let inside = String(working[working.index(after: open)..<close])
                .trimmingCharacters(in: .whitespaces)
            if !inside.isEmpty { notes.append(inside) }
            working.removeSubrange(open...close)
            working = HTMLScanner.collapseWhitespace(working)
        }

        // Everything after the first comma is a note.
        if let comma = working.firstIndex(of: ",") {
            let after = String(working[working.index(after: comma)...])
                .trimmingCharacters(in: .whitespaces)
            if !after.isEmpty { notes.append(after) }
            working = String(working[working.startIndex..<comma])
        }

        // A trailing prep word with no comma: "butter softened".
        var tokens = working.split(separator: " ").map(String.init)
        while let last = tokens.last, prepWords.contains(last.lowercased()) {
            notes.insert(last, at: 0)
            tokens.removeLast()
        }

        let name = tokens
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.;"))

        return (name, notes.isEmpty ? nil : notes.joined(separator: ", "))
    }
}

// MARK: - Category

/// Best-effort aisle guessing. Wrong guesses are cheap — the grocery list lets
/// you move an item — so this errs towards a guess rather than "other".
enum GroceryCategoryGuesser {

    private nonisolated static let keywords: [(GroceryCategory, [String])] = [
        (.produce, ["onion", "garlic", "ginger", "tomato", "potato", "carrot", "celery",
                    "lemon", "lime", "orange", "apple", "banana", "berry", "berries",
                    "spinach", "kale", "lettuce", "cucumber", "pepper", "chilli", "chili",
                    "mushroom", "courgette", "zucchini", "aubergine", "eggplant", "broccoli",
                    "cauliflower", "cabbage", "herb", "parsley", "coriander", "cilantro",
                    "basil", "thyme", "rosemary", "mint", "spring onion", "scallion",
                    "avocado", "leek", "shallot", "corn", "pea", "bean sprout"]),
        (.dairy, ["milk", "butter", "cream", "cheese", "yoghurt", "yogurt", "egg",
                  "parmesan", "cheddar", "mozzarella", "pecorino", "mascarpone",
                  "creme fraiche", "buttermilk", "ricotta", "feta"]),
        (.meat, ["chicken", "beef", "pork", "lamb", "bacon", "sausage", "mince",
                 "steak", "salmon", "tuna", "cod", "prawn", "shrimp", "fish",
                 "turkey", "ham", "chorizo", "anchovy", "duck"]),
        (.bakery, ["bread", "baguette", "roll", "bun", "tortilla", "pita", "brioche",
                   "sourdough", "croissant"]),
        (.frozen, ["frozen", "ice cream", "peas frozen"]),
        (.condiment, ["sauce", "vinegar", "mustard", "mayonnaise", "ketchup", "soy",
                      "miso", "mirin", "sriracha", "harissa", "tahini", "pesto",
                      "honey", "syrup", "jam", "paste", "stock", "broth"]),
        (.pantry, ["flour", "sugar", "salt", "pepper", "oil", "rice", "pasta",
                   "spaghetti", "noodle", "lentil", "chickpea", "bean", "oat",
                   "baking powder", "baking soda", "yeast", "vanilla", "cocoa",
                   "chocolate", "cumin", "turmeric", "paprika", "cinnamon",
                   "coriander seed", "nutmeg", "stock cube", "coconut milk",
                   "tomatoes", "breadcrumb", "cornflour", "cornstarch", "nut",
                   "almond", "walnut", "seed", "raisin", "couscous", "quinoa"])
    ]

    nonisolated static func category(for name: String) -> GroceryCategory {
        let haystack = name.lowercased()

        // Ordered so the more specific lists win: "coconut milk" is pantry,
        // not dairy, because pantry is checked before the bare "milk" match.
        for (category, terms) in keywords.reversed() {
            if terms.contains(where: { haystack.contains($0) }) {
                return category
            }
        }

        for (category, terms) in keywords {
            if terms.contains(where: { haystack.contains($0) }) {
                return category
            }
        }

        return .other
    }
}
