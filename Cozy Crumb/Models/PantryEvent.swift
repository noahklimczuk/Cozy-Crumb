//
//  PantryEvent.swift
//  Cozy Crumb
//
//  Everything that has ever happened to the pantry, in order.
//
//  Three things need this and none of them can be answered from the current
//  inventory alone:
//
//    - Restock prediction (P9) learns a cadence from the gaps between
//      purchases of the same food. The pantry only knows about the jar you
//      have now, not the four before it.
//    - Waste insight (P8) needs to know that the coriander was thrown out
//      three times running, which is precisely the information that is
//      destroyed when a row is deleted.
//    - When the inventory is wrong — and it will be — this is the only way to
//      work out why. An item that vanished either got cooked, got ticked off,
//      got swept away, or decayed out, and those are four different bugs.
//
//  So: never mutate a `PantryItem` without writing one of these. `PantryLog`
//  exists to make that a single call rather than a discipline.
//
//  Events key off the *canonical* name rather than the item's id. The item is
//  the thing that comes and goes; the food is what has a history. Two jars of
//  tahini bought a year apart are one story, and they are not the same row.
//

import Foundation
import SwiftData

nonisolated enum PantryEventKind: String, Codable, CaseIterable, Sendable {
    /// Arrived, by any capture route.
    case added
    /// Gone, and the user said so — "used it up", or swiped it away.
    case depleted
    /// Taken off automatically by cooking a recipe. Kept distinct from
    /// `.depleted` because it is the app's inference, not the user's word, and
    /// a wrong one should be traceable.
    case consumedByCook
    /// Thrown out. The signal waste insight is built on.
    case wasted
    /// The user confirmed it is still there — the reconciliation sweep, or a
    /// swipe on a row.
    case confirmed
    /// The user changed something about it: quantity, name, tier, location.
    case corrected
    /// Passed its date, or decayed below the lapsed band and was archived.
    case expired

    nonisolated var displayName: String {
        switch self {
        case .added: "Added"
        case .depleted: "Used up"
        case .consumedByCook: "Cooked with"
        case .wasted: "Thrown out"
        case .confirmed: "Confirmed"
        case .corrected: "Corrected"
        case .expired: "Ran out of time"
        }
    }

    /// Whether this event means the food arrived. Restock prediction measures
    /// the gaps between these and nothing else.
    nonisolated var isAcquisition: Bool {
        self == .added
    }
}

@Model
final class PantryEvent {
    @Attribute(.unique) var id: UUID

    /// Canonical food name — "tomato", not "Roma tomatoes". This is what the
    /// history is keyed on; see the note at the top of the file.
    var canonicalName: String

    /// What the item was called at the time, so a history can be read back in
    /// the user's own words rather than the matcher's.
    var displayName: String

    var kind: PantryEventKind

    /// How much moved, where a number was known. Negative for things going
    /// out. Nil is common and fine — most of the pantry has no numbers.
    var quantityDelta: Double?
    var unit: String?

    /// Which recipe consumed it, for `.consumedByCook`. An id rather than a
    /// relationship: an event outlives the recipe it refers to, and a dangling
    /// relationship would either block the delete or take the history with it.
    var recipeID: UUID?

    var timestamp: Date

    init(
        id: UUID = UUID(),
        canonicalName: String,
        displayName: String,
        kind: PantryEventKind,
        quantityDelta: Double? = nil,
        unit: String? = nil,
        recipeID: UUID? = nil,
        timestamp: Date = .now
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.displayName = displayName
        self.kind = kind
        self.quantityDelta = quantityDelta
        self.unit = unit
        self.recipeID = recipeID
        self.timestamp = timestamp
    }
}
