//
//  PantryItem.swift
//  Cozy Crumb
//
//  What the user probably has.
//
//  "Probably" is the whole design. Every pantry feature ever shipped dies the
//  same way: week one the user enters everything, week three they stop
//  updating quantities, week five the app confidently plans dinner around
//  chicken that was eaten a fortnight ago. At that point the pantry is worse
//  than useless, because it is actively degrading the recommendations that
//  depend on it. The failure is never missing features. It is staleness.
//
//  So this model does not store "has chicken". It stores evidence: how
//  strongly something was believed, when it was last confirmed, and what kind
//  of thing it is. Confidence is derived from those, never stored — a stored
//  number that is supposed to fall off over time needs something to recompute
//  it, nothing ever does, and the result is a value that quietly lies. That is
//  the exact bug this whole feature exists to avoid, and it would be
//  embarrassing to reproduce it inside the mechanism meant to fix it.
//
//  `canonicalName` is computed for the same reason. A stored copy is a cache
//  of `IngredientCanonicalizer`, and it goes wrong the next time that gets
//  better at its job.
//
//  The decay maths itself is P2. This file carries the evidence.
//

import Foundation
import SwiftData

// MARK: - Capture source

/// How an item got here, and how much that is worth believing.
///
/// Raw values are unchanged from the three-case `PantryItemSource` this
/// replaces, so rows written before the revamp still decode.
nonisolated enum CaptureSource: String, Codable, CaseIterable, Sendable {
    case manual
    case fridgePhoto
    case groceryCheckoff
    case receiptScan
    case barcode
    case voiceShortcut
    case autoRestock

    nonisolated var displayName: String {
        switch self {
        case .manual: "Added by hand"
        case .fridgePhoto: "Spotted in a photo"
        case .groceryCheckoff: "Ticked off the list"
        case .receiptScan: "Read off a receipt"
        case .barcode: "Scanned"
        case .voiceShortcut: "Added by voice"
        case .autoRestock: "Assumed restocked"
        }
    }

    /// How strongly to believe this evidence the moment it lands.
    ///
    /// Typing something in is a person telling you a fact. A grocery check-off
    /// is nearly as good — they were holding it. A photo is the weakest of the
    /// real signals, because a camera cannot see behind the milk.
    nonisolated var initialConfidence: Double {
        switch self {
        case .manual, .voiceShortcut: 1.0
        case .barcode: 0.95
        case .groceryCheckoff: 0.95
        case .receiptScan: 0.9
        case .fridgePhoto: 0.85
        case .autoRestock: 0.5
        }
    }

    /// The most this source is ever allowed to claim, however sure the thing
    /// supplying it says it is. A vision model reporting 0.99 on a carton of
    /// milk still has not seen what is behind it.
    nonisolated var confidenceCap: Double {
        switch self {
        case .fridgePhoto: 0.85
        case .receiptScan: 0.9
        case .autoRestock: 0.5
        case .manual, .voiceShortcut, .barcode, .groceryCheckoff: 1.0
        }
    }
}

// MARK: - Item

@Model
final class PantryItem {
    @Attribute(.unique) var id: UUID

    /// What the user sees: "Roma tomatoes". The canonical form for matching is
    /// computed from this — see the extension below.
    @Attribute(originalName: "name") var displayName: String

    var category: GroceryCategory
    var tier: PantryTier = PantryTier.stock
    var location: StorageLocation = StorageLocation.pantry

    // Quantity is deliberately fuzzy. Both of these are optional and it is
    // normal for both to be nil: you cannot know that half the onion got used,
    // and pretending otherwise is how the numbers stop meaning anything.
    var quantity: Double?
    var unit: String?
    var looseAmount: LooseAmount?

    /// How strongly this item was believed at `lastConfirmedAt`. Set from the
    /// capture source, or from the source's cap and whatever evidence came
    /// with it. Decay is applied on read, not written back into this.
    var confidenceAtConfirmation: Double = 1.0

    /// When someone or something last established that this is really here.
    ///
    /// `.distantPast` is the sentinel for a row written before the revamp:
    /// see `hasBeenBackfilled` below. A real confirmation is never distantPast.
    var lastConfirmedAt: Date = Date.distantPast

    var addedAt: Date
    @Attribute(originalName: "source") var addedVia: CaptureSource

    /// A date the *user* read off the package. Authoritative where it exists,
    /// and always preferred over the app's own estimate — the app is guessing
    /// from a shelf-life table and the package is not.
    var expiresAt: Date?

    /// When an opened package was opened. Opened things spoil faster, and the
    /// use-by estimate takes this into account.
    var openedAt: Date?

    /// "Always assume I have this." Holds confidence at full regardless of
    /// tier or age.
    var isPinned: Bool = false

    /// When this row was put away, having decayed out of the active list or
    /// been marked gone. Nil for everything on the shelf.
    ///
    /// Archived, never deleted. Users find silent disappearance unnerving and
    /// it destroys trust in the whole feature — and the row is still worth
    /// something afterwards, because restock prediction learns from what you
    /// used to have.
    var archivedAt: Date?

    var notes: String?

