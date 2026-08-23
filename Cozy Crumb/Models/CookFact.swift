//
//  CookFact.swift
//  Cozy Crumb
//
//  Something durable about the cook, in words.
//
//  The taste profile is arithmetic over behaviour. This is the other half:
//  the things that are simply true and that no amount of cooking would ever
//  reveal. Nobody's stir-fry history says their partner won't eat mushrooms,
//  or that there is no dishwasher, or that hard cheeses are fine but milk is
//  not.
//
//  Everything here carries where it came from. `source` and `sourceExcerpt`
//  are not bookkeeping — they are what lets the Taste Profile screen say
//  "because you said: …" instead of asking someone to take the app's word for
//  it, and what makes a wrong fact correctable rather than mysterious.
//
//  `isUserEdited` is a lock. Once a person has touched a fact, no extraction
//  overwrites it. Getting that wrong would mean the app quietly arguing with
//  someone about their own kitchen, over and over, every time they mentioned
//  the subject.
//

import Foundation
import SwiftData

enum FactCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case allergy
    case dietary
    case equipment
    case household
    case preference
    case schedule
    case skill

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .allergy: "Allergies"
        case .dietary: "How you eat"
        case .equipment: "Your kitchen"
        case .household: "Who you cook for"
        case .preference: "Likes and dislikes"
        case .schedule: "Your week"
        case .skill: "What you're up for"
        }
    }

    /// Categories that change what the app is allowed to suggest, rather than
    /// what it prefers to. These are never applied on an inference alone.
    nonisolated var isSafetyRelevant: Bool {
        self == .allergy || self == .dietary
    }

    nonisolated var symbol: String {
        switch self {
        case .allergy: "exclamationmark.triangle"
        case .dietary: "leaf"
        case .equipment: "fork.knife"
        case .household: "person.2"
        case .preference: "heart"
        case .schedule: "calendar"
        case .skill: "chart.bar"
        }
    }
}

enum FactSource: String, Codable, CaseIterable, Sendable {
    /// They typed it, or confirmed it on a card.
    case userStated
    /// Derived from behaviour.
    case inferred
    /// Pulled out of a conversation by the background extractor.
    case extractedFromChat

    nonisolated var displayName: String {
        switch self {
        case .userStated: "user-stated"
        case .inferred: "inferred"
        case .extractedFromChat: "from chat"
        }
    }
}

@Model
final class CookFact {
    @Attribute(.unique) var id: UUID
    var statement: String
    var category: FactCategory
    var confidence: Double
    var source: FactSource
    /// What they actually said, verbatim.
    var sourceExcerpt: String?

    var createdAt: Date
    var lastConfirmedAt: Date?

    /// Set the moment a person edits or confirms this. Locks it against every
    /// automatic overwrite from then on.
    var isUserEdited: Bool
    var isActive: Bool

    /// An allergy or dietary fact does nothing until a person says yes.
    ///
    /// §5 is firm about this and the asymmetry is the reason: a false
    /// positive silently removes food they can eat, and a false negative is a
    /// safety issue. Neither is acceptable as a silent guess, so the fact
    /// exists in a pending state and filters nothing until confirmed.
    var needsConfirmation: Bool

    init(
        id: UUID = UUID(),
        statement: String,
        category: FactCategory,
        confidence: Double = 0.8,
        source: FactSource = .userStated,
        sourceExcerpt: String? = nil,
        createdAt: Date = .now,
        lastConfirmedAt: Date? = nil,
        isUserEdited: Bool = false,
        isActive: Bool = true,
        needsConfirmation: Bool = false
    ) {
        self.id = id
        self.statement = statement
        self.category = category
        self.confidence = confidence
        self.source = source
        self.sourceExcerpt = sourceExcerpt
        self.createdAt = createdAt
        self.lastConfirmedAt = lastConfirmedAt
        self.isUserEdited = isUserEdited
        self.isActive = isActive
        self.needsConfirmation = needsConfirmation
    }
}

extension CookFact {
    /// True when this fact is allowed to change what gets recommended.
    var isEnforceable: Bool {
        isActive && !needsConfirmation
    }

    /// "[user-stated]" or "[inferred, 0.7]", as §6's FACTS section wants it.
    var provenanceLabel: String {
        switch source {
        case .userStated: "user-stated"
        case .inferred: String(format: "inferred, %.1f", confidence)
        case .extractedFromChat:
            isUserEdited ? "user-stated" : String(format: "from chat, %.1f", confidence)
        }
    }

    var digestFact: DigestFact {
        DigestFact(
            statement: statement,
            provenance: provenanceLabel,
            isCritical: category.isSafetyRelevant
        )
    }
}
