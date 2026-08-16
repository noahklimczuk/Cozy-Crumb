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
            try? await Task.sleep(for: .milliseconds(850))
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
                CupcakeMark(size: 168)
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

/// The in-app counterpart to the app-icon cupcake: intentionally drawn from
/// simple shapes so it stays crisp at every launch-screen size.
private struct CupcakeMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(CozyColor.blushSoft)

            VStack(spacing: -size * 0.12) {
                frosting
                wrapper
            }
            .padding(size * 0.12)
        }
        .frame(width: size, height: size)
    }

    private var frosting: some View {
        ZStack {
            HStack(spacing: -size * 0.12) {
                Circle().fill(CozyColor.creamDeep)
                Circle().fill(CozyColor.creamDeep)
                Circle().fill(CozyColor.creamDeep)
            }
            .frame(width: size * 0.72, height: size * 0.32)

            VStack(spacing: size * 0.05) {
                HStack(spacing: size * 0.18) {
                    Capsule().fill(CozyColor.inkPrimary).frame(width: size * 0.035, height: size * 0.065)
                    Capsule().fill(CozyColor.inkPrimary).frame(width: size * 0.035, height: size * 0.065)
                }
                SplashSmileShape()
                    .stroke(CozyColor.inkPrimary, style: StrokeStyle(lineWidth: size * 0.025, lineCap: .round))
                    .frame(width: size * 0.17, height: size * 0.075)
            }
            .offset(y: size * 0.03)

            Circle()
                .fill(CozyColor.danger)
                .frame(width: size * 0.12, height: size * 0.12)
                .offset(y: -size * 0.22)
        }
        .frame(height: size * 0.42)
    }

    private var wrapper: some View {
        CupcakeWrapperShape()
            .fill(CozyColor.blushDeep.opacity(0.82))
            .overlay {
                CupcakeWrapperShape()
                    .stroke(CozyColor.outlineStrong, lineWidth: size * 0.018)
            }
            .overlay {
                HStack(spacing: size * 0.10) {
                    Capsule().fill(CozyColor.blushDeep.opacity(0.7))
                    Capsule().fill(CozyColor.blushDeep.opacity(0.7))
                    Capsule().fill(CozyColor.blushDeep.opacity(0.7))
                }
                .padding(.vertical, size * 0.10)
            }
            .frame(width: size * 0.48, height: size * 0.32)
    }
}

private struct CupcakeWrapperShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct SplashSmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: rect.midX, y: rect.maxY * 1.8)
            )
        }
    }
}
