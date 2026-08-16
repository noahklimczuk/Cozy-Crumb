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
        /// The platform gave us nothing readable — ask the user to paste it.
        case needsCaption
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

    /// What we managed to gather from a social post, if this is one.
    var socialPost: SocialPost?
    /// Caption the user pasted by hand when the platform would not share it.
    var pastedCaption = ""
    /// Describes what happened on a social import, for the review banner.
    var socialNote: String?

    private let coordinator: ImportCoordinator
    private let imageFetcher: ImageFetcher
    private let socialImporter: SocialImporter
    private let parser: AIRecipeParser
    private let keychain: KeychainStore

    init(
        coordinator: ImportCoordinator = ImportCoordinator(),
        imageFetcher: ImageFetcher = ImageFetcher(),
        socialImporter: SocialImporter = SocialImporter(),
        parser: AIRecipeParser = AIRecipeParser(),
        keychain: KeychainStore = .shared
    ) {
        self.coordinator = coordinator
        self.imageFetcher = imageFetcher
        self.socialImporter = socialImporter
        self.parser = parser
        self.keychain = keychain
    }

    /// Whether the Sous Chef is awake. Everything social depends on it.
    var isAIAvailable: Bool {
        keychain.hasValue(for: .geminiAPIKey)
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

        // Social posts never serve recipe markup, so the scraping cascade is
        // skipped entirely rather than being run and failing.
        if let platform = SocialPlatform.detect(from: url) {
            await runSocialImport(from: url, platform: platform, existingRecipes: existingRecipes)
            return
        }

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

    // MARK: - Social

    /// YouTube gets the video read. TikTok gets its caption. Instagram and
    /// Facebook get whatever Open Graph they will serve, and the paste box
    /// when they serve nothing.
    private func runSocialImport(
        from url: URL,
        platform: SocialPlatform,
        existingRecipes: [Recipe]
    ) async {
        let post = await socialImporter.fetch(url: url, platform: platform)
        socialPost = post
        isSocialSource = true

        // Match duplicates on the canonical URL, so the same post shared two
        // different ways is recognised as one recipe.
        duplicate = existingRecipes.first { $0.sourceURL == post.url }

        if let thumbnail = post.thumbnailURL {
            heroImageData = await imageFetcher.downscaledImage(from: thumbnail)
        }

        guard isAIAvailable else {
            // Without a key there is nothing that can read a caption, so hand
            // over what we have and say why.
            fallBackToManual(
                post: post,
                note: "Add your Gemini key in Settings and I'll read \(platform.displayName) posts for you. For now, here's what I could get."
            )
            return
        }

        if platform.supportsVideoAnalysis {
            switch await parser.parseVideo(post: post) {
            case .success(let recipe):
                accept(recipe, post: post, note: "I watched the video for this one — worth a check.")
                return
            case .failure(let error):
                Log.importer.info("Video parse failed: \(String(describing: error), privacy: .public)")
                // Fall through to the caption, which often still works.
            }
        }

        if post.hasUsableText, let caption = post.caption {
            switch await parser.parse(caption: caption, post: post) {
            case .success(let recipe):
                accept(recipe, post: post, note: "Read from the caption — worth a check.")
                return
            case .failure(let error):
                Log.importer.info("Caption parse failed: \(String(describing: error), privacy: .public)")
            }
        }

        // Nothing readable came back. Ask for the caption rather than saving
        // a hollow recipe.
        prefillFromPost(post)
        stage = .needsCaption
    }

    /// Parses a caption the user pasted in themselves. This path always works,
    /// whatever the platform decided to serve us.
    func parsePastedCaption() async {
        let caption = pastedCaption.trimmingCharacters(in: .whitespacesAndNewlines)

        guard caption.count >= 40 else {
            stage = .failed(.captionTooShort)
            return
        }

        guard isAIAvailable else {
            stage = .failed(.missingAPIKey)
            return
        }

        guard let post = socialPost
            ?? draft.sourceURL.map({ SocialPost(platform: .instagram, url: $0) }) else {
            stage = .failed(.badURL)
            return
        }

        stage = .working

        switch await parser.parse(caption: caption, post: post, wasPastedByUser: true) {
        case .success(let recipe):
            accept(recipe, post: post, note: "Read from the caption you pasted — worth a check.")
        case .failure(let error):
            if error == .noRecipeFound {
                prefillFromPost(post)
                didFallBackToManual = true
                socialNote = "I couldn't find a recipe in that text. Fill in what you know?"
                stage = .review
            } else {
                stage = .failed(error)
            }
        }
    }

    private func accept(_ recipe: ImportedRecipe, post: SocialPost, note: String?) {
        draft = recipe
        draft.sourceURL = post.url
        draft.sourceName = recipe.sourceName ?? post.author ?? post.platform.displayName
        didFallBackToManual = false
        socialNote = note
        stage = .review
    }

    private func fallBackToManual(post: SocialPost, note: String) {
        prefillFromPost(post)
        didFallBackToManual = true
        socialNote = note
        stage = .review
    }

    /// Seeds the draft with the metadata we have, so manual entry starts from
    /// something rather than a blank form.
    private func prefillFromPost(_ post: SocialPost) {
        draft = ImportedRecipe(
            title: post.title ?? "",
            summary: nil,
            imageURL: post.thumbnailURL,
            servings: 4,
            sourceName: post.author ?? post.platform.displayName,
            sourceURL: post.url,
            confidence: 0
        )
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

    /// Merges the line parser's reading with what is already there, rather
    /// than replacing it.
    ///
    /// This used to overwrite unconditionally, which quietly broke servings
    /// scaling and unit conversion for every social import. A web page gives
    /// clean lines ("115 g unsalted butter") that reparse identically, so the
    /// damage was invisible there. A caption gives the poster's phrasing
    /// ("• 2 eggs", "🧈 a knob of butter"), which the line parser reads as
    /// having no quantity — so a perfectly good AI parse was replaced with
    /// nothing to scale.
    ///
    /// The line parser wins only where it actually found something. That keeps
    /// hand-edits authoritative without throwing away a better reading.
    func reparseIngredient(at index: Int) {
        guard draft.ingredients.indices.contains(index) else { return }

        let existing = draft.ingredients[index]
        guard !existing.rawText.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let reparsed = IngredientLineParser.parse(existing.rawText, order: index)

        // A quantity means the line decomposed cleanly, so the rest of that
        // reading can be trusted too.
        let decomposed = reparsed.quantity != nil

        let name: String = if decomposed, !reparsed.name.isEmpty {
            reparsed.name
        } else if !existing.name.isEmpty {
            existing.name
        } else {
            reparsed.name
        }

        draft.ingredients[index] = ImportedIngredient(
            id: existing.id,
            rawText: existing.rawText,
            quantity: decomposed ? reparsed.quantity : existing.quantity,
            unit: decomposed ? reparsed.unit : existing.unit,
            name: name,
            note: reparsed.note ?? existing.note,
            isSectionHeader: reparsed.isSectionHeader || existing.isSectionHeader,
            groceryCategory: GroceryCategoryGuesser.category(for: name)
        )
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
