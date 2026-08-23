//
//  RankedCandidatesBlock.swift
//  Cozy Crumb
//
//  §7.2. The engine's output, rendered for the prompt.
//
//  This block is written by Swift and never by the model. That is the whole
//  arrangement: the scoring happened in code, deterministically, over the
//  user's real data, and the model's job is to pick two or three of these and
//  say why in a sentence each — not to re-rank them and not to invent
//  alternatives.
//
//  Each line carries its reason code, and the reason codes are honest labels
//  rather than sales copy. A stretch is announced as a stretch so the Sous
//  Chef can say "a bit different from your usual" instead of pretending it
//  knew all along that this person wanted a tagine.
//

import Foundation

nonisolated enum RankedCandidatesBlock {

    /// How many candidates the model is given to choose from. Enough for a
    /// real choice, few enough that it does not start summarising the list
    /// back to the user.
    nonisolated static let limit = 8

    nonisolated static func render(_ candidates: [ScoredRecipe], now: Date = .now) -> String {
        guard !candidates.isEmpty else {
            return """
            === RANKED CANDIDATES ===
            none — nothing in their cookbook passes their constraints for this question.
            Say so plainly and offer to come up with something new.
            """
        }

        var lines = ["=== RANKED CANDIDATES ==="]

        for (index, candidate) in candidates.prefix(limit).enumerated() {
            lines.append(contentsOf: describe(candidate, position: index + 1, now: now))
        }

        return lines.joined(separator: "\n")
    }

    nonisolated static func describe(
        _ candidate: ScoredRecipe,
        position: Int,
        now: Date
    ) -> [String] {
        let recipe = candidate.recipe

        var lines = [
            String(
                format: "%d. %@ | %@ | %.2f | %@",
                position,
                recipe.id.uuidString,
                recipe.title,
                candidate.total,
                candidate.reason.rawValue
            )
        ]

        // Why it is a stretch, in the terms the prompt is told to use.
        if candidate.reason == .stretch {
            lines.append("   " + stretchNote(for: candidate))
        }

        lines.append("   " + pantryLine(for: candidate))
        lines.append("   " + factsLine(for: candidate, now: now))

        return lines
    }

    private nonisolated static func stretchNote(for candidate: ScoredRecipe) -> String {
        var parts: [String] = []

        if let cuisine = candidate.recipe.cuisine {
            parts.append("\(cuisine), which isn't their usual")
        }
        if !candidate.recipe.techniques.isEmpty {
            parts.append("needs " + candidate.recipe.techniques.sorted().joined(separator: ", "))
        }

        return parts.isEmpty ? "outside their usual" : parts.joined(separator: " · ")
    }

    private nonisolated static func pantryLine(for candidate: ScoredRecipe) -> String {
        guard !candidate.missing.isEmpty else {
            return "have: everything · missing: none"
        }

        let missing = candidate.missing.prefix(4).map { item -> String in
            if let substitute = item.substitute {
                return "\(item.name) (sub: \(substitute))"
            }
            return item.name
        }

        let total = candidate.have.count + candidate.missing.count
        return "have: \(candidate.have.count)/\(total) · missing: " + missing.joined(separator: ", ")
    }

    private nonisolated static func factsLine(for candidate: ScoredRecipe, now: Date) -> String {
        var parts: [String] = []

        if let minutes = candidate.recipe.totalMinutes {
            parts.append("\(minutes) min")
        }

        if candidate.recipe.cookCount > 0 {
            parts.append("cooked \(candidate.recipe.cookCount)×")
        } else {
            parts.append("never cooked")
        }

        if let lastCookedAt = candidate.recipe.lastCookedAt {
            let days = Int(now.timeIntervalSince(lastCookedAt) / 86_400)
            parts.append(days <= 0 ? "made today" : "last made \(days) days ago")
        }

        return parts.joined(separator: " · ")
    }
}
