//
//  RecipeDetailViewModel.swift
//  Cozy Crumb
//
//  Transient state for one recipe screen: how many servings the user has
//  dialled to, and which ingredients they've ticked off.
//
//  Ticks are deliberately ephemeral (§5.3) — they reset when you leave. They
//  are a "where was I" aid while shopping or prepping, not saved data.
//

import Foundation
import SwiftUI

@Observable
@MainActor
final class RecipeDetailViewModel {
    /// What the recipe was written for. Scaling is always relative to this.
    let originalServings: Int

    var servings: Int
    var checkedIngredientIDs: Set<UUID> = []
    var isLoggingCook = false
    var isCelebrating = false

    init(recipe: Recipe) {
        let original = max(1, recipe.servings)
        self.originalServings = original
        self.servings = original
    }

    var isScaled: Bool {
        servings != originalServings
    }

    var scaleFactor: Double {
        ServingsScaler.factor(from: originalServings, to: servings)
    }

    /// "double", "half", or nil when it isn't a tidy multiple — used for the
    /// little caption beside the stepper.
    var scaleDescription: String? {
        guard isScaled else { return nil }

        return switch scaleFactor {
        case 2.0: "double batch"
        case 3.0: "triple batch"
        case 0.5: "half batch"
        default: nil
        }
    }

    func isChecked(_ ingredient: Ingredient) -> Bool {
        checkedIngredientIDs.contains(ingredient.id)
    }

    func toggle(_ ingredient: Ingredient) {
        if checkedIngredientIDs.contains(ingredient.id) {
            checkedIngredientIDs.remove(ingredient.id)
        } else {
            checkedIngredientIDs.insert(ingredient.id)
        }
    }

    func increaseServings() {
        servings = min(servings + 1, 99)
    }

    func decreaseServings() {
        servings = max(servings - 1, 1)
    }

    func resetServings() {
        servings = originalServings
    }
}
