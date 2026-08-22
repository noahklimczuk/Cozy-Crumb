//
//  CozyCrumbSchema.swift
//  Cozy Crumb
//
//  The schema the app opens, and the migration plan around it.
//
//  A note on versioning, learned the hard way. A `VersionedSchema` does not
//  hold a snapshot of your models — it holds a *list of the live Swift types*
//  and reflects over them at runtime. So two versions can only describe
//  different shapes if each one owns its own copy of every model class it
//  names. With a single set of `@Model` types, every version necessarily
//  describes the same shape, and listing a model in one version but not
//  another is not a description of history — it's a broken schema.
//
//  Adding `PlannedMeal` while leaving it out of V1's list meant V1 named
//  `Recipe`, whose relationship pointed at a model V1 didn't contain.
//  SwiftData traps on that rather than throwing, so the container's
//  in-memory fallback never got a chance and the app died on launch.
//
//  Until a change actually needs custom migration logic, additive changes
//  ride SwiftData's inferred migration: add the model here, and an existing
//  store gains the new table on next open. When a genuinely breaking change
//  arrives, that's the point to take snapshot copies of the models into a
//  versioned namespace and add a real `MigrationStage` between them.
//

import SwiftData

enum CozyCrumbSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    /// Every `@Model` in the app. A model reachable by a relationship but
    /// missing from this list is the crash described above.
    static var models: [any PersistentModel.Type] {
        [
            Recipe.self,
            Ingredient.self,
            RecipeStep.self,
            RecipeCollection.self,
            CookLog.self,
            GroceryList.self,
            GroceryItem.self,
            PantryItem.self,
            PlannedMeal.self,
            TasteSignal.self,
            TasteProfile.self
        ]
    }
}

/// The schema the app opens. Points at the newest version.
typealias CozyCrumbCurrentSchema = CozyCrumbSchemaV1

enum CozyCrumbMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CozyCrumbSchemaV1.self]
    }

    /// Empty while one schema is the whole history. Each future version
    /// appends one stage — see the note at the top before adding one.
    static var stages: [MigrationStage] {
        []
    }
}
