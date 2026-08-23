//
//  WeeklyReflection.swift
//  Cozy Crumb
//
//  §7.5. One short, warm observation a week.
//
//  Cheap, optional, and the highest ratio of perceived intelligence to actual
//  work in the whole feature. All the learning in S1–S4 is invisible by
//  design — it quietly improves a ranking nobody sees the internals of. This
//  makes a week of it visible in one sentence: "you made three one-pan things
//  this week — want me to put those together?"
//
//  Constraints that keep it from becoming a nuisance:
//
//    * Once a week, and only when there is something to observe. Fewer than
//      two cooks in a week is not a pattern, it is a quiet week, and
//      remarking on it would be the app noticing that you didn't cook.
//    * It is a card, never a notification.
//    * The observation is generated from the cook log alone. It has no
//      business being a second opinion on their taste profile.
//

import Foundation
import SwiftData
import os

nonisolated struct WeeklyReflectionText: Sendable, Decodable {
    var observation: String
    /// An optional light offer — "want me to make a collection of those?"
    var offer: String?
}

@MainActor
enum WeeklyReflection {

    static let interval: TimeInterval = 7 * 24 * 60 * 60

    /// Below this it is a quiet week rather than a pattern.
    static let minimumCooks = 2

    nonisolated static let schema = GeminiSchema.record(
        [
            ("observation", .text("One warm sentence about their week's cooking")),
            ("offer", .text("An optional light offer, or null", nullable: true))
        ],
        required: ["observation"]
    )

    nonisolated static let systemInstruction = """
    You are the Sous Chef in a cozy cookbook app, looking back at what someone
    cooked this week.

    Write ONE short, warm observation — the kind a friend who cooks would
    make. Notice a pattern if there is one: a run of quick things, a weekend
    project, a cuisine they kept coming back to, a night they clearly could
    not be bothered.

    Optionally add one light offer that follows from it, like building a small
    collection or planning something similar. Only if it genuinely follows.

    Do not flatter. Do not congratulate them on cooking. Do not give advice
    they did not ask for. If the week was unremarkable, say something small
    and true rather than manufacturing significance.
    """

    // MARK: - Whether to run

    static func isDue(defaults: UserDefaults = .standard, now: Date = .now) -> Bool {
        guard let last = defaults.object(forKey: CozyDefaultsKey.lastWeeklyReflectionAt) as? Date else {
            return true
        }
        return now.timeIntervalSince(last) >= interval
    }

    /// What was cooked in the last week, as lines for the prompt.
    static func weekSummary(in modelContext: ModelContext, now: Date = .now) -> [String] {
        let cutoff = now.addingTimeInterval(-interval)
        let logs = (try? modelContext.fetch(FetchDescriptor<CookLog>())) ?? []

        return logs
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
            .compactMap { log -> String? in
                guard let recipe = log.recipe else { return nil }

                var line = "\(log.date.formatted(.dateTime.weekday(.abbreviated))): \(recipe.title)"
                if let minutes = recipe.totalMinutes { line += " (\(minutes) min)" }
                if let cuisine = recipe.inferredCuisine { line += " [\(cuisine)]" }
                if let rating = log.rating { line += " ★\(rating)" }
                if !recipe.tags.isEmpty {
                    line += " — " + recipe.tags.prefix(3).joined(separator: ", ")
                }
                return line
            }
    }

    // MARK: - Running it

    /// Returns the observation, or nil when there is nothing worth saying.
    static func run(
        in modelContext: ModelContext,
        client: GeminiClient,
        defaults: UserDefaults = .standard,
        now: Date = .now
    ) async -> WeeklyReflectionText? {
        guard isDue(defaults: defaults, now: now) else { return nil }

        let summary = weekSummary(in: modelContext, now: now)
        guard summary.count >= minimumCooks else {
            // Nothing to remark on. The clock is still reset, so a quiet week
            // does not mean being asked again tomorrow.
            defaults.set(now, forKey: CozyDefaultsKey.lastWeeklyReflectionAt)
            return nil
        }

        let result = await client.generate(
            model: .speedy,
            systemInstruction: systemInstruction,
            parts: [.text("THIS WEEK:\n" + summary.joined(separator: "\n"))],
            schema: schema,
            temperature: 0.7,
            maxOutputTokens: 512
        )

        defaults.set(now, forKey: CozyDefaultsKey.lastWeeklyReflectionAt)

        guard case .success(let json) = result,
              let data = GeminiClient.stripJSONFences(json).data(using: .utf8),
              let decoded = try? JSONDecoder().decode(WeeklyReflectionText.self, from: data),
              !decoded.observation.trimmingCharacters(in: .whitespaces).isEmpty else {
            Log.ai.info("Weekly reflection produced nothing usable")
            return nil
        }

        return decoded
    }
}
