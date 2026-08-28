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
    /// Opened off the main thread, which is why it is state rather than a
    /// `let` built in `init()`.
    ///
    /// `init()` runs before the app has a window, so anything slow in it
    /// happens with nothing at all on screen — not even the splash. Opening
    /// the store there meant a store that was slow to open was
    /// indistinguishable from an app that had frozen, and after twenty
    /// seconds the watchdog killed it. Nothing in launch is allowed to be on
    /// the main thread before the first frame any more.
    @State private var modelContainer: ModelContainer?

    /// Kitchen timers live above every screen. A timer started in Cook Mode
    /// has to keep counting while the user wanders off to the shopping list,
    /// so this cannot belong to a view that gets torn down.
    @State private var timers = KitchenTimers()

    /// Set when a link arrives from the share sheet. Someone who shared a
    /// recipe is waiting on the importer, not on the cupcake.
    @State private var isSplashSkipped = false

    var body: some Scene {
        WindowGroup {
            Group {
                if let modelContainer {
                    AppLaunchView(isSkipped: isSplashSkipped) {
                        RootTabView(onSharedLink: { isSplashSkipped = true })
                    }
                    .modelContainer(modelContainer)
                } else {
                    // The same splash, so opening the store looks like part of
                    // the greeting rather than a second screen.
                    CupcakeSplashView()
                }
            }
            .environment(timers)
            .task { await openStore() }
        }
    }

    private func openStore() async {
        guard modelContainer == nil else { return }

        // Read before this launch overwrites the record of the last one.
        CookbookSafeMode.clearIfSetUnderAnOlderRule()
        CookbookSafeMode.latchIfPreviousLaunchFailed()
        LaunchTrace.mark("app init")

        // Detached, so the open runs on a background thread and the splash
        // keeps drawing while it happens. `ModelContainer` is `Sendable`, so
        // handing the finished one back to the main actor is safe.
        let opened = await Task.detached(priority: .userInitiated) {
            Self.makeModelContainer()
        }.value

        modelContainer = opened
        Self.installSampleDataIfRequested(in: opened)
        LaunchTrace.mark("model container ready")
    }

    /// Fills an empty store with the sample recipes, when a launch argument
    /// asked for them. See `LaunchOptions` — this is how CI gets a Cookbook
    /// with something in it to photograph.
    ///
    /// Guarded twice: the argument has to be present, and the store has to be
    /// completely empty. A real cookbook is never touched.
    private static func installSampleDataIfRequested(in container: ModelContainer) {
        guard LaunchOptions.wantsSampleData else { return }

        let context = container.mainContext
        let existing = (try? context.fetchCount(FetchDescriptor<Recipe>())) ?? 1
        guard existing == 0 else { return }

        for recipe in SeedData.allSamples {
            context.insert(recipe)
        }
        try? context.save()
        LaunchTrace.mark("sample data installed")
    }

    /// Builds the persistent store, falling back to an in-memory store so a
    /// corrupt or unreadable store shows an empty app rather than a launch
    /// crash. The final `fatalError` is genuinely unrecoverable — if an
    /// in-memory container cannot be created there is no app to run.
    /// `nonisolated` because it is called from a detached task: the target
    /// defaults types to MainActor, and a MainActor-isolated open would hop
    /// straight back onto the thread this is trying to keep free.
    nonisolated private static func makeModelContainer() -> ModelContainer {
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

/// How long the cupcake holds the screen before handing over.
///
/// It was 3.9 seconds, which is a long time to look at a picture of a cupcake
/// several times a day — and close to the problem this app has actually had.
/// A launch that hangs and a launch that is merely greeting you are the same
/// still image, so four seconds of greeting trains people to read a stall as
/// normal and normal as a stall. It also stretches the window in which
/// backgrounding or force-quitting the app counts as an interrupted launch.
///
/// The store opens in about 40ms, so none of this was ever waiting for
/// anything. 1.1s is long enough to register as a greeting and short enough
/// that nobody wonders whether the app is stuck. One number, easy to move if
/// it reads as hurried.
///
/// At file scope rather than on `AppLaunchView`, which is generic over its
/// content — and Swift has no static stored properties in generic types.
private enum SplashTiming {
    static let dwell: Double = 1.1
}

/// A short, branded handoff after iOS's system launch screen. Keeping this in
/// SwiftUI lets the cupcake greet the user while SwiftData opens the store.
private struct AppLaunchView<Content: View>: View {
    /// Cuts the greeting short — set when the app was opened to do something
    /// specific, like import a shared link.
    let isSkipped: Bool
    let content: () -> Content

    @Environment(\.cozyMotion) private var motion

    @State private var isShowingSplash = true

    /// Whether the app underneath the splash has been built yet.
    ///
    /// This is the fix for a black screen on launch, and the reason is
    /// structural. The splash used to sit in a `ZStack` beside `content()` —
    /// the whole `RootTabView`, held at `opacity(0)`. Opacity is not laziness:
    /// SwiftUI still had to evaluate that entire tree, every tab and every
    /// `@Query`, before it could commit a single frame. So the splash could
    /// not appear until the heaviest screen in the app was ready, and anything
    /// slow or fatal in there took the splash down with it.
    ///
    /// What is on screen in the meantime is iOS's own launch screen, and
    /// because the target sets `INFOPLIST_KEY_UILaunchScreen_Generation` that
    /// is a bare `systemBackground` — pure black after dark. A launch that
    /// never finishes therefore looks like a black screen, and then like a
    /// crash, because the watchdog kills an app that takes too long to draw.
    ///
    /// Now the splash is the first frame on its own: a colour and an image,
    /// with nothing else to evaluate. The app is built one beat later, once
    /// there is something on screen and the watchdog is satisfied.
    @State private var isContentBuilt = false

    var body: some View {
        ZStack {
            if isContentBuilt {
                content()
                    .opacity(isShowingSplash ? 0 : 1)
            }

            if isShowingSplash {
                CupcakeSplashView()
                    .transition(.opacity)
            }
        }
        // Reaching this means a frame is on screen. It now says so about the
        // splash alone, which is the point: it no longer waits on the app.
        .onAppear { LaunchTrace.mark("first frame on screen") }
        .task {
            // Long enough for the splash to actually reach the glass before
            // the app underneath it starts building. A yield is not enough —
            // that returns on the same runloop turn, before anything is drawn.
            try? await Task.sleep(for: .milliseconds(120))
            buildContent()

            // A screenshot two seconds in should be of the app, not of the
            // cupcake. Nothing sets this but CI.
            guard !LaunchOptions.skipsSplash else {
                hideSplash()
                return
            }

            try? await Task.sleep(for: .seconds(SplashTiming.dwell))
            LaunchTrace.mark("splash dismissed")
            hideSplash()
        }
        .onChange(of: isSkipped) { _, skipped in
            guard skipped else { return }
            hideSplash()
        }
    }

    private func buildContent() {
        guard !isContentBuilt else { return }
        isContentBuilt = true
        LaunchTrace.mark("app content built")
    }

    private func hideSplash() {
        // A shared link can cut the greeting short before the timer above has
        // run, so the app has to be built here too — otherwise dismissing the
        // splash early would reveal an empty window.
        buildContent()

        guard isShowingSplash else { return }

        // Through the resolver like everything else. A cross-fade is exactly
        // the kind of thing Reduce Motion asks to be shortened, and this was
        // the one animation in the app still deciding for itself.
        withAnimation(motion(.easeOut(duration: 0.28))) {
            isShowingSplash = false
        }
    }
}

private struct CupcakeSplashView: View {

    var body: some View {
        ZStack {
            // Sampled from the supplied icon's pink edge so the artwork appears
            // to melt directly into the launch background.
            //
            // The same pink in both appearances, like every other accent
            // surface in the app. It used to go to a deep maroon after dark,
            // which is now unreadable rather than merely different: the ink on
            // an accent is one dark value in both appearances, so a ground
            // that flips takes the app's own name down with it.
            Color(red: 254 / 255, green: 193 / 255, blue: 190 / 255)
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
