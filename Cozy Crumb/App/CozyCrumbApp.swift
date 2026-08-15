//
//  CozyCrumbApp.swift
//  Cozy Crumb
//
//  Created by Noah Klimczuk on 2026-08-15.
//

import Foundation
import SwiftData
import SwiftUI
import os

@main
struct CozyCrumbApp: App {
    private let modelContainer: ModelContainer

    init() {
        modelContainer = Self.makeModelContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(modelContainer)
    }

    /// Builds the persistent store, falling back to an in-memory store so a
    /// corrupt or unreadable store shows an empty app rather than a launch
    /// crash. The final `fatalError` is genuinely unrecoverable — if an
    /// in-memory container cannot be created there is no app to run.
    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema(versionedSchema: CozyCrumbSchemaV1.self)

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: CozyCrumbMigrationPlan.self,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            )
        } catch {
            Log.data.error(
                "Persistent store unavailable, falling back to in-memory: \(error.localizedDescription, privacy: .public)"
            )
        }

        do {
            return try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
        } catch {
            fatalError("Could not create an in-memory ModelContainer: \(error)")
        }
    }
}
