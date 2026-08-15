//
//  RecipeCollection.swift
//  Cozy Crumb
//
//  User-created pastel groups: "Weeknight", "Baking", "Mom's".
//
//  Named RecipeCollection rather than Collection because `Collection` is a
//  Swift standard library protocol — shadowing it module-wide would make
//  every generic constraint in the app ambiguous.
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class RecipeCollection {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    /// Inverse is declared on Recipe.collections.
    var recipes: [Recipe]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        recipes: [Recipe] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.recipes = recipes
    }
}

extension RecipeCollection {
    /// Stable pastel derived from the name, so a collection keeps its colour.
    var tint: Color {
        CozyColor.rotatedAccent(for: name)
    }

    var recipeCount: Int { recipes.count }
}
