//
//  TasteSignal.swift
//  Cozy Crumb
//
//  One thing the user did, recorded so the app can work out what they like.
//
//  The Sous Chef spec opens with the point that matters most here: Gemini
//  cannot learn anything. It is stateless, every request starts blank, and
//  there is no memory in the model between calls. All of the learning lives
//  in the app, and this is the bottom of it — the raw event log everything
//  else is derived from.
//
//  Three decisions worth knowing about before reading the code:
//
//  1. `weight` is stored, not looked up. It is derived from `kind` at the
//     moment of logging and then frozen. Retuning the table in a later build
//     should not silently rewrite two years of history into something the
//     user never did, so old signals keep the meaning they were recorded
//     with. `SignalKind.baseWeight` stays public and pure so the derivation
//     itself can be tested.
//
//  2. The recipe is referenced by UUID rather than by a SwiftData
//     relationship. A signal outlives the recipe it came from: deleting a
//     Thai curry should not also delete the evidence that this cook likes
//     lemongrass, fish sauce and 25-minute dinners. A relationship with any
//     delete rule would either take the signal with it or leave a dangling
//     reference; a plain identifier is honest about being a soft link.
//
//  3. Nothing here decays on its own. Decay is a pure function of age applied
//     at read time (`effectiveWeight`), so the same row means different
//     things in March and September without anyone having to migrate it.
//

import Foundation
import SwiftData

// MARK: - Kinds

/// What the user did. Grouped by how much it actually tells us, which is not
/// the same as how deliberate it looked at the time.
enum SignalKind: String, Codable, CaseIterable, Sendable {

    // Strong positive — they actually did the thing.

    /// Cooked something for the first time.
    case cooked
    /// Cooked something they had cooked before. Logged *instead of* `cooked`,
    /// never alongside it, or a recipe made four times would quietly earn
    /// +11 and drown out everything else in the profile.
    case cookedRepeat
    case ratedHigh
    case addedToCollection

    // Moderate positive.

    case favorited
    case saved
    case groceryPurchased
    case viewedLong

    // Weak positive.

    case viewed
    case searched
    case imported

    // Negative.

    case ratedLow
    case dismissedRecommendation
    case abandonedMidCook
    case ingredientRemovedFromGrocery
    case savedButNeverCooked
    case explicitlyDisliked

    /// The weight this kind carries before any decay.
    ///
    /// `saved` and `searched` are not in the spec's table. Cozy Crumb has no
    /// "save" separate from importing, so `saved` matches `imported`, and a
    /// search is a weaker signal than reading a page, so `searched` sits at
    /// the same floor as `viewed`.
    nonisolated var baseWeight: Double {
        switch self {
        case .cookedRepeat: 3.0
        case .cooked: 2.0
        case .ratedHigh: 1.8
        case .addedToCollection: 1.2
        case .groceryPurchased: 1.0
        case .favorited: 0.8
        case .saved: 0.5
        case .imported: 0.5
        case .viewedLong: 0.4
        case .viewed: 0.1
        case .searched: 0.1

        case .savedButNeverCooked: -0.6
        case .dismissedRecommendation: -1.0
        case .abandonedMidCook: -1.2
        case .ingredientRemovedFromGrocery: -1.5
        case .ratedLow: -2.0
        case .explicitlyDisliked: -4.0
        }
    }

    /// Whether age is allowed to soften this.
    ///
    /// Tastes drift, so almost everything decays. "I hate coriander" does not
    /// — someone who typed that two years ago has not quietly started liking
    /// it, and letting the statement fade means recommending coriander again
    /// eventually, which is exactly the failure the whole system exists to
    /// avoid. Allergy facts get the same treatment in `CookFact` (S7).
    nonisolated var decays: Bool {
        self != .explicitlyDisliked
    }

    /// True for the signals logged as a side effect of simply looking around.
    /// These are the ones that pile up in volume and get pruned first.
    nonisolated var isIncidental: Bool {
        switch self {
        case .viewed, .searched: true
        default: false
        }
    }

    /// For the debug inspector. Not user-facing copy.
    nonisolated var debugDescription: String {
        switch self {
        case .cooked: "cooked"
        case .cookedRepeat: "cooked again"
        case .ratedHigh: "rated 4–5★"
        case .addedToCollection: "added to a collection"
        case .favorited: "favourited"
        case .saved: "saved"
        case .groceryPurchased: "bought"
        case .viewedLong: "read properly"
        case .viewed: "opened"
        case .searched: "searched"
        case .imported: "imported"
        case .ratedLow: "rated 1–2★"
        case .dismissedRecommendation: "dismissed a suggestion"
        case .abandonedMidCook: "gave up mid-cook"
        case .ingredientRemovedFromGrocery: "deleted off the list"
        case .savedButNeverCooked: "saved, never cooked"
        case .explicitlyDisliked: "said they dislike it"
        }
    }
}

