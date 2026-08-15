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

enum CozyCrumbMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CozyCrumbSchemaV1.self]
    }

    /// Empty while V1 is the only schema. Each future version appends one stage.
    static var stages: [MigrationStage] {
        []
    }
}
