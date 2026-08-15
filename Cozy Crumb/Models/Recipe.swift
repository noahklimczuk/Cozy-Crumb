//
//  Recipe.swift
//  Cozy Crumb
//
//  Phase 0 scaffold: deliberately minimal so the ModelContainer and migration
//  plan are proven end to end. Phase 2 fills in the full shape from the spec —
//  summary, sourceURL, sourceKind, heroImageData, servings, timings,
//  ingredients, steps, tags, collections, rating, notes, cookLogs and
//  importConfidence — and expands CozyCrumbSchemaV1 alongside it.
//

import Foundation
import SwiftData

@Model
final class Recipe {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
