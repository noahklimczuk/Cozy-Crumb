//
//  TasteProfile.swift
//  Cozy Crumb
//
//  The stored copy of what the app has worked out.
//
//  This is a *cache*, not the source of truth. The signals are the truth;
//  this is what falls out of them, kept so the app does not have to re-derive
//  a picture of six months of cooking every time a screen appears.
//  `TasteProfileSnapshot` is what everything actually reads.
//
//  Two shape decisions that differ from the spec's sketch, both for the same
//  reason — SwiftData is happiest with simple stored types:
//
//    * Dictionaries are keyed by String rather than Int. `[Int: Double]` and
//      `[Int: [Int]]` are legal Swift but a needless bet on the persistence
//      layer's handling of non-string keys. Weekday numbers go in as "1"…"7"
//      and come back out as Ints through the accessors below.
//
//    * `inferredEquipment` is an Array here and a Set in the snapshot. Same
//      reason; the conversion is one line and happens in one place.
//
//  User corrections live here too, and they are the whole point of §8. An
//  override survives every rebuild — the builder reads it and stops deriving
//  that value. A dismissal removes the inference entirely rather than zeroing
//  it, because zero is a finding and absence is the truth.
//

import Foundation
import SwiftData

@Model
final class TasteProfile {
    @Attribute(.unique) var id: UUID

    var cuisineAffinity: [String: Double]
    var ingredientAffinity: [String: Double]
    var techniqueComfort: [String: Double]

    /// Weekday number as a string, "1" = Sunday.
    var effortMinutesByWeekday: [String: Int]
    var cookHoursByWeekday: [String: [Int]]

    var spiceTolerance: Double?
    var inferredHouseholdSize: Int?
    var noveltyAppetite: Double
    var inferredEquipment: [String]

    var explicitlyDisliked: [String]
    var aspirationalRecipeIDs: [UUID]

    var signalCount: Int
    var lastRebuiltAt: Date

    /// Inference key → the sentence explaining it.
    var evidenceSummaries: [String: String]
    var evidenceCounts: [String: Int]

    /// Values the user typed or corrected. Never overwritten by derivation.
    var userOverrides: [String: Double]
    /// Inferences the user asked the app to forget.
    var dismissedKeys: [String]

    init(
        id: UUID = TasteProfileSnapshot.soleProfileID,
        cuisineAffinity: [String: Double] = [:],
        ingredientAffinity: [String: Double] = [:],
        techniqueComfort: [String: Double] = [:],
        effortMinutesByWeekday: [String: Int] = [:],
        cookHoursByWeekday: [String: [Int]] = [:],
        spiceTolerance: Double? = nil,
        inferredHouseholdSize: Int? = nil,
        noveltyAppetite: Double = 0.5,
        inferredEquipment: [String] = [],
        explicitlyDisliked: [String] = [],
        aspirationalRecipeIDs: [UUID] = [],
        signalCount: Int = 0,
        lastRebuiltAt: Date = .distantPast,
        evidenceSummaries: [String: String] = [:],
        evidenceCounts: [String: Int] = [:],
        userOverrides: [String: Double] = [:],
        dismissedKeys: [String] = []
    ) {
        self.id = id
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
        self.evidenceSummaries = evidenceSummaries
        self.evidenceCounts = evidenceCounts
        self.userOverrides = userOverrides
        self.dismissedKeys = dismissedKeys
    }
}

// MARK: - Conversion

extension TasteProfile {

    /// The value type everything else reads.
    var snapshot: TasteProfileSnapshot {
        var evidence: [String: ProfileEvidence] = [:]
        for (key, summary) in evidenceSummaries {
            evidence[key] = ProfileEvidence(
                summary: summary,
                signalCount: evidenceCounts[key] ?? 0
            )
        }

        return TasteProfileSnapshot(
            profileID: id,
            cuisineAffinity: cuisineAffinity,
            ingredientAffinity: ingredientAffinity,
            techniqueComfort: techniqueComfort,
            effortMinutesByWeekday: Self.intKeyed(effortMinutesByWeekday),
            cookHoursByWeekday: Self.intKeyed(cookHoursByWeekday),
            spiceTolerance: spiceTolerance,
            inferredHouseholdSize: inferredHouseholdSize,
            noveltyAppetite: noveltyAppetite,
            inferredEquipment: Set(inferredEquipment),
            explicitlyDisliked: Set(explicitlyDisliked),
            aspirationalRecipeIDs: Set(aspirationalRecipeIDs),
            signalCount: signalCount,
            lastRebuiltAt: lastRebuiltAt,
            evidence: evidence
        )
    }

    /// Writes a freshly built snapshot over this row.
    ///
    /// Overrides and dismissals are *not* touched: they are the user's, they
    /// were inputs to the build that produced this snapshot, and a rebuild
    /// that quietly cleared them would undo every correction on the Taste
    /// Profile screen the next time someone cooked something.
    func apply(_ snapshot: TasteProfileSnapshot) {
        cuisineAffinity = snapshot.cuisineAffinity
        ingredientAffinity = snapshot.ingredientAffinity
        techniqueComfort = snapshot.techniqueComfort
        effortMinutesByWeekday = Self.stringKeyed(snapshot.effortMinutesByWeekday)
        cookHoursByWeekday = Self.stringKeyed(snapshot.cookHoursByWeekday)
        spiceTolerance = snapshot.spiceTolerance
        inferredHouseholdSize = snapshot.inferredHouseholdSize
        noveltyAppetite = snapshot.noveltyAppetite
        inferredEquipment = snapshot.inferredEquipment.sorted()
        explicitlyDisliked = snapshot.explicitlyDisliked.sorted()
        aspirationalRecipeIDs = Array(snapshot.aspirationalRecipeIDs)
        signalCount = snapshot.signalCount
        lastRebuiltAt = snapshot.lastRebuiltAt
        evidenceSummaries = snapshot.evidence.mapValues(\.summary)
        evidenceCounts = snapshot.evidence.mapValues(\.signalCount)
    }

    nonisolated static func intKeyed<Value>(_ dictionary: [String: Value]) -> [Int: Value] {
        var result: [Int: Value] = [:]
        for (key, value) in dictionary {
            guard let intKey = Int(key) else { continue }
            result[intKey] = value
        }
        return result
    }

    nonisolated static func stringKeyed<Value>(_ dictionary: [Int: Value]) -> [String: Value] {
        var result: [String: Value] = [:]
        for (key, value) in dictionary {
            result[String(key)] = value
        }
        return result
    }
}