    init(
        id: UUID = UUID(),
        displayName: String,
        quantity: Double? = nil,
        unit: String? = nil,
        looseAmount: LooseAmount? = nil,
        category: GroceryCategory = .other,
        tier: PantryTier = .stock,
        location: StorageLocation? = nil,
        confidenceAtConfirmation: Double? = nil,
        lastConfirmedAt: Date? = nil,
        addedAt: Date = .now,
        expiresAt: Date? = nil,
        openedAt: Date? = nil,
        isPinned: Bool = false,
        archivedAt: Date? = nil,
        notes: String? = nil,
        addedVia: CaptureSource = .manual
    ) {
        self.id = id
        self.displayName = displayName
        self.quantity = quantity
        self.unit = unit
        self.looseAmount = looseAmount
        self.category = category
        self.tier = tier
        self.location = location ?? StorageLocation.inferred(from: category)
        self.confidenceAtConfirmation = min(
            confidenceAtConfirmation ?? addedVia.initialConfidence,
            addedVia.confidenceCap
        )
        // A new row is confirmed by the act of being written. Falling back to
        // `addedAt` rather than `.now` keeps a backdated import honest.
        self.lastConfirmedAt = lastConfirmedAt ?? addedAt
        self.addedAt = addedAt
        self.expiresAt = expiresAt
        self.openedAt = openedAt
        self.isPinned = isPinned
        self.archivedAt = archivedAt
        self.notes = notes
        self.addedVia = addedVia
    }
}

// MARK: - Derived

extension PantryItem {

    // MARK: - Confidence

    /// Whether this row has been put away. Archived rows are excluded from
    /// every active query and from everything the Sous Chef reads.
    var isArchived: Bool { archivedAt != nil }

    /// Whether age says anything about this row. Staples and pinned rows are a
    /// standing statement that it is always in.
    var neverDecays: Bool {
        isPinned || !tier.decays
    }

    /// Everything the decay engine needs, in a form that does not drag
    /// SwiftData along with it.
    var evidence: PantryEvidence {
        PantryEvidence(
            canonicalName: canonicalName,
            category: category,
            strength: confidenceAtConfirmation,
            confirmedAt: lastConfirmedAt,
            expiresAt: expiresAt,
            neverDecays: neverDecays
        )
    }

    /// How sure the app is this is still here, on `date`.
    ///
    /// Computed every time rather than stored — see the note at the top of
    /// `PantryConfidence` for why that is the whole point.
    func confidence(at date: Date = .now) -> Double {
        PantryConfidence.confidence(of: evidence, at: date)
    }

    func band(at date: Date = .now) -> PantryConfidenceBand {
        PantryConfidence.band(of: evidence, at: date)
    }

    /// Marks this row as confirmed present, right now.
    ///
    /// The one way confidence goes back up. Takes the stronger of what is
    /// already believed and the new evidence, so a weak signal can never talk
    /// down a strong one: a fridge photo spotting milk that was ticked off the
    /// list this morning must not make the app *less* sure there is milk.
    func confirm(at date: Date = .now, strength: Double = 1.0) {
        lastConfirmedAt = date
        confidenceAtConfirmation = max(confidenceAtConfirmation, min(max(strength, 0), 1))
        archivedAt = nil
    }

    // MARK: - Naming

    /// The canonical food name, for matching against recipes, the taste
    /// profile and the shopping list.
    ///
    /// Computed, not stored: `IngredientCanonicalizer` is the one place that
    /// answers this question for the whole app, and a stored copy here would
    /// be a cache that silently disagrees with it the next time it improves.
    var canonicalName: String {
        IngredientCanonicalizer.canonical(displayName)
    }

    /// False for a row written before the revamp, which has never had a tier,
    /// a location or a real `lastConfirmedAt` worked out for it.
    ///
    /// One marker for the whole row rather than a flag per field: everything
    /// `PantryBackfill` sets, it sets together, so one sentinel is enough and
    /// there is no half-migrated state to reason about.
    var hasBeenBackfilled: Bool {
        lastConfirmedAt != .distantPast
    }

    /// How the amount reads on screen, whether it was counted or guessed at.
    var amountDescription: String? {
        let measured = FractionFormatter.quantityString(quantity: quantity, unit: unit)
        if !measured.isEmpty { return measured }
        return looseAmount?.displayName
    }

    /// Days until the user's own recorded date, or nil when they never set one.
    ///
    /// This is deliberately *not* the shelf-life estimate. The estimate is a
    /// guess the app makes and labels as a guess; this is a date somebody read
    /// off a package. P8 adds the estimate alongside, and where both exist
    /// this one wins.
    func daysUntilExpiry(now: Date = .now) -> Int? {
        guard let expiresAt else { return nil }
        return Calendar.current.dateComponents([.day], from: now, to: expiresAt).day
    }

    /// Items within three days float to the top with an amber tint (§5.8).
    func isExpiringSoon(now: Date = .now) -> Bool {
        guard let days = daysUntilExpiry(now: now) else { return false }
        return days <= 3
    }

    func isExpired(now: Date = .now) -> Bool {
        guard let days = daysUntilExpiry(now: now) else { return false }
        return days < 0
    }
}
