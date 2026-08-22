//
//  SignalLog.swift
//  Cozy Crumb
//
//  Writes `TasteSignal` rows as a side effect of ordinary use.
//
//  The rule the spec is firm about, and the one that is easiest to break by
//  accident: this never interrupts anyone. There is no "how did that turn
//  out?" prompt, no rating nag, no dialog. Every call site here is already
//  something the user chose to do, and logging it is invisible.
//
//  Two things keep the log from becoming a landfill:
//
//    * Incidental signals coalesce. Opening the same recipe eleven times
//      while cooking from it is one interest, not eleven, so `viewed` and
//      `searched` are dropped if the same target was already logged within
//      the last hour.
//    * `SignalRetention` prunes them once they are old enough that decay has
//      made them worthless anyway.
//
//  A note on what does *not* get its own row. Cooking a Thai curry does not
//  write a signal per ingredient. The signal points at the recipe, and
//  profile derivation (S3) walks recipe → ingredients → tags from there.
//  That keeps one cook as one row, and means correcting a recipe's ingredient
//  list also corrects every inference already drawn from it. `ingredientName`
//  is reserved for signals that genuinely have no recipe behind them — buying
//  something, deleting something off the list, saying you dislike something.
//

import Foundation
import SwiftData
import os

@MainActor
enum SignalLog {

    /// How long an incidental signal about the same thing suppresses another.
    static let coalescingWindow: TimeInterval = 60 * 60

    // MARK: - The one that does the work

    /// Records a signal, unless an identical incidental one is still fresh.
    ///
    /// Returns the signal written, or nil when it was coalesced away — the
    /// return value exists for the tests and the debug screen, and call sites
    /// are free to ignore it.
    @discardableResult
    static func log(
        _ kind: SignalKind,
        recipeID: UUID? = nil,
        ingredientName: String? = nil,
        tag: String? = nil,
        in modelContext: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TasteSignal? {
        let ingredient = normalized(ingredientName)
        let normalizedTag = normalized(tag)

        if kind.isIncidental,
           isDuplicate(
               kind,
               recipeID: recipeID,
               ingredientName: ingredient,
               tag: normalizedTag,
               in: modelContext,
               now: now
           ) {
            return nil
        }

        let signal = TasteSignal(
            kind: kind,
            recipeID: recipeID,
            ingredientName: ingredient,
            tag: normalizedTag,
            timestamp: now,
            context: SignalContext(date: now, calendar: calendar)
        )

        modelContext.insert(signal)
        save(kind, in: modelContext)

        return signal
    }

    // MARK: - Call sites, named after what the user did

    /// Someone tapped "I made this".
    ///
    /// `priorCookCount` is how many cooks were already on the recipe *before*
    /// this one. One or more makes it a repeat, which is the strongest signal
    /// in the system — see `SignalKind.cookedRepeat`.
    static func cooked(
        _ recipe: Recipe,
        priorCookCount: Int,
        rating: Int?,
        in modelContext: ModelContext,
        now: Date = .now
    ) {
        log(
            priorCookCount > 0 ? .cookedRepeat : .cooked,
            recipeID: recipe.id,
            in: modelContext,
            now: now
        )

        guard let rating else { return }

        if rating >= 4 {
            log(.ratedHigh, recipeID: recipe.id, in: modelContext, now: now)
        } else if rating <= 2 {
            log(.ratedLow, recipeID: recipe.id, in: modelContext, now: now)
        }
        // A 3 is a shrug. Logging it as either would be putting words in
        // their mouth.
    }

    /// The heart button. Un-favouriting is not logged as a negative — people
    /// tidy their favourites, and reading that as dislike would punish
    /// housekeeping.
    static func favorited(_ recipe: Recipe, isNowFavorite: Bool, in modelContext: ModelContext) {
        guard isNowFavorite else { return }
        log(.favorited, recipeID: recipe.id, in: modelContext)
    }

    static func addedToCollection(_ recipe: Recipe, in modelContext: ModelContext) {
        log(.addedToCollection, recipeID: recipe.id, in: modelContext)
    }

    static func imported(_ recipe: Recipe, in modelContext: ModelContext) {
        log(.imported, recipeID: recipe.id, in: modelContext)
    }

    /// A recipe screen was opened.
    static func viewed(_ recipe: Recipe, in modelContext: ModelContext) {
        log(.viewed, recipeID: recipe.id, in: modelContext)
    }

    /// The recipe screen stayed open long enough to be read rather than
    /// glanced at. Fired by a cancellable timer, so backing out early logs
    /// nothing.
    static func readProperly(_ recipe: Recipe, in modelContext: ModelContext) {
        log(.viewedLong, recipeID: recipe.id, in: modelContext)
    }

    /// How long a recipe has to stay on screen to count as read.
    static let longViewThreshold: Duration = .seconds(30)

    /// A submitted search. Not every keystroke — the field's onSubmit only.
    static func searched(_ query: String, in modelContext: ModelContext) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return }
        log(.searched, ingredientName: trimmed, in: modelContext)
    }

    /// An item ticked off the shopping list: they bought it.
    static func groceryPurchased(_ item: GroceryItem, in modelContext: ModelContext) {
        log(.groceryPurchased, ingredientName: item.name, in: modelContext)
    }

    /// An item swiped off the shopping list without being bought.
    ///
    /// Logged every time, weighted as it stands. The spec's "3×" qualifier is
    /// a derivation concern, not a logging one — one deletion is a change of
    /// mind, three is a preference, and only the profile builder is in a
    /// position to tell those apart.
    static func groceryDeleted(_ item: GroceryItem, in modelContext: ModelContext) {
        log(.ingredientRemovedFromGrocery, ingredientName: item.name, in: modelContext)
    }

    // MARK: - Internals

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// True when the same incidental signal about the same thing is still
    /// inside the coalescing window.
    ///
    /// The fetch filters on timestamp only and matches the target in Swift:
    /// optional comparisons inside a `#Predicate` are more trouble than they
    /// are worth, and an hour's worth of signals is a handful of rows.
    private static func isDuplicate(
        _ kind: SignalKind,
        recipeID: UUID?,
        ingredientName: String?,
        tag: String?,
        in modelContext: ModelContext,
        now: Date
    ) -> Bool {
        let cutoff = now.addingTimeInterval(-coalescingWindow)
        var descriptor = FetchDescriptor<TasteSignal>(
            predicate: #Predicate { $0.timestamp >= cutoff }
        )
        descriptor.fetchLimit = 200

        guard let recent = try? modelContext.fetch(descriptor) else { return false }

        return recent.contains { signal in
            signal.kind == kind
                && signal.recipeID == recipeID
                && signal.ingredientName == ingredientName
                && signal.tag == tag
        }
    }

    /// Signals are a side effect of something the user was doing, so a failed
    /// save is logged and swallowed. Losing one is a slightly worse
    /// recommendation later; interrupting a cook to say so would be worse.
    private static func save(_ kind: SignalKind, in modelContext: ModelContext) {
        do {
            try modelContext.save()
        } catch {
            // One literal, not two concatenated: an os.Logger message is an
            // OSLogMessage rather than a String, and '+' does not apply.
            Log.data.error(
                "Could not save a \(kind.rawValue, privacy: .public) signal: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
