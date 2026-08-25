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

    /// Kitchen timers live above every screen. A timer started in Cook Mode
    /// has to keep counting while the user wanders off to the shopping list,
    /// so this cannot belong to a view that gets torn down.
    @State private var timers = KitchenTimers()

    /// Set when a link arrives from the share sheet. Someone who shared a
    /// recipe is waiting on the importer, not on the cupcake.
    @State private var isSplashSkipped = false

    init() {
        LaunchTrace.mark("app init")
        modelContainer = Self.makeModelContainer()
        LaunchTrace.mark("model container ready")
    }

    var body: some Scene {
        WindowGroup {
            AppLaunchView(isSkipped: isSplashSkipped) {
                RootTabView(onSharedLink: { isSplashSkipped = true })
            }
            .environment(timers)
        }
        .modelContainer(modelContainer)
    }

    /// Builds the persistent store, falling back to an in-memory store so a
    /// corrupt or unreadable store shows an empty app rather than a launch
    /// crash. The final `fatalError` is genuinely unrecoverable — if an
    /// in-memory container cannot be created there is no app to run.
    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema(versionedSchema: CozyCrumbCurrentSchema.self)

        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: CozyCrumbMigrationPlan.self,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            )
            // Named separately from "model container ready" so the log
            // distinguishes a store that opened from one that quietly fell
            // back — an app that came up empty is a different bug report.
            LaunchTrace.mark("persistent store opened")
            return container
        } catch {
            Log.data.error(
                "Persistent store unavailable, falling back to in-memory: \(error.localizedDescription, privacy: .public)"
            )
        }

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
            LaunchTrace.mark("in-memory store opened")
            return container
        } catch {
            fatalError("Could not create an in-memory ModelContainer: \(error)")
        }
    }
}

/// A short, branded handoff after iOS's system launch screen. Keeping this in
/// SwiftUI lets the cupcake greet the user while SwiftData opens the store.
private struct AppLaunchView<Content: View>: View {
    /// Cuts the greeting short — set when the app was opened to do something
    /// specific, like import a shared link.
    let isSkipped: Bool
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
        // The single most useful line in the log. Reaching it means SwiftUI
        // evaluated this whole ZStack — the splash *and* `content()`, which is
        // the entire RootTabView — and put a frame on screen. Not reaching it
        // means the app is still on the system launch screen, and everything
        // after this point in launch is irrelevant to whatever went wrong.
        .onAppear { LaunchTrace.mark("first frame on screen") }
        .task {
            try? await Task.sleep(for: .seconds(4))
            LaunchTrace.mark("splash dismissed")
            hideSplash()
        }
        .onChange(of: isSkipped) { _, skipped in
            guard skipped else { return }
            hideSplash()
        }
    }

    private func hideSplash() {
        guard isShowingSplash else { return }

        withAnimation(.easeOut(duration: 0.28)) {
            isShowingSplash = false
        }
    }
}

private struct CupcakeSplashView: View {
    var body: some View {
        ZStack {
            // Sampled from the supplied icon's pink edge so the artwork appears
            // to melt directly into the launch background — and a deep version
            // of the same pink after dark, so the first thing anybody sees at
            // night isn't a full-screen flash of it.
            Color(light: Color(red: 254 / 255, green: 193 / 255, blue: 190 / 255),
                  dark: Color(hex: "5A3238"))
                .ignoresSafeArea()

            VStack(spacing: CozySpacing.l) {
                Image("CupcakeLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 210, height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                // inkOnAccent, because this pink is an accent surface like any
                // other: it goes deep after dark and the ink goes light with
                // it. Set in inkPrimary, as it was, the app's own name was
                // rendering in #F2E7E0 on pale pink on the first screen
                // anybody sees.
                Text(AppBranding.appName)
                    .cozyText(CozyFont.title, color: CozyColor.inkOnAccent)
                    .cozyDisplayTracking(CozyTracking.title, relativeTo: .title)
                Text(AppBranding.tagline)
                    .cozyText(CozyFont.subheadline, color: CozyColor.inkOnAccent)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cozy Crumb is loading")
    }
}
