//
//  PantryConfidence.swift
//  Cozy Crumb
//
//  How sure the app is that something is still there, and the one place that
//  question is answered.
//
//  There used to be two answers. `RecommendationEngine.freshness` discounted a
//  pantry entry by age with its own per-category half-lives, and the revamp
//  spec described a decay engine with different ones — dairy at 21 days on one
//  side and 8 on the other. Two models with different constants is the same
//  bug as two ingredient canonicalizers: it shows up as a recipe scoring
//  differently depending on which code path asked, which is close to
//  undebuggable. `freshness` is gone and everything reads this.
//
//  Confidence is never stored. It is a function of three things the pantry
//  *does* store — how good the evidence was, when it landed, and what kind of
//  food it is — plus the date you are asking about. A stored number that is
//  meant to fall off over time needs something to recompute it, nothing ever
//  does, and the value quietly starts lying. That is the failure this whole
//  feature exists to prevent.
//
//  The date is always passed in, never read from the clock here. That is what
//  makes three months of decay testable in a millisecond.
//

import Foundation

// MARK: - Evidence

/// Everything needed to work out how much to believe one pantry row.
///
/// A value type rather than the `@Model`, so the recommendation engine can
/// score against a snapshot without touching SwiftData, and so a test can
/// build one without a store.
nonisolated struct PantryEvidence: Sendable, Equatable {
    /// The canonical food name. Drives the half-life override table — spinach
    /// and potatoes are both produce and they do not keep the same way.
    var canonicalName: String
    var category: GroceryCategory

    /// How strongly this was believed at `confirmedAt`. See
    /// `CaptureSource.initialConfidence`.
    var strength: Double

    /// When someone or something last established this is really here.
    var confirmedAt: Date

    /// A date the user read off the package, where they set one.
    var expiresAt: Date?

    /// Staples and pinned rows. Nobody should ever be asked whether they still
    /// have salt.
    var neverDecays: Bool

    nonisolated init(
        canonicalName: String,
        category: GroceryCategory = .other,
        strength: Double = 1.0,
        confirmedAt: Date,
        expiresAt: Date? = nil,
        neverDecays: Bool = false
    ) {
        self.canonicalName = canonicalName
        self.category = category
        self.strength = strength
        self.confirmedAt = confirmedAt
        self.expiresAt = expiresAt
        self.neverDecays = neverDecays
    }
}

// MARK: - Bands

/// What a confidence figure means to the rest of the app.
///
/// Downstream code branches on the band, not on the number. A band is a
/// decision — plan around it, hedge about it, leave it out, put it away — and
/// scattering `> 0.8` comparisons through feature code is how those decisions
/// drift apart.
nonisolated enum PantryConfidenceBand: String, CaseIterable, Comparable, Sendable {
    /// Treated as present. Full weight in recommendations.
    case confident
    /// Usable, but the Sous Chef hedges: "if you've still got that spinach…".
    case probable
    /// Left out of recommendation matching, dimmed in the UI, and this is what
    /// the reconciliation sweep asks about.
    case doubtful
    /// Archived out of the active list. Never deleted — see `PantryDecay`.
    case lapsed

    /// Ordered least-sure to most-sure, so `max`/`<` read the way they look.
    private nonisolated var rank: Int {
        switch self {
        case .lapsed: 0
        case .doubtful: 1
        case .probable: 2
        case .confident: 3
        }
    }

    nonisolated static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Whether the recommendation engine should count this towards a recipe.
    nonisolated var countsTowardsRecipes: Bool {
        self >= .probable
    }

    /// How the Sous Chef's digest groups it (§4).
    nonisolated var digestHeading: String {
        switch self {
        case .confident: "Confident"
        case .probable: "Probably"
        case .doubtful, .lapsed: "Might be gone"
        }
    }

    /// Said in words for VoiceOver, because opacity and a ring are not
    /// available to everyone (§9).
    nonisolated var spokenDescription: String {
        switch self {
        case .confident: "definitely have"
        case .probable: "probably still have"
        case .doubtful: "might be gone"
        case .lapsed: "probably gone"
        }
    }
}

// MARK: - The engine

