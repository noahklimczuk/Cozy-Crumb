//
//  ImportViewModel.swift
//  Cozy Crumb
//
//  Drives the import flow: paste a link, run the cascade, land on the review
//  screen. Nothing reaches the library without passing through review (§5.2).
//

import Foundation
import SwiftData
import SwiftUI
import os

@Observable
@MainActor
final class ImportViewModel {

    enum Stage: Equatable {
        case entry
        case working
        case review
        case failed(CozyError)
    }

    var stage: Stage = .entry
    var urlText = ""

    /// The editable recipe. Also the manual-entry document — a blank draft and
    /// a parsed one are the same thing to the review screen.
    var draft = ImportedRecipe(title: "", confidence: 1)
    var heroImageData: Data?

    /// Set when the parse came back empty and the user is filling it in.
    var didFallBackToManual = false
    /// Set when the source is a site that never serves recipe markup.
    var isSocialSource = false

    /// An existing recipe with the same source URL (§8.6).
    var duplicate: Recipe?

    private let coordinator: ImportCoordinator
    private let imageFetcher: ImageFetcher

    init(coordinator: ImportCoordinator = ImportCoordinator(), imageFetcher: ImageFetcher = ImageFetcher()) {
        self.coordinator = coordinator
        self.imageFetcher = imageFetcher
    }

    // MARK: - Entry points

    /// Starts a blank manual entry.
    func startManualEntry() {
        draft = ImportedRecipe(title: "", servings: 4, confidence: 1)
        heroImageData = nil
        didFallBackToManual = false
        isSocialSource = false
        duplicate = nil
        stage = .review
    }

    func importFromPastedText() async {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = Self.firstURL(in: trimmed) else {
            stage = .failed(.badURL)
            return
        }

        await runImport(from: url)
    }

    func runImport(from url: URL, existingRecipes: [Recipe] = []) async {
        stage = .working
        duplicate = existingRecipes.first { $0.sourceURL == url }

        let outcome = await coordinator.importRecipe(from: url)

        switch outcome {
        case .failure(let error):
            Log.importer.info("Import failed: \(String(describing: error), privacy: .public)")
            stage = .failed(error)

        case .success(let result):
            isSocialSource = result.isSocialSource

            if let recipe = result.recipe {
                draft = recipe
                didFallBackToManual = false
            } else {
                // Never save a broken parse. Pre-fill what we recovered and let
                // the user finish it by hand.
                draft = ImportedRecipe(
                    title: result.metadata.title ?? "",
                    summary: result.metadata.description,
                    imageURL: result.metadata.imageURL,
                    servings: 4,
                    sourceName: result.metadata.siteName,
                    sourceURL: url,
                    confidence: 0
                )
                didFallBackToManual = true
            }

            await loadHeroImage()
            stage = .review
        }
    }

    private func loadHeroImage() async {
        guard let imageURL = draft.imageURL else { return }
        heroImageData = await imageFetcher.downscaledImage(from: imageURL)
    }

    // MARK: - Editing

    func addIngredient() {
        draft.ingredients.append(ImportedIngredient(rawText: "", name: ""))
    }

    func addStep() {
        draft.steps.append(ImportedStep(text: ""))
    }

    /// Re-reads a hand-edited line so quantity, unit and category stay in step
    /// with the text the user actually typed.
    func reparseIngredient(id: UUID) {
        guard let index = draft.ingredients.firstIndex(where: { $0.id == id }) else { return }
        reparseIngredient(at: index)
    }

    func reparseStepDuration(id: UUID) {
        guard let index = draft.steps.firstIndex(where: { $0.id == id }) else { return }
        reparseStepDuration(at: index)
    }

    func reparseAllIngredients() {
        for index in draft.ingredients.indices {
            reparseIngredient(at: index)
        }

        for index in draft.steps.indices {
            reparseStepDuration(at: index)
        }
    }

