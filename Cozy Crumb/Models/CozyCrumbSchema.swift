//
//  CozyCrumbSchema.swift
//  Cozy Crumb
//
//  Versioned schema and migration plan, established in Phase 0 so that adding
//  V2 later is additive rather than a retrofit.
//
//  Phase 2 filled V1 out in place with the complete model set. That was safe
//  only because nothing had shipped. From here on, changing any @Model means a
//  new VersionedSchema plus a MigrationStage — editing V1 would corrupt an
//  existing install.
//

import SwiftData

enum CozyCrumbSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            Recipe.self,
            Ingredient.self,
            RecipeStep.self,
            RecipeCollection.self,
            CookLog.self,
            GroceryList.self,
            GroceryItem.self,
            PantryItem.self
        ]
    }
}

/// Adds the week planner. Purely additive — a new `PlannedMeal` model and the
/// cascade relationship on `Recipe` that owns it — so the migration is
/// lightweight and no existing recipe, list or log is touched.
enum CozyCrumbSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

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
            PlannedMeal.self
        ]
    }
}

/// The schema the app opens. Bump this alongside the newest version above.
typealias CozyCrumbCurrentSchema = CozyCrumbSchemaV2

enum CozyCrumbMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CozyCrumbSchemaV1.self, CozyCrumbSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CozyCrumbSchemaV1.self, toVersion: CozyCrumbSchemaV2.self)
        ]
    }
}
