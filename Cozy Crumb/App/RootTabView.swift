//
//  RootTabView.swift
//  Cozy Crumb
//
//  Tab shell. Every tab is a real screen now. Preferences are read here and
//  carried down through the environment, so one place decides the accent, the
//  appearance and whether haptics fire.
//
//  The `TabView` is still here with the system bar hidden, and `MascotTabBar`
//  drives its selection from the bottom inset. See the note at the top of that
//  file for why the container stays: it owns the five children, so each tab
//  keeps its own NavigationStack across a switch.
//

import SwiftData
import SwiftUI
import os

enum CozyTab: String, Hashable, CaseIterable, Identifiable {
    case library
    case groceries
    case sousChef
    case pantry
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: "Cookbook"
        case .groceries: "Groceries"
        case .sousChef: "Sous Chef"
        case .pantry: "Pantry"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .library: "books.vertical.fill"
        case .groceries: "checklist"
        case .sousChef: "sparkles"
        case .pantry: "refrigerator.fill"
        case .settings: "gearshape.fill"
        }
    }

}

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage(CozyDefaultsKey.accentPalette) private var accentRaw = AccentPalette.blush.rawValue
    @AppStorage(CozyDefaultsKey.hapticsEnabled) private var hapticsEnabled = true
    /// Defaults to whatever the old dark-mode switch was set to, so upgrading
    /// doesn't silently change how the app looks.
    @AppStorage(CozyDefaultsKey.appearance) private var appearanceRaw = AppAppearance.stored().rawValue

    /// Called the moment a shared link arrives, so the launch splash can get
    /// out of the way rather than making the import wait behind it.
    var onSharedLink: () -> Void = {}

    @State private var selection: CozyTab = .library
    /// A link handed over from outside the app — the share extension, a
    /// shortcut, anything that opens the cozycrumb:// scheme.
    @State private var sharedLink: SharedLink?

    private var accent: AccentPalette {
        AccentPalette(rawValue: accentRaw) ?? .blush
    }

    private var accentBinding: Binding<AccentPalette> {
        Binding(
            get: { accent },
            set: { accentRaw = $0.rawValue }
        )
    }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { appearance },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(CozyTab.library.title, systemImage: CozyTab.library.symbol, value: .library) {
                LibraryView()
            }
            Tab(CozyTab.groceries.title, systemImage: CozyTab.groceries.symbol, value: .groceries) {
                GroceriesView()
            }
            Tab(CozyTab.sousChef.title, systemImage: CozyTab.sousChef.symbol, value: .sousChef) {
                SousChefView()
            }
            Tab(CozyTab.pantry.title, systemImage: CozyTab.pantry.symbol, value: .pantry) {
                PantryView()
            }
            Tab(CozyTab.settings.title, systemImage: CozyTab.settings.symbol, value: .settings) {
                SettingsView(
                    accentSelection: accentBinding,
                    appearance: appearanceBinding
                )
            }
        }
        // The system bar goes away, but its owner does not — every tab keeps
        // the NavigationStack it had. The `Tab` labels above are still
        // required and are what VoiceOver would fall back to if this hiding
        // ever stopped taking effect.
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MascotTabBar(selection: $selection)
        }
        .tint(accent.deep)
        .environment(\.accentPalette, accent)
        .environment(\.hapticsEnabled, hapticsEnabled)
        .preferredColorScheme(appearance.colorScheme)
        .onOpenURL { url in
            guard case .importRecipe(let link)? = CozyDeepLink(url: url) else {
                Log.app.error("Ignored an unrecognised link: \(url.scheme ?? "none", privacy: .public)://…")
                return
            }

            Log.app.info("Opened with a shared link to import")

            onSharedLink()

            // The Cookbook is where a new recipe belongs, and switching first
            // means cancelling the import leaves you somewhere sensible.
            selection = .library
            sharedLink = SharedLink(url: link)
        }
        .sheet(item: $sharedLink) { link in
            ImportFlowView(initialURL: link.url)
        }
        // Every pass below is synchronous and runs on the main actor, over a
        // store that grows with use. On a fresh simulator they are instant,
        // which is exactly why they are worth timing on a real phone: a launch
        // that is merely slow here and a launch that is stuck are the same
        // black screen to whoever is holding it.
        .task {
            LaunchTrace.mark("launch passes started")

            await pass("seed") { SeedData.installIfNeeded(in: modelContext) }
            // Re-reads ingredient lines saved before the caption parsing
            // fixes, so recipes already in the library start scaling too.
            await pass("ingredient repair") { await IngredientRepair.run(in: modelContext) }
            // Drops taste signals old enough that decay has already made them
            // worthless. Once a day at most; see SignalRetention.
            await pass("signal retention") { SignalRetention.runIfDue(in: modelContext) }
            // Pantry rows written before the revamp have no tier, no
            // location and no real confirmation date; a fresh kitchen has no
            // staples. Both are one pass, and it skips rows it has seen.
            await pass("pantry backfill") { PantryBackfill.run(in: modelContext) }
            // Anything that has decayed past the point of being believable
            // gets put away — archived, never deleted, and restorable with one
            // tap. See PantryDecay.
            await pass("pantry decay") { PantryDecay.archiveLapsed(in: modelContext) }
            // Recipes saved before the classifier existed have no cuisine,
            // and cuisine is most of what the taste profile talks about.
            await pass("cuisine backfill") { await CuisineBackfill.run(in: modelContext) }
            // The recipes they mean to make and never do. Once a day.
            await pass("aspiration gap") { AspirationGapDetector.runIfDue(in: modelContext) }
            await pass("taste profile") { TasteProfileStore.rebuildIfStale(in: modelContext) }

            LaunchTrace.mark("launch passes finished")
            // Got all the way through, so the next launch has nothing to
            // report about this one.
            LaunchTrace.markLaunchComplete()
        }
    }

    /// Runs one launch pass, times it, and then hands the main actor back.
    ///
    /// Every one of these is synchronous and main-actor bound, and together
    /// they walk the whole store: `IngredientRepair` re-parses every ingredient
    /// line, `CuisineBackfill` classifies every recipe. Run back to back they
    /// hold the main actor for as long as all of them take combined, and
    /// nothing can redraw in the meantime — on a real cookbook that is an app
    /// sitting on its splash with no way to tell it apart from a hang.
    ///
    /// Sleeping a frame between them does not make any single pass faster, but
    /// it lets SwiftUI draw in the gaps, so the app comes up and stays honest
    /// about what it is doing. The timings say which pass is the expensive one
    /// rather than leaving it to be guessed at.
    private func pass(_ name: String, _ work: () async -> Void) async {
        await work()
        LaunchTrace.mark("pass: \(name)")
        // A frame, not a yield: `Task.yield()` can resume on the same runloop
        // turn without anything being drawn, which is the whole point here.
        try? await Task.sleep(for: .milliseconds(16))
    }
}

#Preview("Tabs") {
    RootTabView()
        .modelContainer(PreviewData.container)
        .environment(KitchenTimers(usesNotifications: false))
}

#Preview("Tabs — dark") {
    RootTabView()
        .modelContainer(PreviewData.container)
        .environment(KitchenTimers(usesNotifications: false))
        .preferredColorScheme(.dark)
}

// MARK: - Shared links

/// A link from outside the app, wrapped so `.sheet(item:)` can present it —
/// `URL` isn't `Identifiable`, and sharing the same link twice should open the
/// importer both times.
private struct SharedLink: Identifiable {
    let id = UUID()
    let url: URL
}