    func reparseIngredient(at index: Int) {
        guard draft.ingredients.indices.contains(index) else { return }

        let edited = draft.ingredients[index]
        guard !edited.rawText.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        var reparsed = IngredientLineParser.parse(edited.rawText, order: index)
        reparsed = ImportedIngredient(
            id: edited.id,
            rawText: reparsed.rawText,
            quantity: reparsed.quantity,
            unit: reparsed.unit,
            name: reparsed.name,
            note: reparsed.note,
            isSectionHeader: reparsed.isSectionHeader,
            groceryCategory: reparsed.groceryCategory
        )

        draft.ingredients[index] = reparsed
    }

    func reparseStepDuration(at index: Int) {
        guard draft.steps.indices.contains(index) else { return }
        draft.steps[index].durationSeconds = DurationParser.seconds(inStepText: draft.steps[index].text)
    }

    var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespaces).isEmpty
            && !(draft.ingredients.isEmpty && draft.steps.isEmpty)
    }

    var showsConfidenceBanner: Bool {
        draft.confidence > 0 && draft.confidence < 0.8
    }

    // MARK: - Saving

    /// Writes the draft into the store. Returns the saved recipe so the caller
    /// can navigate to it.
    @discardableResult
    func save(into context: ModelContext, updatingExisting: Bool) -> Recipe? {
        // Re-read every line before writing. The review screen only lets the
        // user edit the raw text, so reparsing here keeps quantity, unit and
        // category in step with whatever they typed. It is idempotent for
        // lines the parser produced in the first place.
        reparseAllIngredients()

        let target: Recipe

        if updatingExisting, let duplicate {
            // Replace the children rather than merging — the user has just
            // reviewed the new version, so it wins.
            for ingredient in duplicate.ingredients { context.delete(ingredient) }
            for step in duplicate.steps { context.delete(step) }
            duplicate.ingredients = []
            duplicate.steps = []
            target = duplicate
        } else {
            let recipe = Recipe(title: draft.title, sourceKind: sourceKind)
            context.insert(recipe)
            target = recipe
        }

        apply(to: target, in: context)

        do {
            try context.save()
            return target
        } catch {
            Log.data.error("Could not save imported recipe: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private var sourceKind: SourceKind {
        if isSocialSource { return .social }
        if draft.sourceURL != nil { return .web }
        return .manual
    }

    private func apply(to recipe: Recipe, in context: ModelContext) {
        recipe.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.summary = draft.summary?.isEmpty == true ? nil : draft.summary
        recipe.sourceURL = draft.sourceURL
        recipe.sourceName = draft.sourceName
        recipe.sourceKind = sourceKind
        recipe.servings = max(1, draft.servings ?? 4)
        recipe.prepMinutes = draft.prepMinutes
        recipe.cookMinutes = draft.cookMinutes
        recipe.tags = draft.tags
        recipe.importConfidence = draft.confidence
        recipe.touch()

        if let heroImageData {
            recipe.heroImageData = heroImageData
        }

        for (index, item) in draft.ingredients.enumerated()
        where !item.rawText.trimmingCharacters(in: .whitespaces).isEmpty {
            let ingredient = Ingredient(
                order: index,
                rawText: item.rawText,
                quantity: item.quantity,
                unit: item.unit,
                name: item.name.isEmpty ? item.rawText : item.name,
                note: item.note,
                groceryCategory: item.groceryCategory,
                isSectionHeader: item.isSectionHeader
            )
            context.insert(ingredient)
            ingredient.recipe = recipe
        }

        for (index, item) in draft.steps.enumerated()
        where !item.text.trimmingCharacters(in: .whitespaces).isEmpty {
            let step = RecipeStep(
                order: index,
                text: item.text,
                durationSeconds: item.durationSeconds
            )
            context.insert(step)
            step.recipe = recipe
        }
    }

    // MARK: - Helpers

    /// Pulls the first URL out of pasted text, which is often a whole share
    /// message rather than a bare link.
    nonisolated static func firstURL(in text: String) -> URL? {
        if let direct = URL(string: text), direct.scheme != nil, direct.host() != nil {
            return direct
        }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, range: range)?.url
    }
}
