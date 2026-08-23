//
//  CookFactStore.swift
//  Cozy Crumb
//
//  Reading, writing and deduplicating what the app knows in words.
//
//  The interesting parts are all about not being wrong twice:
//
//    * Deduplication, so a person who mentions their partner's mushroom
//      problem three times ends up with one fact rather than three.
//    * Contradiction detection, so when they say the opposite of something
//      stored, the app notices and asks instead of silently keeping both.
//    * A cap, so the list cannot grow until it is the whole prompt.
//
//  There are no embeddings here. `NLEmbedding` exists on device but is weak
//  at this, and the alternative is cheaper and more predictable: normalised
//  token overlap in Swift, plus handing the extractor the facts it already
//  has and telling it not to repeat them. Two chances to catch a duplicate,
//  neither of them a guess about sentence vectors.
//

import Foundation
import SwiftData
import os

@MainActor
enum CookFactStore {

    /// §5's ceiling. Past this the prompt is mostly facts.
    static let maximumActiveFacts = 60

    /// How alike two statements have to be to count as the same fact.
    nonisolated static let duplicateThreshold = 0.6

    // MARK: - Reading

    static func active(in modelContext: ModelContext) -> [CookFact] {
        let facts = (try? modelContext.fetch(FetchDescriptor<CookFact>())) ?? []
        return facts.filter(\.isActive)
    }

    /// Facts awaiting a yes or no from the user. Allergies, mostly.
    static func pendingConfirmation(in modelContext: ModelContext) -> [CookFact] {
        active(in: modelContext)
            .filter(\.needsConfirmation)
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// What goes into the digest's FACTS section. Unconfirmed facts are
    /// included but only as things the model may mention — they are excluded
    /// from the hard filters until someone says yes.
    static func digestFacts(in modelContext: ModelContext) -> [DigestFact] {
        active(in: modelContext)
            .filter { !$0.needsConfirmation }
            .sorted { lhs, rhs in
                if lhs.category.isSafetyRelevant != rhs.category.isSafetyRelevant {
                    return lhs.category.isSafetyRelevant
                }
                return lhs.createdAt < rhs.createdAt
            }
            .map(\.digestFact)
    }

    /// Allergens that are actually enforced. Unconfirmed ones are deliberately
    /// absent — an allergy nobody has agreed to is not yet a filter.
    static func allergens(in modelContext: ModelContext) -> Set<String> {
        Set(
            active(in: modelContext)
                .filter { $0.category == .allergy && $0.isEnforceable }
                .flatMap { allergenNames(in: $0.statement) }
        )
    }

    static func diets(in modelContext: ModelContext) -> Set<DietaryRule> {
        var rules: Set<DietaryRule> = []

        for fact in active(in: modelContext) where fact.category == .dietary && fact.isEnforceable {
            rules.formUnion(ConversationConstraints.diets(in: fact.statement))
        }

        return rules
    }

    /// Pulls the food out of "allergic to shellfish" or "peanut allergy".
    ///
    /// Matched on word boundaries. A plain substring search reads "buckwheat"
    /// as wheat and therefore as gluten — which is wrong twice over: buckwheat
    /// is gluten-free, so it would strip every bread and pasta from someone
    /// who can eat them, while still not filtering the buckwheat.
    nonisolated static func allergenNames(in statement: String) -> [String] {
        let text = statement.lowercased()
        let words = Set(
            text
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .map(IngredientCanonicalizer.singularised)
        )

        func mentions(_ phrase: String) -> Bool {
            let parts = phrase.components(separatedBy: " ").filter { !$0.isEmpty }
            // The words were singularised, so the needle has to be too, or
            // the alias "nuts" stops matching the sentence "allergic to nuts".
            guard parts.count > 1 else {
                return words.contains(IngredientCanonicalizer.singularised(phrase))
            }
            // Multi-word groups ("tree nut") still match as a phrase.
            return text.contains(phrase)
        }

        var found: [String] = []

        for group in AllergenIndex.groups.keys where mentions(group) {
            found.append(group)
        }
        for (alias, group) in AllergenIndex.aliases where mentions(alias) {
            found.append(group)
        }

        // Nothing recognised, but the sentence still says allergy. Keep the
        // nouns rather than enforcing nothing at all.
        if found.isEmpty {
            let stopWords: Set<String> = [
                "allergic", "allergy", "to", "a", "an", "the", "i'm", "im",
                "i", "am", "have", "has", "is", "and", "or", "severe", "mild",
                "intolerant", "intolerance", "can't", "cant", "eat"
            ]
            found = text
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !stopWords.contains($0) }
                .map(IngredientCanonicalizer.canonical)
        }

        return found.filter { !$0.isEmpty }
    }

    // MARK: - Writing

    /// Adds a fact unless one like it is already there.
    ///
    /// Returns the fact that ended up representing it — either the new one or
    /// the existing near-duplicate, whose confidence is nudged up by having
    /// been said again.
    @discardableResult
    static func add(
        statement: String,
        category: FactCategory,
        confidence: Double,
        source: FactSource,
        excerpt: String?,
        in modelContext: ModelContext,
        now: Date = .now
    ) -> CookFact? {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let existing = active(in: modelContext)

        if let duplicate = existing.first(where: {
            FactSimilarity.areSame($0.statement, trimmed) && $0.category == category
        }) {
            // Said again. That is mild evidence it is true, but it never
            // rewrites a fact the user has edited.
            if !duplicate.isUserEdited {
                duplicate.confidence = min(1, max(duplicate.confidence, confidence) + 0.05)
                duplicate.lastConfirmedAt = now
            }
            return duplicate
        }

        let fact = CookFact(
            statement: trimmed,
            category: category,
            confidence: confidence,
            source: source,
            sourceExcerpt: excerpt,
            createdAt: now,
            // §5: an allergy or dietary rule from an inference is never
            // silently applied. It waits for a yes.
            needsConfirmation: category.isSafetyRelevant && source != .userStated
        )

        modelContext.insert(fact)
        prune(in: modelContext)
        save(in: modelContext)

        return fact
    }

