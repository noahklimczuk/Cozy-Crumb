//
//  Prompts.swift
//  Cozy Crumb
//
//  Every prompt template lives here. Never build one inline in view code.
//

import Foundation

enum Prompts {

    /// System instruction for all recipe extraction, whatever the source.
    nonisolated static let extractionSystem = """
    You pull structured recipes out of messy text for a personal cookbook app.

    The response schema constrains your output, so spend your attention on
    judgement rather than formatting.

    Rules:
    - Preserve every ingredient line's original wording in rawText, always.
    - Normalise units to one of: g, kg, ml, l, tsp, tbsp, cup, oz, lb, clove,
      piece, pinch, can, bunch. If a unit does not map cleanly, leave it null
      and keep the full text in rawText.
    - Convert fractions and unicode fractions to decimals in quantity.
    - "For the sauce:" style lines are ingredients with isSectionHeader true.
    - durationSeconds only when a step states an explicit time. Never invent
      a time, a temperature, or a step that was not there.
    - Strip ad copy, "jump to recipe" links, life stories and comment threads.
    - If there is no recipe here, return found false with confidence 0 and
      empty lists. Do not invent a plausible recipe to fill the shape.
    - Set confidence honestly. Below 0.6 means you had to guess at structure.
    """

    /// Web page or pasted text.
    nonisolated static func extractionFromText(_ text: String) -> String {
        """
        Extract a structured recipe from the text below. It may be a scraped
        web page, a social media caption, or something a user typed.

        TEXT:
        \(text)
        """
    }

    /// A social caption, where the recipe is usually terse and unpunctuated.
    nonisolated static func extractionFromCaption(
        caption: String,
        platform: String,
        author: String?
    ) -> String {
        var context = "This is a caption from \(platform)."
        if let author, !author.isEmpty {
            context += " Posted by \(author)."
        }

        return """
        \(context)

        Social captions are written for people, not parsers. Expect emoji
        bullets, missing punctuation, ingredients and method run together, and
        quantities written loosely ("a knob of butter", "handful of spinach").
        Read it the way a cook would.

        If quantities are genuinely absent, leave quantity null rather than
        guessing a number — the user can fill it in. Keep the poster's own
        phrasing in rawText.

        If the caption is only a description of the dish with no actual recipe,
        return found false rather than inventing one.

        CAPTION:
        \(caption)
        """
    }

    /// A YouTube video, which Gemini watches directly.
    nonisolated static func extractionFromVideo(
        title: String?,
        author: String?,
        description: String?
    ) -> String {
        var context = "Watch this cooking video and write down the recipe."

        if let title, !title.isEmpty {
            context += "\n\nThe video is titled: \(title)"
        }
        if let author, !author.isEmpty {
            context += "\nPosted by: \(author)"
        }
        if let description, !description.isEmpty {
            context += "\n\nThe description says:\n\(description)"
        }

        return """
        \(context)

        Use everything you can see and hear: on-screen text, the narration,
        what actually goes into the bowl, and the description above. When the
        description and the video disagree, trust the video — creators often
        paste an old or approximate list.

        Quantities are often only spoken or shown on screen briefly. Capture
        them where you can and leave them null where you genuinely cannot,
        rather than estimating.

        Write the steps in the order they happen in the video.
        """
    }

    /// Shown to the model when the user pastes a caption by hand.
    nonisolated static let pastedCaptionHint = """
    The user copied this text themselves from a post the app could not read.
    It may include hashtags, mentions and emoji — ignore those unless they
    carry recipe information.
    """
}
