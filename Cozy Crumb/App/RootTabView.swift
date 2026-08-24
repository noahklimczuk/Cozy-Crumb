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
        .task {
            SeedData.installIfNeeded(in: modelContext)
            // Re-reads ingredient lines saved before the caption parsing
            // fixes, so recipes already in the library start scaling too.
            IngredientRepair.run(in: modelContext)
            // Drops taste signals old enough that decay has already made them
            // worthless. Once a day at most; see SignalRetention.
            SignalRetention.runIfDue(in: modelContext)
            // Recipes saved before the classifier existed have no cuisine,
            // and cuisine is most of what the taste profile talks about.
            CuisineBackfill.run(in: modelContext)
            // The recipes they mean to make and never do. Once a day.
            AspirationGapDetector.runIfDue(in: modelContext)
            TasteProfileStore.rebuildIfStale(in: modelContext)
        }
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
