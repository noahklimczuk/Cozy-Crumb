//
//  CozyCrumbSchema.swift
//  Cozy Crumb
//
//  Versioned schema and migration plan. Established in Phase 0 with only V1 so
//  that adding V2 later is a additive change rather than a retrofit.
//
//  Phase 2 expands V1 in place (adding the full Recipe fields plus Ingredient,
//  RecipeStep, Collection, GroceryList, GroceryItem, PantryItem, CookLog).
//  That is safe precisely because nothing has shipped yet — once the app is on
//  a device with real data, changes require a new VersionedSchema and a
//  MigrationStage instead.
//

import SwiftData

enum CozyCrumbSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Recipe.self]
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
