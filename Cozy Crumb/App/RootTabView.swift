//
//  RootTabView.swift
//  Cozy Crumb
//
//  Tab shell. Every tab is a real screen now. Preferences are read here and
//  carried down through the environment, so one place decides the accent, the
//  appearance and whether haptics fire.
//

import SwiftData
import SwiftUI

enum CozyTab: Hashable {
    case library
    case groceries
    case sousChef
    case pantry
    case settings

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
        .tint(accent.deep)
        .environment(\.accentPalette, accent)
        .environment(\.hapticsEnabled, hapticsEnabled)
        .preferredColorScheme(appearance.colorScheme)
        .onOpenURL { url in
            guard case .importRecipe(let link)? = CozyDeepLink(url: url) else { return }

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