// MARK: - Context

/// When the thing happened, in the terms recommendations care about.
///
/// This is the part of §2 that is easy to skip and shouldn't be: knowing
/// someone cooks 20 minutes on a Tuesday and three hours on a Sunday is more
/// use than knowing their favourite cuisine.
nonisolated struct SignalContext: Codable, Sendable, Equatable {

    /// Northern hemisphere, because that is where the user cooks. A southern
    /// hemisphere build would need this flipped, not just relabelled.
    nonisolated enum Season: String, Codable, CaseIterable, Sendable {
        case winter, spring, summer, autumn

        nonisolated var displayName: String {
            switch self {
            case .winter: "winter"
            case .spring: "spring"
            case .summer: "summer"
            case .autumn: "autumn"
            }
        }
    }

    /// 1 = Sunday … 7 = Saturday, matching `Calendar.component(.weekday:)`.
    var weekday: Int
    /// 0–23.
    var hour: Int
    var season: Season

    nonisolated init(weekday: Int, hour: Int, season: Season) {
        self.weekday = weekday
        self.hour = hour
        self.season = season
    }

    nonisolated init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.weekday, .hour, .month], from: date)
        self.weekday = parts.weekday ?? 1
        self.hour = parts.hour ?? 12
        self.season = Self.season(forMonth: parts.month ?? 1)
    }

    nonisolated static func season(forMonth month: Int) -> Season {
        switch month {
        case 12, 1, 2: .winter
        case 3, 4, 5: .spring
        case 6, 7, 8: .summer
        default: .autumn
        }
    }

    /// Short weekday name for the digest and the debug screen. Built from a
    /// fixed calendar rather than the user's, because a weekday number means
    /// nothing without the calendar that produced it.
    nonisolated var weekdayName: String {
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        guard weekday >= 1, weekday <= 7 else { return "?" }
        return names[weekday - 1]
    }
}

// MARK: - The signal

@Model
final class TasteSignal {
    @Attribute(.unique) var id: UUID
    var kind: SignalKind

    /// Soft link to a `Recipe.id`. See the note at the top of the file.
    var recipeID: UUID?
    /// Canonicalised and lowercased before it gets here (S2).
    var ingredientName: String?
    var tag: String?

    /// `kind.baseWeight` as it stood when this was logged, then frozen.
    var weight: Double
    var timestamp: Date
    var context: SignalContext?

    init(
        id: UUID = UUID(),
        kind: SignalKind,
        recipeID: UUID? = nil,
        ingredientName: String? = nil,
        tag: String? = nil,
        weight: Double? = nil,
        timestamp: Date = .now,
        context: SignalContext? = nil
    ) {
        self.id = id
        self.kind = kind
        self.recipeID = recipeID
        self.ingredientName = ingredientName
        self.tag = tag
        self.weight = weight ?? kind.baseWeight
        self.timestamp = timestamp
        self.context = context
    }
}

// MARK: - Decay

nonisolated enum SignalDecay {

    /// Half-life in days. A signal from six months ago counts half; a year
    /// ago, a quarter. Slow enough that a quiet month doesn't erase a taste,
    /// fast enough that last winter's soup phase doesn't own next July.
    nonisolated static let halfLifeDays: Double = 180

    /// Multiplier for a signal of a given age. 1.0 today, 0.5 at the
    /// half-life, never negative and never above 1.
    nonisolated static func factor(daysAgo: Double, halfLife: Double = halfLifeDays) -> Double {
        guard halfLife > 0 else { return 1 }
        // A signal timestamped in the future — a clock change, a restored
        // backup — is treated as fresh rather than amplified.
        guard daysAgo > 0 else { return 1 }
        return pow(0.5, daysAgo / halfLife)
    }

    nonisolated static func days(from timestamp: Date, to now: Date) -> Double {
        now.timeIntervalSince(timestamp) / 86_400
    }
}

extension TasteSignal {
    /// Age in days. Negative ages are clamped by `SignalDecay.factor`.
    nonisolated func age(at now: Date = .now) -> Double {
        SignalDecay.days(from: timestamp, to: now)
    }

    /// What this signal is worth *today*. Everything downstream sums these,
    /// never the raw `weight`.
    nonisolated func effectiveWeight(at now: Date = .now) -> Double {
        guard kind.decays else { return weight }
        return weight * SignalDecay.factor(daysAgo: age(at: now))
    }
}
