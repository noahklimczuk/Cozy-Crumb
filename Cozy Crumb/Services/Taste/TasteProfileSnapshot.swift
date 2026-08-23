//
//  TasteProfileSnapshot.swift
//  Cozy Crumb
//
//  What the app has worked out about this cook, as a plain value.
//
//  The `@Model` version of this (TasteProfile) is a cache. *This* is what
//  every consumer reads: the recommendation engine, the digest builder, the
//  Taste Profile screen. That split is deliberate and it is what makes §4
//  possible at all — the engine has to be pure and unit-testable, and it
//  cannot be if it takes a SwiftData object that needs a live store to exist.
//
//  Everything here is derived and everything here can be wrong. Two things
//  follow from that, and both are load-bearing:
//
//    * `confidence` gates how much anyone is allowed to lean on it. Below
//      0.4 the Sous Chef is told not to claim it knows their taste, and the
//      engine weights generic quality higher. A confidently wrong profile is
//      worse than an admittedly empty one.
//
//    * Every inference carries `evidence`, keyed the same way as the numbers.
//      §8 requires that tapping any claim shows what it was built from, and
//      that is only possible if provenance is computed alongside the value
//      rather than reconstructed afterwards.
//

import Foundation

// MARK: - Evidence

/// Why the app believes something. One per inference key.
nonisolated struct ProfileEvidence: Sendable, Equatable, Codable {
    /// Plain language, written for the user: "you've cooked 6 Thai recipes,
    /// 3 of them more than once".
    var summary: String
    /// How many signals went into it. Drives "still getting to know you".
    var signalCount: Int
    /// A few of the recipes behind it, for the detail sheet.
    var recipeTitles: [String]

    nonisolated init(summary: String, signalCount: Int, recipeTitles: [String] = []) {
        self.summary = summary
        self.signalCount = signalCount
        self.recipeTitles = recipeTitles
    }
}

/// One thing the profile leans toward or away from.
///
/// A named type rather than a tuple: these go straight into `ForEach`, and an
/// Identifiable struct spares every call site an `id:` argument — and spares
/// the compiler a key path into a tuple element, which is a corner of the
/// language not worth standing in.
nonisolated struct AffinityEntry: Sendable, Equatable, Identifiable {
    var name: String
    /// −1…1.
    var score: Double

    nonisolated var id: String { name }

    nonisolated init(name: String, score: Double) {
        self.name = name
        self.score = score
    }
}

// MARK: - Keys

/// Stable identifiers for one inference, so a value, its evidence, a user
/// override and a "forget this" all refer to the same thing.
nonisolated enum ProfileKey {
    nonisolated static func cuisine(_ name: String) -> String { "cuisine.\(name)" }
    nonisolated static func ingredient(_ name: String) -> String { "ingredient.\(name)" }
    nonisolated static func technique(_ name: String) -> String { "technique.\(name)" }
    nonisolated static func equipment(_ name: String) -> String { "equipment.\(name)" }
    nonisolated static let spiceTolerance = "spiceTolerance"
    nonisolated static let householdSize = "householdSize"
    nonisolated static let noveltyAppetite = "noveltyAppetite"
    nonisolated static let effort = "effort"
    nonisolated static let schedule = "schedule"
}

// MARK: - The snapshot

