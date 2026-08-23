//
//  FactExtractor.swift
//  Cozy Crumb
//
//  §7.4. Pulls durable facts out of a conversation, in the background.
//
//  Two things shape this. The first is that extraction usually finds nothing
//  — most turns are "what's for dinner", and the prompt says outright not to
//  manufacture facts to seem useful. The second is that the API key belongs
//  to the user, so an extraction call after every single turn roughly doubles
//  what the feature costs them in exchange for a lot of empty arrays.
//
//  So there is a Swift gate in front of the call. It looks for the shapes
//  durable statements actually take — "I'm allergic to", "we don't eat", "my
//  partner", "I've got an air fryer" — and only spends a request when one
//  turns up. It will miss an unusual phrasing now and then; the alternative
//  is billing someone for a hundred requests that return nothing.
//

import Foundation

nonisolated struct ExtractedFact: Sendable, Equatable, Decodable {
    var statement: String
    var category: String
    var confidence: Double
    var sourceExcerpt: String?

    var factCategory: FactCategory {
        FactCategory(rawValue: category.lowercased()) ?? .preference
    }
}

nonisolated struct ExtractedFacts: Sendable, Decodable {
    var facts: [ExtractedFact]
}

nonisolated enum FactExtractor {

    // MARK: - The gate

    /// Phrases that mean someone is telling you something lasting.
    nonisolated static let triggers: [String] = [
        "allergic", "allergy", "intolerant", "intolerance", "coeliac", "celiac",
        "i'm vegan", "i am vegan", "i'm vegetarian", "i am vegetarian",
        "vegetarian", "vegan", "pescatarian", "halal", "kosher",
        "i don't eat", "i dont eat", "we don't eat", "we dont eat",
        "i can't eat", "i cant eat", "can't have", "cant have",
        "i hate", "i love", "i can't stand", "i cant stand", "not a fan of",
        "my partner", "my husband", "my wife", "my kids", "my son",
        "my daughter", "my flatmate", "my roommate", "we're a household",
        "i live alone", "cooking for",
        "i have an", "i have a", "i've got an", "i've got a", "i own",
        "no dishwasher", "no oven", "my kitchen", "air fryer", "stand mixer",
        "slow cooker", "instant pot", "i work", "every week", "on weeknights",
        "i always", "i never", "i usually", "i prefer", "i tend to",
        "beginner", "not confident", "i'm new to"
    ]

    /// Is this worth spending a request on?
    nonisolated static func isWorthExtracting(from message: String) -> Bool {
        let text = message.lowercased().replacingOccurrences(of: "’", with: "'")
        guard text.count >= 12 else { return false }
        return triggers.contains { text.contains($0) }
    }

    // MARK: - The prompt

    nonisolated static let schema = GeminiSchema.record(
        [
            ("facts", .list(of: .record(
                [
                    ("statement", .text("The fact, written in the third person: \"Partner doesn't eat mushrooms\"")),
                    ("category", .text("One of: allergy, dietary, equipment, household, preference, schedule, skill")),
                    ("confidence", .decimal("0–1, honestly")),
                    ("sourceExcerpt", .text("The exact phrase they used", nullable: true))
                ],
                required: ["statement", "category", "confidence"]
            )))
        ],
        required: ["facts"]
    )

    nonisolated static let systemInstruction = """
    Read this exchange between a cook and their kitchen assistant. Extract
    only DURABLE facts about the cook — things likely to still be true in a
    month.

    Extract: allergies, dietary restrictions, household composition, equipment
    they own or lack, strong lasting likes/dislikes, skill level, recurring
    schedule constraints.

    Do NOT extract: what they have in the fridge today, one-off cravings, what
    they're making tonight, anything about a single meal, anything the
    assistant said (only what the cook stated).

    For each fact give a confidence 0–1 and the exact phrase they used.
    If there are no durable facts, return an empty array. That is the common
    case — do not manufacture facts to seem useful.
    """

    /// The user turns, plus the facts already known so the model does not
    /// hand back things the app has had for months.
    nonisolated static func prompt(exchange: [String], existingFacts: [String]) -> String {
        var text = "EXCHANGE:\n" + exchange.joined(separator: "\n")

        if !existingFacts.isEmpty {
            text += """


            ALREADY KNOWN — do not return any of these again:
            \(existingFacts.map { "- \($0)" }.joined(separator: "\n"))
            """
        }

        return text
    }

    // MARK: - The call

    /// Runs the extraction. Returns an empty array on any failure — a
    /// background nicety must never surface an error to someone who was just
    /// asking about dinner.
    static func extract(
        exchange: [String],
        existingFacts: [String],
        client: GeminiClient,
        model: GeminiModel = .speedy
    ) async -> [ExtractedFact] {
        guard !exchange.isEmpty else { return [] }

        let result = await client.generate(
            model: model,
            systemInstruction: systemInstruction,
            parts: [.text(prompt(exchange: exchange, existingFacts: existingFacts))],
            schema: schema,
            temperature: 0.1,
            maxOutputTokens: 1024,
            // §7.4 says "minimal thinking". LOW is the lowest setting this
            // client has a verified value for, so it is what gets used —
            // inventing an "OFF" that may or may not exist in the API would
            // fail the request rather than save a few tokens.
            thinking: .low
        )

        guard case .success(let json) = result,
              let data = GeminiClient.stripJSONFences(json).data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ExtractedFacts.self, from: data) else {
            return []
        }

        return decoded.facts.filter { !$0.statement.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
