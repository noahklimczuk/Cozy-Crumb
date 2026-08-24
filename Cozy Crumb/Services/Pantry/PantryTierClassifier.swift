//
//  PantryTierClassifier.swift
//  Cozy Crumb
//
//  Which of the three tiers something belongs in, decided at capture so the
//  user never has to.
//
//  Two of the three can be worked out from the food alone. The third cannot:
//  `.someday` means "bought for one recipe, not part of the rotation", and
//  that is a statement about purchase history, not about the food. Miso paste
//  is a one-off in one kitchen and a staple in another, and the only way to
//  tell them apart is to watch how often it gets bought.
//
//  So this classifier returns `.staple` or `.stock`, and `.someday` arrives
//  two ways: the user sets it by hand, or restock prediction (P9) works out
//  that something has been bought exactly once in six months and offers to
//  move it. Guessing `.someday` from the food would mean quietly excluding
//  things from running-low nudges for no reason the user could see.
//

import Foundation

nonisolated enum PantryTierClassifier {

    /// The tier for a newly captured item.
    nonisolated static func tier(
        for rawName: String,
        category: GroceryCategory,
        defaults store: UserDefaults = .standard
    ) -> PantryTier {
        PantryStaples.contains(rawName, defaults: store) ? .staple : .stock
    }

    /// The tier for a row that predates the revamp.
    ///
    /// Same rule, with one exception: a row the user pinned is a statement
    /// that they always have it, which is what `.staple` means.
    nonisolated static func backfillTier(
        for item: PantryItem,
        defaults store: UserDefaults = .standard
    ) -> PantryTier {
        if item.isPinned { return .staple }
        return tier(for: item.displayName, category: item.category, defaults: store)
    }
}
