//
//  MicrodataExtractor.swift
//  Cozy Crumb
//
//  Tier 2: schema.org microdata attributes, plus the older hRecipe class
//  names. Used when a site publishes no JSON-LD.
//
//  Confidence is 0.7 rather than 0.95 for a real reason: microdata is scattered
//  through the markup rather than collected in one object, so there is no way
//  to be certain the itemprops found belong to the same recipe — or to a
//  recipe at all, on a page listing several.
//

import Foundation

struct MicrodataExtractor: RecipeExtracting {
    nonisolated init() {}

    nonisolated var confidence: Double { 0.7 }

    nonisolated func extract(from html: String, sourceURL: URL?) -> ImportedRecipe? {
        let scanner = HTMLScanner(html: html)

        let ingredientLines = values(in: scanner, itemprops: ["recipeIngredient", "ingredients"])
            + classValues(in: scanner, classes: ["ingredient"])

        let instructionLines = values(in: scanner, itemprops: ["recipeInstructions", "instructions"])
            + classValues(in: scanner, classes: ["instruction"])

        let ingredients = ingredientLines
            .filter { !$0.isEmpty }
            .enumerated()
            .map { IngredientLineParser.parse($1, order: $0) }

        let steps = expandInstructions(instructionLines)
            .map { ImportedStep(text: $0, durationSeconds: DurationParser.seconds(inStepText: $0)) }

        guard !ingredients.isEmpty || !steps.isEmpty else { return nil }

        let title = values(in: scanner, itemprops: ["name"]).first
            ?? scanner.metaContent(property: "og:title")
            ?? ""

        guard !title.isEmpty else { return nil }

        return ImportedRecipe(
            title: title,
            summary: values(in: scanner, itemprops: ["description"]).first
                ?? scanner.metaContent(property: "og:description"),
            imageURL: scanner.metaContent(property: "og:image").flatMap { URL(string: $0) },
            servings: values(in: scanner, itemprops: ["recipeYield"]).first
                .flatMap { DurationParser.servings(from: $0) },
            prepMinutes: duration(in: scanner, itemprop: "prepTime"),
            cookMinutes: duration(in: scanner, itemprop: "cookTime"),
            ingredients: ingredients,
            steps: steps,
            tags: [],
            sourceName: scanner.metaContent(property: "og:site_name") ?? sourceURL?.host(),
            sourceURL: sourceURL,
            confidence: confidence
        )
    }

    // MARK: - Reading values

    private nonisolated func values(in scanner: HTMLScanner, itemprops: [String]) -> [String] {
        itemprops.flatMap { itemprop in
            scanner
                .elements(withAttribute: "itemprop", value: itemprop)
                .compactMap(\.microdataValue)
                .filter { !$0.isEmpty }
        }
    }

    /// Legacy hRecipe markup used class names rather than itemprop.
    private nonisolated func classValues(in scanner: HTMLScanner, classes: [String]) -> [String] {
        classes.flatMap { className in
            scanner
                .elements(withAttribute: "class", value: className)
                .map(\.text)
                .filter { !$0.isEmpty }
        }
    }

    /// Times live in a `datetime` or `content` attribute rather than the text.
    private nonisolated func duration(in scanner: HTMLScanner, itemprop: String) -> Int? {
        for element in scanner.elements(withAttribute: "itemprop", value: itemprop) {
            if let raw = HTMLScanner.attributeValue("datetime", in: element.openTag)
                ?? element.contentAttribute,
               let minutes = DurationParser.minutes(fromISO8601: raw) {
                return minutes
            }
            if let minutes = DurationParser.seconds(inStepText: element.text).map({ $0 / 60 }), minutes > 0 {
                return minutes
            }
        }
        return nil
    }

    /// A single instructions blob gets split on newlines; several separate
    /// elements are already the steps.
    private nonisolated func expandInstructions(_ lines: [String]) -> [String] {
        guard lines.count == 1, let only = lines.first else {
            return lines.filter { !$0.isEmpty }
        }

        let split = only
            .components(separatedBy: .newlines)
            .map { HTMLScanner.collapseWhitespace($0) }
            .filter { !$0.isEmpty }

        return split.isEmpty ? [only] : split
    }
}
