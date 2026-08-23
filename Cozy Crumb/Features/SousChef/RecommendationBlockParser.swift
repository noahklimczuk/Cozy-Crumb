//
//  RecommendationBlockParser.swift
//  Cozy Crumb
//
//  Reads the fenced JSON block §7.1 asks the Sous Chef to end with, and takes
//  it back out of what the user sees.
//
//  The stripping is the part that matters. A trailing ```json block is an
//  instruction to the app, not a sentence, and leaving it in the transcript
//  turns a warm reply into a warm reply followed by machine output. So the
//  parser returns the prose and the recommendations separately, and the view
//  only ever renders the prose.
//
//  It is also deliberately suspicious of what comes back. A recipe id that
//  was not in the candidates the model was given is dropped rather than shown
//  — §7.1 says only to quote ids from RANKED CANDIDATES, and a card built
//  from an invented id would either crash on a lookup or, worse, quietly
//  point at the wrong recipe. The prose still reaches the user either way;
//  only the card disappears.
//

import Foundation

nonisolated struct SousChefRecommendation: Sendable, Equatable, Identifiable {
    var recipeID: UUID
    /// The model's sentence about why it picked this.
    var why: String
    /// The app's own reasoning, from the score. Shown behind "Why this?" so
    /// the two are never confused for each other.
    var reasoning: [String]

    nonisolated var id: UUID { recipeID }

    nonisolated init(recipeID: UUID, why: String, reasoning: [String] = []) {
        self.recipeID = recipeID
        self.why = why
        self.reasoning = reasoning
    }
}

nonisolated enum RecommendationBlockParser {

    nonisolated struct Result: Sendable, Equatable {
        /// What to show. The block has already been removed.
        var prose: String
        var recommendations: [SousChefRecommendation]
    }

    /// The wire shape from §7.1.
    private nonisolated struct Payload: Decodable {
        struct Item: Decodable {
            var recipeId: String
            var why: String?
        }
        var recommendations: [Item]
    }

    /// Splits a reply into what to say and what to show.
    ///
    /// `knownRecipeIDs` is the set the model was actually offered. Pass it
    /// whenever it is available; an empty set means "don't check", which is
    /// only right in tests.
    nonisolated static func parse(
        _ reply: String,
        knownRecipeIDs: Set<UUID> = [],
        reasoning: [UUID: [String]] = [:]
    ) -> Result {
        guard let fence = lastJSONFence(in: reply) else {
            return Result(prose: reply.trimmingCharacters(in: .whitespacesAndNewlines), recommendations: [])
        }

        let prose = reply
            .replacingCharacters(in: fence.range, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = fence.json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            // Malformed JSON is the model's problem, not the user's. The
            // prose is still worth reading, so it is shown without cards
            // rather than the whole turn being treated as a failure.
            return Result(prose: prose, recommendations: [])
        }

        var seen: Set<UUID> = []
        var recommendations: [SousChefRecommendation] = []

        for item in payload.recommendations {
            guard let id = UUID(uuidString: item.recipeId.trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
            guard knownRecipeIDs.isEmpty || knownRecipeIDs.contains(id) else { continue }
            guard seen.insert(id).inserted else { continue }

            recommendations.append(SousChefRecommendation(
                recipeID: id,
                why: (item.why ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                reasoning: reasoning[id] ?? []
            ))
        }

        return Result(prose: prose, recommendations: recommendations)
    }

    /// The last fenced block in the reply, and where it sits.
    ///
    /// The last one rather than the first: a reply that quotes a snippet
    /// earlier on should still have its own trailing block read, and §7.1
    /// puts the real one at the end with nothing after it.
    private nonisolated static func lastJSONFence(in text: String) -> (json: String, range: Range<String.Index>)? {
        let openings = ["```json", "```JSON", "```"]

        for opening in openings {
            guard let start = text.range(of: opening, options: .backwards) else { continue }
            guard let end = text.range(of: "```", range: start.upperBound..<text.endIndex) else { continue }

            let body = String(text[start.upperBound..<end.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard body.hasPrefix("{") else { continue }
            return (body, start.lowerBound..<end.upperBound)
        }

        return nil
    }
}