nonisolated enum PantryConfidence {

    // MARK: Band thresholds

    nonisolated static let confidentFloor = 0.8
    nonisolated static let probableFloor = 0.5
    nonisolated static let doubtfulFloor = 0.25

    nonisolated static func band(for confidence: Double) -> PantryConfidenceBand {
        switch confidence {
        case confidentFloor...: .confident
        case probableFloor..<confidentFloor: .probable
        case doubtfulFloor..<probableFloor: .doubtful
        default: .lapsed
        }
    }

    // MARK: Decay

    /// How much to believe this evidence on `date`.
    nonisolated static func confidence(of evidence: PantryEvidence, at date: Date) -> Double {
        // Staples and pinned rows are a standing statement by the user that
        // this is always in. Age says nothing about them.
        guard !evidence.neverDecays else { return 1 }

        let strength = min(max(evidence.strength, 0), 1)
        let days = max(0, date.timeIntervalSince(evidence.confirmedAt) / 86_400)
        let halfLife = halfLifeDays(forCanonical: evidence.canonicalName, category: evidence.category)

        var value = strength * pow(0.5, days / halfLife)

        // A date the user read off the package outranks anything the app
        // inferred (§8). Past it, the app stops counting on the item — but it
        // does not decide the food is bad, and it does not remove it. It drops
        // to the top of the doubtful band, which is exactly where the
        // reconciliation sweep will ask about it.
        if let expiresAt = evidence.expiresAt, expiresAt < date {
            value = min(value, doubtfulFloor)
        }

        return min(max(value, 0), 1)
    }

    nonisolated static func band(of evidence: PantryEvidence, at date: Date) -> PantryConfidenceBand {
        band(for: confidence(of: evidence, at: date))
    }

    /// When this evidence will fall below `target`, if it ever does.
    ///
    /// Used to schedule the reconciliation nudge against real dates rather
    /// than re-scanning the whole pantry on a timer.
    nonisolated static func date(
        whenConfidenceFallsBelow target: Double,
        for evidence: PantryEvidence
    ) -> Date? {
        guard !evidence.neverDecays, target > 0 else { return nil }

        let strength = min(max(evidence.strength, 0), 1)
        guard strength > target else { return evidence.confirmedAt }

        let halfLife = halfLifeDays(forCanonical: evidence.canonicalName, category: evidence.category)
        let halfLives = log(target / strength) / log(0.5)
        return evidence.confirmedAt.addingTimeInterval(halfLives * halfLife * 86_400)
    }

    // MARK: Half-lives

    /// How long a food stays believable, in days.
    ///
    /// Keyed by canonical name first and category second, because the category
    /// is too coarse to carry this on its own: coriander and potatoes are both
    /// produce, and one of them is a puddle in five days while the other is
    /// fine in a month. The spec's table is written in terms of "fresh herbs"
    /// and "leafy greens", which are not `GroceryCategory` cases and never
    /// will be — so they live in the override table below.
    ///
    /// This is deliberately *not* a shelf-life table. Shelf life is how long
    /// before something goes off; this is how long before the app should stop
    /// assuming it is still in the house, which folds in how fast it gets
    /// eaten. Herbs decay fast here partly because they spoil and partly
    /// because a bunch of parsley gets used up in two meals. P8's shelf-life
    /// resource answers the other question and does not replace this one.
    nonisolated static func halfLifeDays(
        forCanonical canonicalName: String,
        category: GroceryCategory
    ) -> Double {
        if let override = overrides[canonicalName] {
            return override
        }
        return halfLifeDays(for: category)
    }

    nonisolated static func halfLifeDays(for category: GroceryCategory) -> Double {
        switch category {
        case .produce: 10
        case .dairy: 8
        case .meat: 8
        case .bakery: 6
        case .frozen: 60
        case .pantry: 90
        case .condiment: 90
        // A grab bag, so a middle number. Anything that ends up here often
        // enough to matter deserves a real category rather than a tuned
        // constant.
        case .other: 30
        }
    }

    /// Foods whose category is a bad guide. Canonical names — run anything
    /// from outside through `IngredientCanonicalizer.canonical(_:)` first.
    nonisolated static let overrides: [String: Double] = {
        var table: [String: Double] = [:]

        // Fresh herbs and leafy greens: five days. They wilt fast and they get
        // used up fast, and both point the same way.
        //
        // Some of these look wrong and are not. The canonicalizer reduces
        // "bok choy" to its head noun "choy" and "collard greens" to "greens",
        // because neither is in its compound list; "rocket" resolves to
        // "arugula" through synonyms. Keys here have to be what the
        // canonicalizer actually *produces*, or they sit in the table looking
        // reassuring and never match anything. `overridesAreCanonical` in the
        // tests is what stops that happening again.
        for name in [
            "basil", "cilantro", "parsley", "mint", "dill", "chive", "tarragon",
            "rosemary", "sage", "spinach", "lettuce", "arugula", "kale",
            "chard", "watercress", "greens", "choy"
        ] {
            table[name] = 5
        }

        // Quick to turn, but not herb-quick.
        for name in [
            "mushroom", "berry", "strawberry", "raspberry", "blueberry",
            "avocado", "banana", "asparagus", "cucumber", "tomato", "peach"
        ] {
            table[name] = 7
        }

        // Root vegetables and alliums outlast the rest of the produce aisle by
        // a wide margin, and marking them down at ten days is what makes an
        // app claim you are out of onions.
        for name in [
            "onion", "spring onion", "garlic", "potato", "sweet potato",
            "carrot", "beet", "turnip", "rutabaga", "squash", "pumpkin",
            "cabbage", "ginger"
        ] {
            table[name] = 30
        }

        // Long keepers hiding in short-lived categories.
        table["egg"] = 21
        table["butter"] = 30
        table["parmesan"] = 21
        table["yogurt"] = 10
        // No entry for cheese. "hard cheese" canonicalises to plain "cheese",
        // and a 21-day key on that would hand the same lifetime to a soft
        // cheese that is off in a week. Dairy's eight days is the conservative
        // read, and being conservative is the whole posture here.

        return table
    }()
}