nonisolated struct TasteProfileSnapshot: Sendable, Equatable {

    /// Keyed so a profile switcher can be added later without a migration
    /// (§10). One profile today; the key means two is a feature rather than a
    /// schema change.
    var profileID: UUID

    /// −1…1 each.
    var cuisineAffinity: [String: Double]
    var ingredientAffinity: [String: Double]
    var techniqueComfort: [String: Double]

    /// 1 = Sunday … 7 = Saturday. Typical total minutes of what they actually
    /// cooked on that day.
    var effortMinutesByWeekday: [Int: Int]
    /// Hours of the day they tend to cook, per weekday.
    var cookHoursByWeekday: [Int: [Int]]

    /// nil until there is real evidence. A wrong guess about heat is very
    /// noticeable, so silence is the honest default.
    var spiceTolerance: Double?
    var inferredHouseholdSize: Int?

    /// 0 = they have a rotation and like it, 1 = surprise me.
    var noveltyAppetite: Double

    /// Only ever added to. Not having cooked with a stand mixer is not
    /// evidence of not owning one (§3).
    var inferredEquipment: Set<String>

    /// Foods they have said, in words, that they do not want.
    ///
    /// Kept as a set rather than inferred from a low affinity score. §4's
    /// hard filter has to be exact — "remove every recipe containing this" is
    /// not a judgement call, and a threshold would make it one.
    var explicitlyDisliked: Set<String>

    /// Recipes saved long ago, looked at more than once, never cooked. The
    /// aspiration gap — see AspirationGapDetector.
    var aspirationalRecipeIDs: Set<UUID>

    var signalCount: Int
    var lastRebuiltAt: Date

    var evidence: [String: ProfileEvidence]

    nonisolated init(
        profileID: UUID = TasteProfileSnapshot.soleProfileID,
        cuisineAffinity: [String: Double] = [:],
        ingredientAffinity: [String: Double] = [:],
        techniqueComfort: [String: Double] = [:],
        effortMinutesByWeekday: [Int: Int] = [:],
        cookHoursByWeekday: [Int: [Int]] = [:],
        spiceTolerance: Double? = nil,
        inferredHouseholdSize: Int? = nil,
        noveltyAppetite: Double = 0.5,
        inferredEquipment: Set<String> = [],
        explicitlyDisliked: Set<String> = [],
        aspirationalRecipeIDs: Set<UUID> = [],
        signalCount: Int = 0,
        lastRebuiltAt: Date = .distantPast,
        evidence: [String: ProfileEvidence] = [:]
    ) {
        self.profileID = profileID
        self.cuisineAffinity = cuisineAffinity
        self.ingredientAffinity = ingredientAffinity
        self.techniqueComfort = techniqueComfort
        self.effortMinutesByWeekday = effortMinutesByWeekday
        self.cookHoursByWeekday = cookHoursByWeekday
        self.spiceTolerance = spiceTolerance
        self.inferredHouseholdSize = inferredHouseholdSize
        self.noveltyAppetite = noveltyAppetite
        self.inferredEquipment = inferredEquipment
        self.explicitlyDisliked = explicitlyDisliked
        self.aspirationalRecipeIDs = aspirationalRecipeIDs
        self.signalCount = signalCount
        self.lastRebuiltAt = lastRebuiltAt
        self.evidence = evidence
    }

    /// The single profile this build has. Fixed rather than random so it is
    /// stable across launches and across a store rebuild.
    nonisolated static let soleProfileID = UUID(uuidString: "C0217CB0-0000-4000-8000-000000000001")!

    // MARK: - Confidence

    /// How many signals it takes before the profile is worth believing. Below
    /// 15 it is noise; 60 is a confident picture.
    nonisolated static let confidenceCeiling = 60.0

    /// 0–1. `min(1, signalCount / 60)`, as specified.
    var confidence: Double {
        min(1, Double(signalCount) / Self.confidenceCeiling)
    }

    /// Under this, nothing here should be presented as fact and the engine
    /// leans on generic quality instead (§9).
    nonisolated static let usableConfidence = 0.4

    var isUsable: Bool {
        confidence >= Self.usableConfidence
    }

    /// The kindly phrasing §8 asks for.
    var confidenceDescription: String {
        switch confidence {
        case ..<0.15: "Still getting to know you"
        case ..<0.4: "Starting to get a feel for it"
        case ..<0.75: "Getting the hang of your taste"
        default: "I think I know what you like"
        }
    }

    // MARK: - Reading

    var isEmpty: Bool {
        signalCount == 0
    }

    /// Cuisines they lean toward, strongest first.
    func topCuisines(_ limit: Int = 3, above threshold: Double = 0.2) -> [AffinityEntry] {
        ranked(cuisineAffinity, limit: limit, above: threshold)
    }

    func coolerCuisines(_ limit: Int = 2, below threshold: Double = -0.15) -> [AffinityEntry] {
        lowest(cuisineAffinity, limit: limit, below: threshold)
    }

    func lovedIngredients(_ limit: Int = 6, above threshold: Double = 0.3) -> [AffinityEntry] {
        ranked(ingredientAffinity, limit: limit, above: threshold)
    }

    func avoidedIngredients(_ limit: Int = 5, below threshold: Double = -0.3) -> [AffinityEntry] {
        lowest(ingredientAffinity, limit: limit, below: threshold)
    }

    func comfortableTechniques(_ limit: Int = 5, above threshold: Double = 0.2) -> [AffinityEntry] {
        ranked(techniqueComfort, limit: limit, above: threshold)
    }

    /// Techniques they have not shown any sign of trying. Feeds the stretch
    /// picks, and the "hasn't tried" line of the digest.
    func untriedTechniques(_ limit: Int = 4) -> [String] {
        TechniqueClassifier.all
            .filter { techniqueComfort[$0.name] == nil }
            .sorted { $0.demand < $1.demand }
            .prefix(limit)
            .map(\.name)
    }

    private func ranked(
        _ values: [String: Double],
        limit: Int,
        above threshold: Double
    ) -> [AffinityEntry] {
        values
            .filter { $0.value >= threshold }
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(limit)
            .map { AffinityEntry(name: $0.key, score: $0.value) }
    }

    private func lowest(
        _ values: [String: Double],
        limit: Int,
        below threshold: Double
    ) -> [AffinityEntry] {
        values
            .filter { $0.value <= threshold }
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value < rhs.value
            }
            .prefix(limit)
            .map { AffinityEntry(name: $0.key, score: $0.value) }
    }

    /// Minutes they typically spend on a given weekday, falling back to the
    /// overall average and then to a plain default.
    func typicalMinutes(onWeekday weekday: Int) -> Int {
        if let known = effortMinutesByWeekday[weekday] { return known }

        let all = effortMinutesByWeekday.values
        guard !all.isEmpty else { return Self.defaultEffortMinutes }
        return all.reduce(0, +) / all.count
    }

    /// What to assume before anyone has cooked anything.
    nonisolated static let defaultEffortMinutes = 45

    /// The days they cook most, busiest first.
    var busiestCookingDays: [Int] {
        cookHoursByWeekday
            .sorted { lhs, rhs in
                lhs.value.count == rhs.value.count ? lhs.key < rhs.key : lhs.value.count > rhs.value.count
            }
            .map(\.key)
    }

    var noveltyDescription: String {
        switch noveltyAppetite {
        case ..<0.3: "low — they have a rotation and like it"
        case ..<0.6: "moderate — open to new things, but has a rotation"
        default: "high — they want variety"
        }
    }

    var spiceDescription: String? {
        guard let spiceTolerance else { return nil }
        return switch spiceTolerance {
        case ..<0.33: "mild"
        case ..<0.66: "medium"
        default: "high"
        }
    }
}
