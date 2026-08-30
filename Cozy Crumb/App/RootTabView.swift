//
//  RootTabView.swift
//  Cozy Crumb
//
//  Tab shell. Every tab is a real screen now. Preferences are read here and
//  carried down through the environment, so one place decides the accent, the
//  appearance and whether haptics fire.
//
//  The `TabView` is still here with the system bar hidden, and `MascotTabBar`
//  drives its selection from an overlay at the bottom. See the note at the top
//  of that file for why the container stays: it owns the five children, so each
//  tab keeps its own NavigationStack across a switch.
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

    /// `LaunchOptions.startTab` is nil unless a launch argument named one, so
    /// this is `.library` for everybody who is not a screenshot.
    @State private var selection: CozyTab = LaunchOptions.startTab ?? .library

    /// The window's own bottom inset — the home indicator, nothing else. Read
    /// outside the `TabView`, where the hidden tab bar has not been added yet.
    @State private var windowBottomInset: CGFloat = 0

    /// What a tab is actually handed, reported by `TabInsetProbe`.
    @State private var tabSystemBottom: CGFloat?
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

    /// How much each tab pads its own bottom.
    ///
    /// The bar is an overlay aligned to the window's safe area, so its top edge
    /// sits `tabBarTotalHeight` above the home indicator and content has to
    /// stop in the same place — a total bottom inset of
    /// `windowBottom + tabBarTotalHeight`. The tab already has some of that,
    /// so this is only the remainder.
    ///
    /// Whatever the tab is short by, and never less. `max` and nothing else:
    /// an earlier draft also clamped this *down* to the bar's height, which is
    /// the one way this arithmetic can produce an overlap — if the tab were
    /// ever handed less than the window, capping the top-up would leave
    /// content under the bar. Uncapped, a low reading simply pads more.
    ///
    /// Every remaining way to be wrong leaves *more* room than needed, which
    /// is the gap that is already there today — never less. Until the probe
    /// reports, `system` falls back to `windowBottom`, which makes this the
    /// bar's full height: exactly the behaviour being replaced.
    private var tabBarPadding: CGFloat {
        let system = tabSystemBottom ?? windowBottomInset
        let target = windowBottomInset + CozyMetrics.tabBarTotalHeight
        return max(0, target - system)
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(CozyTab.library.title, systemImage: CozyTab.library.symbol, value: .library) {
                // The probe is a sibling of the padded screen, not inside it.
                // That is the point: nothing pads it, so what it reads is what
                // the tab was handed. See `TabInsetProbe`.
                //
                // One tab carries it because the inset belongs to the
                // `TabView`, not to any screen in it.
                ZStack {
                    TabInsetProbe(systemBottom: $tabSystemBottom)
                    LibraryView().cozyTabBarClearance()
                }
            }
            Tab(CozyTab.groceries.title, systemImage: CozyTab.groceries.symbol, value: .groceries) {
                GroceriesView().cozyTabBarClearance()
            }
            Tab(CozyTab.sousChef.title, systemImage: CozyTab.sousChef.symbol, value: .sousChef) {
                SousChefView().cozyTabBarClearance()
            }
            Tab(CozyTab.pantry.title, systemImage: CozyTab.pantry.symbol, value: .pantry) {
                PantryView().cozyTabBarClearance()
            }
            Tab(CozyTab.settings.title, systemImage: CozyTab.settings.symbol, value: .settings) {
                SettingsView(
                    accentSelection: accentBinding,
                    appearance: appearanceBinding
                )
                .cozyTabBarClearance()
            }
        }
        // The system bar goes away, but its owner does not — every tab keeps
        // the NavigationStack it had. The `Tab` labels above are still
        // required and are what VoiceOver would fall back to if this hiding
        // ever stopped taking effect.
        .toolbar(.hidden, for: .tabBar)
        // An overlay, and the clearance done per tab above, rather than one
        // `safeAreaInset` on the TabView.
        //
        // A safe-area inset on a `TabView` does not reliably reach the views
        // inside its tabs. What it does reach is anything that reads the safe
        // area *outside* — so the bar drew in the right place while the screens
        // under it were laid out as though it were not there. Every screen with
        // a bottom bar of its own put that bar underneath this one: the Sous
        // Chef's composer, the grocery list's export bar, the meal plan's shop
        // bar. They were sitting on the home indicator, which is exactly where
        // a view that has been told about the home indicator and nothing else
        // would sit.
        //
        // An overlay contributes no safe area at all, so there is now exactly
        // one thing insetting content — `cozyTabBarClearance`, applied to each
        // tab's own root, where a plain modifier propagates normally. One
        // source of the number, and no way for the two to disagree.
        .overlay(alignment: .bottom) {
            MascotTabBar(selection: $selection)
        }
        // Measured out here, where the bottom inset is only the home indicator.
        // A background rather than a wrapper: this view is the whole app, and a
        // `GeometryReader` around it would take over the layout of every screen.
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { windowBottomInset = proxy.safeAreaInsets.bottom }
                    .onChange(of: proxy.safeAreaInsets.bottom) { _, new in
                        windowBottomInset = new
                    }
            }
        }
        .environment(\.cozyTabBarPadding, tabBarPadding)
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
        // The shell is on screen and usable, which is what launching means.
        //
        // This used to be recorded at the end of the maintenance passes below,
        // seven of them, several seconds later. Anything that interrupted the
        // app in between — backgrounding it, force-quitting it, iOS reclaiming
        // it — left the launch marked unfinished, and the next one opened in
        // simple mode over a launch that had worked perfectly well.
        .onAppear { LaunchTrace.markLaunchComplete() }
        // Every pass below is synchronous and runs on the main actor, over a
        // store that grows with use. On a fresh simulator they are instant,
        // which is exactly why they are worth timing on a real phone: a launch
        // that is merely slow here and a launch that is stuck are the same
        // black screen to whoever is holding it.
        .task {
            LaunchTrace.mark("launch passes started")

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
