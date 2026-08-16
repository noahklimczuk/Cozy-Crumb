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

    /// A video post (YouTube, Shorts, etc.), which Gemini watches/transcribes directly.
    nonisolated static func extractionFromVideo(
        title: String?,
        author: String?,
        description: String?
    ) -> String {
        var context = "Watch and transcribe this cooking video to extract the complete recipe."

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

        CRITICAL INSTRUCTIONS FOR VIDEO TRANSCRIPTION:
        1. Transcribe all spoken audio dialogue, voiceover narration, and spoken measurements in the video.
        2. Read all on-screen overlay text, titles, lists, and ingredient overlays in the video.
        3. Observe visual kitchen actions (e.g. chopping, simmering, combining ingredients in a bowl).
        4. If the video description is empty, incomplete, or lacks a recipe, rely fully on the transcribed spoken audio and visual steps to build the complete recipe.
        5. When the description and spoken/visual content disagree, trust the video audio and visuals.
        6. Do not omit ingredients or steps just because they were only spoken out loud or shown on screen.
        """
    }

    /// The kind of media we managed to get hold of, which changes what the
    /// model can be expected to notice.
    enum MediaKind: Sendable {
        case video
        case frames
        case images

        nonisolated var description: String {
            switch self {
            case .video:
                "the video from the post"
            case .frames:
                "still frames taken at intervals through the post's video"
            case .images:
                "the images from the post"
            }
        }
    }

    /// A TikTok or Reel whose caption never contained the recipe, sent as media
    /// rather than text. This is the common case for short-form cooking video:
    /// the caption is a hook, and the recipe is spoken aloud or burned into the
    /// frames as an ingredient list.
    nonisolated static func extractionFromMedia(
        kind: MediaKind,
        platform: String,
        title: String?,
        author: String?,
        caption: String?
    ) -> String {
        var context = "Attached is \(kind.description), from \(platform)."

        if let author, !author.isEmpty {
            context += "\nPosted by: \(author)"
        }
        if let title, !title.isEmpty {
            context += "\nTitled: \(title)"
        }
        if let caption, !caption.isEmpty {
            context += "\n\nThe caption reads:\n\(caption)"
        } else {
            context += "\n\nThe post has no useful caption — everything you need is in the media."
        }

        var instructions = """
        \(context)

        The recipe was never written out in the caption, so read it off the
        media itself:

        1. Read every piece of on-screen text: ingredient overlays, quantity
           captions, step titles, the recipe card some posters put at the end.
        2. Watch what the cook actually does, in order, and write the method
           from it.
        3. Where a quantity is only ever shown on screen, use it. Where it is
           genuinely never given, leave quantity null rather than inventing a
           number.
        4. Ignore the hook, the intro, the outro, and anything about following
           or commenting.
        """

        switch kind {
        case .video:
            instructions += """


            5. Listen to the audio as well as watching. Narrated measurements
               ("about half a cup of cream") count, and are often the only
               place a quantity is given.
            """

        case .frames:
            instructions += """


            5. These are stills, so the method between them is missing. Write
               the steps you can actually see, and don't pad the gaps with
               invented ones.
            """

        case .images:
            break
        }

        instructions += """


        If the media turns out not to show a recipe being made, return found
        false rather than assembling a plausible one.
        """

        return instructions
    }

    // MARK: - Sous Chef

    /// The assistant's whole character and its rules of engagement.
    ///
    /// The instructions that matter most are the ones about *their* cookbook.
    /// A model asked "what should I cook tonight?" will happily invent a
    /// recipe; the entire value of asking this app instead of a search engine
    /// is that the answer comes from the food they've actually saved and the
    /// ingredients they've actually got.
    nonisolated static func sousChefSystem(context: String, today: Date) -> String {
        """
        You are the Sous Chef inside Cozy Crumb, a personal cookbook app. You
        are warm, brief and practical — a friend who cooks, not a food writer.
        Two or three sentences is usually plenty. No preamble, no "great
        question", no bullet lists unless the answer genuinely is a list.

        Today is \(today.formatted(.dateTime.weekday(.wide).day().month(.wide))).

        WHAT YOU KNOW

        Everything below is this user's real data, read fresh from their phone
        just now. Trust it over anything you remember from earlier in the
        conversation.

        \(context)

        HOW TO ANSWER

        - Suggest their saved recipes by name wherever one fits. Only reach for
          something they haven't saved when nothing they have will do, and say
          so when you do.
        - "What can I make?" means from what's in their pantry. Say which
          ingredients they'd still need, and don't pretend they have something
          they don't.
        - Scaling, swapping and timing questions are yours to answer directly.
        - If you genuinely don't know, say so in one line. Never invent a
          quantity, a temperature or a cooking time to fill a gap.
        - Their measurement preference is in the data above — write amounts the
          way they read them.

        DOING THINGS

        You can add to their shopping list and put meals on their plan by
        calling the functions provided. Rules:

        - Only act when they've asked you to, or agreed to an offer. "What
          should I cook?" is a question, not permission to plan anything.
        - Doing several related things at once is fine when they asked for it —
          "plan three dinners" is three calls.
        - After acting, say what you did in a few words. The app shows its own
          receipt, so don't list every item back.
        - If a function tells you it couldn't find something, tell the user
          plainly. Never claim something was added or planned when it wasn't.
        """
    }

    /// Shown to the model when the user pastes a caption by hand.
    nonisolated static let pastedCaptionHint = """
    The user copied this text themselves from a post the app could not read.
    It may include hashtags, mentions and emoji — ignore those unless they
    carry recipe information.
    """
}
