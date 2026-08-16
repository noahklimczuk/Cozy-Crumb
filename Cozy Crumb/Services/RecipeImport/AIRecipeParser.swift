//
//  AIRecipeParser.swift
//  Cozy Crumb
//
//  Tier 3 of the cascade, and the whole story for social posts.
//
//  Three entry points, all landing on the same schema-constrained call:
//    - text     a web page the scrapers could not read, or pasted text
//    - caption  a social caption
//    - video    a YouTube URL, which Gemini watches directly
//
//  Confidence is clamped to 0.85 however sure the model claims to be, so an
//  AI parse never outranks real structured data and always trips the review
//  banner.
//

import Foundation
import os

struct AIRecipeParser: Sendable {

    private let client: GeminiClient
    private let model: GeminiModel

    /// However confident the model says it is, a parse is still a parse.
    private nonisolated static let confidenceCeiling = 0.85

    init(client: GeminiClient = GeminiClient(), model: GeminiModel = .balanced) {
        self.client = client
        self.model = model
    }

    // MARK: - Entry points

    func parse(text: String, sourceURL: URL?, sourceName: String?) async -> Result<ImportedRecipe, CozyError> {
        let capped = Self.cap(text, at: 15_000)
        guard capped.count >= 40 else { return .failure(.captionTooShort) }

        return await run(
            parts: [.text(Prompts.extractionFromText(capped))],
            sourceURL: sourceURL,
            sourceName: sourceName,
            timeout: GeminiClient.textTimeout
        )
    }

    func parse(caption: String, post: SocialPost, wasPastedByUser: Bool = false) async -> Result<ImportedRecipe, CozyError> {
        let capped = Self.cap(caption, at: 15_000)
        guard capped.count >= 40 else { return .failure(.captionTooShort) }

        var prompt = Prompts.extractionFromCaption(
            caption: capped,
            platform: post.platform.displayName,
            author: post.author
        )
        if wasPastedByUser {
            prompt = Prompts.pastedCaptionHint + "\n\n" + prompt
        }

        return await run(
            parts: [.text(prompt)],
            sourceURL: post.url,
            sourceName: post.author ?? post.platform.displayName,
            timeout: GeminiClient.textTimeout
        )
    }

    /// YouTube only. Gemini fetches and watches the video server-side; there
    /// is no equivalent for TikTok, Instagram or Facebook, so this must not be
    /// called for them.
    func parseVideo(post: SocialPost) async -> Result<ImportedRecipe, CozyError> {
        guard post.platform.supportsVideoAnalysis else {
            return .failure(.socialNeedsCaption)
        }

        // The media part goes first — Gemini attends to it better that way.
        let parts: [GeminiPart] = [
            .youTube(post.url),
            .text(Prompts.extractionFromVideo(
                title: post.title,
                author: post.author,
                description: post.caption
            ))
        ]

        return await run(
            parts: parts,
            sourceURL: post.url,
            sourceName: post.author ?? post.platform.displayName,
            timeout: GeminiClient.visionTimeout
        )
    }

    // MARK: - Shared

    private func run(
        parts: [GeminiPart],
        sourceURL: URL?,
        sourceName: String?,
        timeout: TimeInterval
    ) async -> Result<ImportedRecipe, CozyError> {
        let outcome = await client.generate(
            model: model,
            systemInstruction: Prompts.extractionSystem,
            parts: parts,
            schema: RecipeSchemas.extraction,
            temperature: 0.2,
            // Generous, because thinking tokens come out of this same budget
            // on Gemini 3 and a truncated response is unparseable JSON.
            maxOutputTokens: 16_384,
            timeout: timeout
        )

        switch outcome {
        case .failure(let error):
            return .failure(error)

        case .success(let raw):
            let cleaned = GeminiClient.stripJSONFences(raw)

            guard let data = cleaned.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(AIExtractedRecipe.self, from: data) else {
                Log.ai.error("Could not decode an extraction response")
                return .failure(.decodingFailed)
            }

            guard decoded.found else { return .failure(.noRecipeFound) }

            let recipe = Self.convert(decoded, sourceURL: sourceURL, sourceName: sourceName)
            guard recipe.isUsable else { return .failure(.noRecipeFound) }

            return .success(recipe)
        }
    }

    // MARK: - Conversion

    nonisolated static func convert(
        _ decoded: AIExtractedRecipe,
        sourceURL: URL?,
        sourceName: String?
    ) -> ImportedRecipe {
        let ingredients = decoded.ingredients
            .filter { !$0.rawText.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { item in
                ImportedIngredient(
                    rawText: item.rawText,
                    quantity: item.quantity,
                    unit: Self.normalisedUnit(item.unit),
                    name: item.name.isEmpty ? item.rawText : item.name,
                    note: item.note,
                    isSectionHeader: item.isSectionHeader,
                    // The model is not asked to categorise; our own guesser is
                    // deterministic and free.
                    groceryCategory: GroceryCategoryGuesser.category(for: item.name)
                )
            }

        let steps = decoded.steps
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { step in
                ImportedStep(
                    text: step.text,
                    // Trust a stated duration, but fall back to reading the
                    // step text ourselves when the model left it out.
                    durationSeconds: step.durationSeconds ?? DurationParser.seconds(inStepText: step.text)
                )
            }

        return ImportedRecipe(
            title: decoded.title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: decoded.summary,
            imageURL: nil,
            servings: decoded.servings.map { max(1, $0) },
            prepMinutes: decoded.prepMinutes,
            cookMinutes: decoded.cookMinutes,
            ingredients: ingredients,
            steps: steps,
            tags: Array(decoded.tags.map { $0.lowercased() }.prefix(8)),
            sourceName: sourceName,
            sourceURL: sourceURL,
            confidence: min(max(decoded.confidence, 0), confidenceCeiling)
        )
    }

    /// The model is asked for the normalised set, but occasionally returns a
    /// spelling from the source anyway.
    private nonisolated static func normalisedUnit(_ unit: String?) -> String? {
        guard let unit = unit?.trimmingCharacters(in: .whitespaces).lowercased(), !unit.isEmpty else {
            return nil
        }

        let allowed: Set<String> = [
            "g", "kg", "ml", "l", "tsp", "tbsp", "cup",
            "oz", "lb", "clove", "piece", "pinch", "can", "bunch"
        ]

        if allowed.contains(unit) { return unit }

        // Reuse the line parser's alias table by round-tripping a fake line.
        let probe = IngredientLineParser.parse("1 \(unit) x", order: 0)
        return probe.unit
    }

    /// Keeps a page's worth of text inside the model's useful window, taking
    /// from the start where recipes almost always are.
    private nonisolated static func cap(_ text: String, at limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit))
    }
}
