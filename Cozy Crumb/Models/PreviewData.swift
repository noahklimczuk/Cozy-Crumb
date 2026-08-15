//
//  PreviewData.swift
//  Cozy Crumb
//
//  In-memory containers for #Preview blocks. Previews are the design feedback
//  loop, so every screen gets real data to render.
//

import Foundation
import SwiftData

@MainActor
enum PreviewData {

    /// Container preloaded with the sample recipes and collections.
    static let container: ModelContainer = {
        let container = makeContainer()

        let weeknight = RecipeCollection(name: "Weeknight")
        let baking = RecipeCollection(name: "Baking")
        let comfort = RecipeCollection(name: "Mom's")

        for collection in [weeknight, baking, comfort] {
            container.mainContext.insert(collection)
        }

        let pairs: [(Recipe, [RecipeCollection])] = [
            (SeedData.bananaBread(), [baking]),
            (SeedData.misoSalmon(), [weeknight]),
            (SeedData.cacioEPepe(), [weeknight]),
            (SeedData.chickpeaCurry(), [weeknight]),
            (SeedData.roastChicken(), [comfort])
        ]

        for (recipe, collections) in pairs {
            container.mainContext.insert(recipe)
            recipe.collections = collections
        }

        return container
    }()

    /// Container with nothing in it, for empty states.
    static let emptyContainer: ModelContainer = makeContainer()

    private static func makeContainer() -> ModelContainer {
        let schema = Schema(versionedSchema: CozyCrumbSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // Previews only — a container that cannot be built has nothing to show.
            fatalError("Preview container failed: \(error)")
        }
    }
}
