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
            AppLaunchView {
                RootTabView()
            }
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

/// A short, branded handoff after iOS's system launch screen. Keeping this in
/// SwiftUI lets the cupcake greet the user while SwiftData opens the store.
private struct AppLaunchView<Content: View>: View {
    let content: () -> Content

    @State private var isShowingSplash = true

    var body: some View {
        ZStack {
            content()
                .opacity(isShowingSplash ? 0 : 1)

            if isShowingSplash {
                CupcakeSplashView()
                    .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.easeOut(duration: 0.28)) {
                isShowingSplash = false
            }
        }
    }
}

private struct CupcakeSplashView: View {
    var body: some View {
        ZStack {
            CozyColor.blush
                .ignoresSafeArea()

            VStack(spacing: CozySpacing.l) {
                Image("CupcakeLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 210, height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                Text(AppBranding.appName)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(CozyColor.inkPrimary)
                Text("Your cookbook, cozied up.")
                    .cozyText(CozyFont.subheadline, color: CozyColor.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cozy Crumb is loading")
    }
}
