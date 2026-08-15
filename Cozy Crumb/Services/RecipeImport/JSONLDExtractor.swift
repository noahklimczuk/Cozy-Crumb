//
//  JSONLDExtractor.swift
//  Cozy Crumb
//
//  Tier 1: schema.org/Recipe embedded as JSON-LD. This is what the large
//  majority of real recipe sites publish, and it is by far the most reliable
//  thing to read — the site has already done the structuring for us.
//
//  Real-world JSON-LD is messier than the spec suggests, so this handles:
//    - a bare Recipe object, or an array of objects, or an @graph wrapper
//    - "@type": "Recipe" or ["Recipe", "NewsArticle"]
//    - image as a string, an array, or an ImageObject
//    - instructions as a string, an array of strings, HowToStep objects, or
//      HowToSection groups containing itemListElement
//

import Foundation

struct JSONLDExtractor: RecipeExtracting {
    nonisolated init() {}

    nonisolated var confidence: Double { 0.95 }

    nonisolated func extract(from html: String, sourceURL: URL?) -> ImportedRecipe? {
        let scanner = HTMLScanner(html: html)

        for block in scanner.scriptContents(type: "application/ld+json") {
            guard let data = block.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data),
                  let node = findRecipeNode(in: parsed) else { continue }

            if let recipe = build(from: node, sourceURL: sourceURL) {
                return recipe
            }
        }

        return nil
    }

    // MARK: - Finding the Recipe

    /// Depth-first search for a node whose @type includes Recipe.
    private nonisolated func findRecipeNode(in object: Any) -> [String: Any]? {
        if let dictionary = object as? [String: Any] {
            if isRecipe(dictionary) { return dictionary }

            // @graph is the usual wrapper, but recurse everything — sites nest
            // the recipe in all sorts of places.
            for value in dictionary.values {
                if let found = findRecipeNode(in: value) { return found }
            }
            return nil
        }

        if let array = object as? [Any] {
            for element in array {
                if let found = findRecipeNode(in: element) { return found }
            }
        }

        return nil
    }

    private nonisolated func isRecipe(_ dictionary: [String: Any]) -> Bool {
        guard let type = dictionary["@type"] else { return false }

        if let single = type as? String {
            return single.caseInsensitiveCompare("Recipe") == .orderedSame
        }
        if let many = type as? [String] {
            return many.contains { $0.caseInsensitiveCompare("Recipe") == .orderedSame }
        }
        return false
    }

    // MARK: - Building

    private nonisolated func build(from node: [String: Any], sourceURL: URL?) -> ImportedRecipe? {
        guard let title = string(from: node["name"]), !title.isEmpty else { return nil }

        let ingredientLines = strings(from: node["recipeIngredient"] ?? node["ingredients"])
        let ingredients = ingredientLines
            .map { HTMLScanner.plainText($0) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { IngredientLineParser.parse($1, order: $0) }

        let steps = instructionSteps(from: node["recipeInstructions"])

        guard !ingredients.isEmpty || !steps.isEmpty else { return nil }

        return ImportedRecipe(
            title: HTMLScanner.plainText(title),
            summary: string(from: node["description"]).map { HTMLScanner.plainText($0) },
            imageURL: url(from: node["image"]),
            servings: servings(from: node["recipeYield"]),
            prepMinutes: string(from: node["prepTime"]).flatMap { DurationParser.minutes(fromISO8601: $0) },
            cookMinutes: cookMinutes(from: node),
            ingredients: ingredients,
            steps: steps,
            tags: tags(from: node),
            sourceName: string(from: node["author"]) ?? sourceURL?.host(),
            sourceURL: sourceURL,
            confidence: confidence
        )
    }

    /// Falls back to totalTime when cookTime is absent, which many sites do.
    private nonisolated func cookMinutes(from node: [String: Any]) -> Int? {
        if let cook = string(from: node["cookTime"]), let minutes = DurationParser.minutes(fromISO8601: cook) {
            return minutes
        }

        guard let total = string(from: node["totalTime"]),
              let totalMinutes = DurationParser.minutes(fromISO8601: total) else {
            return nil
        }

        // Total includes prep, so subtract it rather than double-counting.
        if let prep = string(from: node["prepTime"]),
           let prepMinutes = DurationParser.minutes(fromISO8601: prep),
           totalMinutes > prepMinutes {
            return totalMinutes - prepMinutes
        }

        return totalMinutes
    }

    // MARK: - Instructions

    private nonisolated func instructionSteps(from value: Any?) -> [ImportedStep] {
        let texts = instructionTexts(from: value)

        return texts
            .map { HTMLScanner.plainText($0) }
            .filter { !$0.isEmpty }
            .map { ImportedStep(text: $0, durationSeconds: DurationParser.seconds(inStepText: $0)) }
    }

    private nonisolated func instructionTexts(from value: Any?) -> [String] {
        guard let value else { return [] }

        if let text = value as? String {
            // A single blob. Split on newlines when the site used them,
            // otherwise keep it whole rather than guessing at sentences.
            let lines = text
                .components(separatedBy: .newlines)
                .map { HTMLScanner.plainText($0) }
                .filter { !$0.isEmpty }
            return lines.count > 1 ? lines : [text]
        }

        if let array = value as? [Any] {
            return array.flatMap { instructionTexts(from: $0) }
        }

        if let dictionary = value as? [String: Any] {
            // HowToSection wraps its steps in itemListElement.
            if let nested = dictionary["itemListElement"] {
                return instructionTexts(from: nested)
            }
            if let text = string(from: dictionary["text"] ?? dictionary["name"]) {
                return [text]
            }
        }

        return []
    }

    // MARK: - Field helpers

    private nonisolated func string(from value: Any?) -> String? {
        guard let value else { return nil }

        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let array = value as? [Any] {
            return array.compactMap { string(from: $0) }.first
        }
        if let dictionary = value as? [String: Any] {
            return string(from: dictionary["name"] ?? dictionary["@value"] ?? dictionary["text"])
        }

        return nil
    }

    private nonisolated func strings(from value: Any?) -> [String] {
        guard let value else { return [] }

        if let text = value as? String { return [text] }
        if let array = value as? [Any] { return array.compactMap { string(from: $0) } }
        if let single = string(from: value) { return [single] }

        return []
    }

    private nonisolated func url(from value: Any?) -> URL? {
        guard let value else { return nil }

        if let text = value as? String { return URL(string: text) }
        if let array = value as? [Any] {
            for element in array {
                if let found = url(from: element) { return found }
            }
            return nil
        }
        if let dictionary = value as? [String: Any] {
            return url(from: dictionary["url"] ?? dictionary["contentUrl"] ?? dictionary["@id"])
        }

        return nil
    }

    private nonisolated func servings(from value: Any?) -> Int? {
        guard let value else { return nil }

        if let number = value as? NSNumber { return number.intValue }
        if let text = string(from: value) { return DurationParser.servings(from: text) }

        return nil
    }

    private nonisolated func tags(from node: [String: Any]) -> [String] {
        var collected: [String] = []

        for key in ["keywords", "recipeCategory", "recipeCuisine", "suitableForDiet"] {
            guard let value = node[key] else { continue }

            if let text = value as? String {
                // Sites publish keywords as one comma-separated string.
                collected.append(contentsOf: text.components(separatedBy: ","))
            } else {
                collected.append(contentsOf: strings(from: value))
            }
        }

        let cleaned = collected
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0.count < 30 }

        // Deduplicate while keeping the order the site listed them in.
        var seen = Set<String>()
        return cleaned.filter { seen.insert($0).inserted }.prefix(8).map { $0 }
    }
}
