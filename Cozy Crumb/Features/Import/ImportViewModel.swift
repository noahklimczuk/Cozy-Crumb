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

    /// The recipe a save would overwrite: either a duplicate found on import
    /// (§8.6) or the recipe currently being edited.
    var existing: Recipe?

    /// True when the editor was opened from a saved recipe rather than an
    /// import, which changes the buttons and keeps the original source kind.
    var isEditingExisting = false

    private var editingSourceKind: SourceKind?

    /// Kept for the import flow's duplicate prompt, which only applies when we
    /// arrived here from a link.
    var duplicate: Recipe? {
        isEditingExisting ? nil : existing
    }

    /// What we managed to gather from a social post, if this is one.
    var socialPost: SocialPost?
    /// Caption the user pasted by hand when the platform would not share it.
    var pastedCaption = ""
    /// Describes what happened on a social import, for the review banner.
    var socialNote: String?
    /// Why the "paste the caption" screen is being shown, in the app's voice.
    var captionPromptReason: String?

    private let coordinator: ImportCoordinator
    private let imageFetcher: ImageFetcher
    private let socialImporter: SocialImporter
    private let mediaResolver: SocialMediaResolver
    private let parser: AIRecipeParser
    private let keychain: KeychainStore

    init(
        coordinator: ImportCoordinator = ImportCoordinator(),
        imageFetcher: ImageFetcher = ImageFetcher(),
        socialImporter: SocialImporter = SocialImporter(),
        mediaResolver: SocialMediaResolver = SocialMediaResolver(),
        parser: AIRecipeParser = AIRecipeParser(),
        keychain: KeychainStore = .shared
    ) {
        self.coordinator = coordinator
        self.imageFetcher = imageFetcher
        self.socialImporter = socialImporter
        self.mediaResolver = mediaResolver
        self.parser = parser
        self.keychain = keychain
    }

    /// Whether the Sous Chef is awake. Everything social depends on it.
    var isAIAvailable: Bool {
        keychain.hasValue(for: .geminiAPIKey)
    }

    // MARK: - Entry points

    /// Opens an existing recipe in the editor.
    ///
    /// Editing reuses the review screen and the update-in-place save path, so
    /// there is one editor rather than two that drift apart. The recipe is put
    /// in `existing` so saving overwrites it instead of creating a copy.
    func startEditing(_ recipe: Recipe) {
        draft = ImportedRecipe(editing: recipe)
        heroImageData = recipe.heroImageData
        existing = recipe
        isEditingExisting = true
        editingSourceKind = recipe.sourceKind
        didFallBackToManual = false
        socialNote = nil
        isSocialSource = recipe.sourceKind == .social
        stage = .review
    }

    /// Starts a blank manual entry.
    func startManualEntry() {
        draft = ImportedRecipe(title: "", servings: 4, confidence: 1)
        heroImageData = nil
        didFallBackToManual = false
        isSocialSource = false
        existing = nil
        isEditingExisting = false
        editingSourceKind = nil
        stage = .review
    }

    func importFromPastedText(overrideText: String? = nil) async {
        let raw = (overrideText ?? urlText).trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            urlText = raw
        }

        guard let url = Self.firstURL(in: raw) else {
            stage = .failed(.badURL)
            return
        }

        await runImport(from: url)
    }

    func runImport(from url: URL, existingRecipes: [Recipe] = []) async {
        stage = .working
        captionPromptReason = nil

        // Social posts never serve recipe markup, so the scraping cascade is
        // skipped entirely rather than being run and failing.
        if let platform = SocialPlatform.detect(from: url) {
            await runSocialImport(from: url, platform: platform, existingRecipes: existingRecipes)
            return
        }

        existing = existingRecipes.first { $0.sourceURL == url }

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
            } else if isAIAvailable, let html = result.rawHTML, html.count >= 40 {
                // Tier 3: structured scrapers found no recipe schema, so try AI text extraction on the page HTML.
                switch await parser.parse(text: html, sourceURL: url, sourceName: result.metadata.siteName) {
                case .success(let aiRecipe):
                    draft = aiRecipe
                    didFallBackToManual = false
                case .failure:
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
            } else {
                // Pre-fill what we recovered and let the user finish it by hand.
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
        existing = existingRecipes.first { $0.sourceURL == post.url }

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

        // The caption was a hook rather than a recipe — "full recipe below 👇"
        // with nothing below it. The recipe is in the video, so go and get the
        // video.
        if await importFromPostMedia(post: post) { return }

        // Nothing readable came back. Ask for the caption, or for the video,
        // rather than saving a hollow recipe.
        prefillFromPost(post)
        captionPromptReason = nil
        stage = .needsCaption
    }

    // MARK: - Reading the post's media

    /// The path for the posts this app exists for: a Reel or a TikTok whose
    /// caption never contained the recipe.
    ///
    /// Three things are tried, cheapest first, and any of them can quietly come
    /// back with nothing — these platforms serve a logged-out visitor less
    /// every year:
    ///
    ///   1. a fuller caption than Open Graph gave us (Instagram's embed page
    ///      serves the whole thing where og:description is truncated)
    ///   2. the video itself, sent to Gemini as bytes so it reads the on-screen
    ///      text *and* hears the narration
    ///   3. the post's images — a carousel's recipe card, or the cover frame
    ///
    /// Returns true when one of them produced a recipe.
    private func importFromPostMedia(post: SocialPost) async -> Bool {
        // Gemini fetches YouTube itself, and has already had its go by here.
        guard post.platform != .youtube else { return false }

        var media = await mediaResolver.resolve(post: post)
        guard !media.isEmpty else { return false }

        // Instagram wraps a caption in engagement noise wherever it serves one.
        media.caption = media.caption.map {
            SocialImporter.cleanCaption($0, platform: post.platform)
        }

        if heroImageData == nil, let cover = media.imageURLs.first {
            heroImageData = await imageFetcher.downscaledImage(from: cover)
        }

        // 1. A caption we hadn't seen in full before.
        if let caption = media.caption,
           caption.count >= 40,
           caption.count > (post.caption?.count ?? 0),
           case .success(let recipe) = await parser.parse(caption: caption, post: post) {
            accept(recipe, post: post, note: "Read from the post's caption — worth a check.")
            return true
        }

        // 2. The video.
        if let videoURL = media.videoURL,
           let video = await mediaResolver.downloadVideo(from: videoURL, referer: post.url) {
            let outcome = await parser.parse(
                video: video.data,
                mimeType: video.mimeType,
                post: post,
                caption: media.caption
            )

            if case .success(let recipe) = outcome {
                accept(
                    recipe,
                    post: post,
                    note: "The caption didn't have the recipe, so I watched the video — worth a check."
                )
                return true
            }

            Log.importer.info("Post video parse found nothing")
        }

        // 3. The pictures, where a recipe card often hides.
        let images = await downloadImages(media.imageURLs, limit: 4)

        if !images.isEmpty {
            let outcome = await parser.parse(
                images: images,
                kind: .images,
                post: post,
                caption: media.caption
            )

            if case .success(let recipe) = outcome {
                accept(
                    recipe,
                    post: post,
                    note: "I read this one off the pictures in the post — worth a proper check."
                )
                return true
            }
        }

        return false
    }

    private func downloadImages(_ urls: [URL], limit: Int) async -> [Data] {
        var images: [Data] = []

        for url in urls.prefix(limit) {
            if let data = await imageFetcher.downscaledImage(from: url) {
                images.append(data)
            }
        }

        return images
    }

    // MARK: - Media the user hands over

    /// The always-works route for a Reel the app can't reach: the user saves
    /// the video, or screenshots it, and passes it to us directly.
    ///
    /// A short clip goes over whole, audio and all. A long one is sampled into
    /// stills first, because the request has to fit inside Gemini's inline
    /// limit — worse, but far better than nothing.
    func importPickedVideo(at url: URL) async {
        defer { try? FileManager.default.removeItem(at: url) }

        let post = currentPost
        stage = .working

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
        var outcome: Result<ImportedRecipe, CozyError> = .failure(.noRecipeFound)

        if size <= SocialMediaResolver.inlineVideoByteLimit, let data = try? Data(contentsOf: url) {
            outcome = await parser.parse(
                video: data,
                mimeType: Self.mimeType(for: url),
                post: post,
                caption: nonEmptyPastedCaption
            )
        }

        // Either it was too big to send whole, or Gemini couldn't make a recipe
        // out of it. Stills are the second chance.
        if case .failure = outcome {
            let frames = await VideoFrameSampler.frames(from: url)

            if !frames.isEmpty {
                outcome = await parser.parse(
                    images: frames,
                    kind: .frames,
                    post: post,
                    caption: nonEmptyPastedCaption
                )
            }
        }

        finish(outcome, post: post, note: "Read from the video you gave me — worth a check.")
    }

    /// Screenshots of the post: the ingredient overlay, the method, the recipe
    /// card at the end.
    func importPickedImages(_ images: [Data]) async {
        let usable = images.filter { !$0.isEmpty }
        guard !usable.isEmpty else { return }

        let post = currentPost
        stage = .working

        let outcome = await parser.parse(
            images: usable,
            kind: .images,
            post: post,
            caption: nonEmptyPastedCaption
        )

        finish(outcome, post: post, note: "Read from the screenshots — worth a check.")
    }

    /// Lands a media parse: straight to review on success, back to the paste
    /// screen with an explanation when it found nothing.
    private func finish(_ outcome: Result<ImportedRecipe, CozyError>, post: SocialPost, note: String) {
        switch outcome {
        case .success(let recipe):
            if heroImageData == nil, let imageURL = recipe.imageURL {
                // Best effort only; the recipe is already good.
                Task { heroImageData = await imageFetcher.downscaledImage(from: imageURL) }
            }
            accept(recipe, post: post, note: note)

        case .failure(let error):
            Log.importer.info("Picked-media parse failed: \(String(describing: error), privacy: .public)")

            captionPromptReason = switch error {
            case .missingAPIKey, .invalidAPIKey, .modelUnavailable:
                error.friendlyMessage
            case .noRecipeFound:
                "I couldn't find a recipe in that. If the recipe's spoken or on screen somewhere else, try the whole video — or paste the caption."
            default:
                "That didn't come back with anything. Want to try the caption instead?"
            }

            stage = .needsCaption
        }
    }

    private var nonEmptyPastedCaption: String? {
        let trimmed = pastedCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Stands in for a link when there isn't one. `accept` strips it again, so
    /// a recipe read off the camera roll is saved with no source URL rather
    /// than a made-up one.
    private nonisolated static let placeholderPostURL = URL(
        string: "https://cozycrumb.local/from-your-camera-roll"
    )!

    /// The post we're working on, invented from the draft when the user reached
    /// the media picker some other way.
    private var currentPost: SocialPost {
        if let socialPost { return socialPost }

        let url = draft.sourceURL ?? Self.placeholderPostURL
        let platform = draft.sourceURL.flatMap(SocialPlatform.detect(from:)) ?? .instagram

        return SocialPost(
            platform: platform,
            url: url,
            title: draft.title.isEmpty ? nil : draft.title,
            author: draft.sourceName
        )
    }

    private nonisolated static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mov", "qt": "video/quicktime"
        case "m4v": "video/x-m4v"
        case "webm": "video/webm"
        default: "video/mp4"
        }
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
        // A recipe read from the camera roll has no link to keep.
        draft.sourceURL = post.url == Self.placeholderPostURL ? nil : post.url
        draft.sourceName = recipe.sourceName ?? post.author ?? post.platform.displayName
        didFallBackToManual = false
        socialNote = note
        captionPromptReason = nil
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

        if updatingExisting, let existing {
            // Replace the children rather than merging — the user has just
            // reviewed the new version, so it wins.
            for ingredient in existing.ingredients { context.delete(ingredient) }
            for step in existing.steps { context.delete(step) }
            existing.ingredients = []
            existing.steps = []
            target = existing
        } else {
            let recipe = Recipe(title: draft.title, sourceKind: sourceKind)
            context.insert(recipe)
            target = recipe
        }

        apply(to: target, in: context)
        CuisineBackfill.classify(target)

        do {
            try context.save()

            // Only a genuinely new recipe is a signal. Re-saving an edit is
            // housekeeping, and reading it as fresh interest would let one
            // fiddled-with recipe outweigh five real ones.
            if !updatingExisting {
                SignalLog.imported(target, in: context)
            }

            return target
        } catch {
            Log.data.error("Could not save imported recipe: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private var sourceKind: SourceKind {
        // An edit never changes where the recipe came from.
        if let editingSourceKind { return editingSourceKind }
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

    /// Pulls and normalises the first URL out of pasted text (which may be wrapped
    /// in quotes, brackets, missing http/https, or surrounded by share text).
    nonisolated static func firstURL(in text: String) -> URL? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown fences, quotes, parens or angle brackets wrapping the URL
        if (cleaned.hasPrefix("<") && cleaned.hasSuffix(">")) || (cleaned.hasPrefix("(") && cleaned.hasSuffix(")")) {
            cleaned = String(cleaned.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))

        // Try direct URL initialization first if scheme is specified
        if let direct = URL(string: cleaned), direct.scheme != nil, direct.host() != nil {
            return direct
        }

        // Try prepending https:// if missing scheme (e.g. www.allrecipes.com/recipe/123 or tiktok.com/@user/video/123)
        if !cleaned.contains("://") {
            let candidate = "https://" + cleaned
            if let directWithScheme = URL(string: candidate), let host = directWithScheme.host(), host.contains(".") {
                return directWithScheme
            }
        }

        // Use NSDataDetector for URLs embedded in share text messages
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        let range = NSRange(cleaned.startIndex..., in: cleaned)
        if let match = detector.firstMatch(in: cleaned, range: range), let matchURL = match.url {
            return matchURL
        }

        // Fallback for single host tokens missing scheme
        let firstWord = cleaned.components(separatedBy: .whitespacesAndNewlines).first ?? cleaned
        if !firstWord.contains("://") {
            let candidate = "https://" + firstWord
            if let url = URL(string: candidate), let host = url.host(), host.contains(".") {
                return url
            }
        }

        return nil
    }
}
