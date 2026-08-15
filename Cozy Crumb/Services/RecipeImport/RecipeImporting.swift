//
//  RecipeImporting.swift
//  Cozy Crumb
//
//  The shape every extractor produces, and the protocol they share.
//
//  Extractors deal in plain values rather than SwiftData models: nothing is
//  written to the store until the user has seen the review screen and pressed
//  save. A bad parse must never reach the library silently (§5.2).
//

import Foundation

// MARK: - Values

nonisolated struct ImportedIngredient: Sendable, Equatable, Identifiable {
    let id: UUID
    /// The source line, verbatim. Always preserved.
    var rawText: String
    var quantity: Double?
    var unit: String?
    var name: String
    var note: String?
    var isSectionHeader: Bool
    var groceryCategory: GroceryCategory

    nonisolated init(
        id: UUID = UUID(),
        rawText: String,
        quantity: Double? = nil,
        unit: String? = nil,
        name: String,
        note: String? = nil,
        isSectionHeader: Bool = false,
        groceryCategory: GroceryCategory = .other
    ) {
        self.id = id
        self.rawText = rawText
        self.quantity = quantity
        self.unit = unit
        self.name = name
        self.note = note
        self.isSectionHeader = isSectionHeader
        self.groceryCategory = groceryCategory
    }
}

nonisolated struct ImportedStep: Sendable, Equatable, Identifiable {
    let id: UUID
    var text: String
    var durationSeconds: Int?

    nonisolated init(id: UUID = UUID(), text: String, durationSeconds: Int? = nil) {
        self.id = id
        self.text = text
        self.durationSeconds = durationSeconds
    }
}

// Import parsing runs off the main actor. Keep this value type and its
// synthesized protocol conformances usable from the coordinator's
// `nonisolated` parsing path even though the app target defaults to MainActor.
nonisolated struct ImportedRecipe: Sendable, Equatable {
    var title: String
    var summary: String?
    var imageURL: URL?
    var servings: Int?
    var prepMinutes: Int?
    var cookMinutes: Int?
    var ingredients: [ImportedIngredient]
    var steps: [ImportedStep]
    var tags: [String]
    var sourceName: String?
    var sourceURL: URL?
    /// 0–1. Drives the "worth a quick look" banner on the review screen.
    var confidence: Double

    nonisolated init(
        title: String,
        summary: String? = nil,
        imageURL: URL? = nil,
        servings: Int? = nil,
        prepMinutes: Int? = nil,
        cookMinutes: Int? = nil,
        ingredients: [ImportedIngredient] = [],
        steps: [ImportedStep] = [],
        tags: [String] = [],
        sourceName: String? = nil,
        sourceURL: URL? = nil,
        confidence: Double
    ) {
        self.title = title
        self.summary = summary
        self.imageURL = imageURL
        self.servings = servings
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.ingredients = ingredients
        self.steps = steps
        self.tags = tags
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.confidence = confidence
    }

    /// A result with no ingredients and no steps isn't a recipe, whatever the
    /// page claimed. The cascade treats this as "keep going".
    nonisolated var isUsable: Bool {
        !title.isEmpty && (!ingredients.isEmpty || !steps.isEmpty)
    }

    /// Both lists present is the bar for "don't bother with the next tier".
    nonisolated var isComplete: Bool {
        !title.isEmpty && !ingredients.isEmpty && !steps.isEmpty
    }
}

// MARK: - Protocol

/// One tier of the import cascade. Extractors are pure: they take HTML in and
/// give values out, with no networking of their own, so they can be tested
/// against saved fixtures.
protocol RecipeExtracting: Sendable {
    /// Confidence this tier claims when it succeeds.
    nonisolated var confidence: Double { get }

    /// Returns nil when this tier finds nothing — that's expected, not an
    /// error, and means the cascade moves on.
    ///
    /// `nonisolated` so the coordinator actor can run extractors off the main
    /// thread; the target's default MainActor isolation would otherwise pin
    /// every tier to the main thread for what is pure string work.
    nonisolated func extract(from html: String, sourceURL: URL?) -> ImportedRecipe?
}