    /// The user said yes on a confirmation card.
    static func confirm(_ fact: CookFact, in modelContext: ModelContext, now: Date = .now) {
        fact.needsConfirmation = false
        fact.isUserEdited = true
        fact.source = .userStated
        fact.confidence = 1
        fact.lastConfirmedAt = now
        save(in: modelContext)
    }

    /// The user said no. Deactivated rather than deleted, so the extractor
    /// does not cheerfully rediscover it next week.
    static func reject(_ fact: CookFact, in modelContext: ModelContext) {
        fact.isActive = false
        fact.isUserEdited = true
        save(in: modelContext)
    }

    static func update(_ fact: CookFact, statement: String, in modelContext: ModelContext, now: Date = .now) {
        fact.statement = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        fact.isUserEdited = true
        fact.source = .userStated
        fact.confidence = 1
        fact.lastConfirmedAt = now
        save(in: modelContext)
    }

    static func forget(_ fact: CookFact, in modelContext: ModelContext) {
        modelContext.delete(fact)
        save(in: modelContext)
    }

    // MARK: - Contradictions

    /// A stored fact that the new one appears to disagree with.
    ///
    /// This is what makes the app feel like it is paying attention. Noticing
    /// out loud — "I had you down as not a fan of mushrooms, has that
    /// changed?" — does more for the sense of being learned about than any
    /// amount of silent scoring, and it costs one comparison.
    static func contradiction(
        of statement: String,
        category: FactCategory,
        in modelContext: ModelContext
    ) -> CookFact? {
        active(in: modelContext).first { fact in
            fact.category == category && FactSimilarity.contradict(fact.statement, statement)
        }
    }

    // MARK: - Housekeeping

    /// Drops the weakest facts once there are too many. Lowest confidence
    /// first, then the oldest thing nobody has confirmed. Anything the user
    /// edited is untouchable.
    static func prune(in modelContext: ModelContext, now: Date = .now) {
        let facts = active(in: modelContext)
        guard facts.count > maximumActiveFacts else { return }

        let expendable = facts
            .filter { !$0.isUserEdited && !$0.category.isSafetyRelevant }
            .sorted { lhs, rhs in
                if lhs.confidence != rhs.confidence { return lhs.confidence < rhs.confidence }
                return (lhs.lastConfirmedAt ?? lhs.createdAt) < (rhs.lastConfirmedAt ?? rhs.createdAt)
            }

        for fact in expendable.prefix(facts.count - maximumActiveFacts) {
            modelContext.delete(fact)
        }
    }

    private static func save(in modelContext: ModelContext) {
        do {
            try modelContext.save()
        } catch {
            Log.data.error("Could not save a cook fact: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Similarity

/// Comparing two statements without embeddings.
///
/// Token overlap on content words, which is crude and predictable. Crude is
/// acceptable because there is a second line of defence: the extraction
/// prompt is shown the existing facts and told not to repeat them, so this
/// only has to catch the near-identical rephrasings that slip through.
nonisolated enum FactSimilarity {

    nonisolated static let stopWords: Set<String> = [
        "a", "an", "the", "is", "are", "was", "were", "be", "been", "am",
        "i", "me", "my", "we", "our", "they", "them", "their", "he", "she",
        "it", "to", "of", "in", "on", "at", "for", "with", "and", "or",
        "but", "so", "that", "this", "these", "those", "have", "has", "had",
        "do", "does", "did", "will", "would", "can", "could", "very", "really"
    ]

    nonisolated static func tokens(_ statement: String) -> Set<String> {
        Set(
            statement
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !stopWords.contains($0) }
                .map(IngredientCanonicalizer.singularised)
        )
    }

    /// Jaccard overlap, 0–1.
    nonisolated static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let left = tokens(lhs)
        let right = tokens(rhs)

        guard !left.isEmpty, !right.isEmpty else { return 0 }

        let shared = left.intersection(right).count
        let total = left.union(right).count

        return Double(shared) / Double(total)
    }

    nonisolated static func areSame(_ lhs: String, _ rhs: String) -> Bool {
        similarity(lhs, rhs) >= CookFactStore.duplicateThreshold
    }

    /// Words that flip the meaning of a sentence.
    nonisolated static let negations: Set<String> = [
        "not", "no", "never", "doesn't", "does", "don't", "won't", "can't",
        "cannot", "dislike", "dislikes", "hate", "hates", "avoid", "avoids",
        "without", "off", "stopped", "anymore"
    ]

    nonisolated static func isNegated(_ statement: String) -> Bool {
        let words = Set(
            statement
                .lowercased()
                .replacingOccurrences(of: "’", with: "'")
                .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
        )
        return !words.isDisjoint(with: negations)
    }

    /// Two statements about the same subject that point opposite ways.
    ///
    /// Requires real overlap first, so "doesn't eat mushrooms" and "loves
    /// mushrooms" contradict, while "doesn't eat mushrooms" and "loves
    /// anchovies" merely differ.
    nonisolated static func contradict(_ lhs: String, _ rhs: String) -> Bool {
        guard similarity(lhs, rhs) >= 0.3 else { return false }
        return isNegated(lhs) != isNegated(rhs)
    }
}
