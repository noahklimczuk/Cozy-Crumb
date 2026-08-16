//
//  RootTabView.swift
//  Cozy Crumb
//
//  Tab shell. Only the Pantry is still a placeholder, and it says which phase
//  delivers it; everything else is real. Preferences are read here and carried
//  down through the environment, so one place decides the accent, the
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

    /// Which build phase delivers this screen. Shown on the placeholder only.
    var arrivingInPhase: String {
        switch self {
        case .library: "Phase 3"
        case .groceries: "Phase 5"
        case .sousChef: "Phase 8"
        case .pantry: "Phase 9"
        case .settings: "Phase 7"
        }
    }

    /// Empty-state copy, so the placeholders already read in the app's voice.
    var placeholderMessage: String {
        switch self {
        case .library: "Your cookbook's a blank page. Paste a link to get started."
        case .groceries: "Nothing on the list yet. Add a recipe's ingredients and they'll land here."
        case .sousChef: "Add your key in Settings to wake up the Sous Chef."
        case .pantry: "Nothing in the pantry. Snap a photo of your fridge and I'll take a look."
        case .settings: "Preferences, your API key, and your data live here."
        }
    }

    var pose: MascotView.Pose {
        switch self {
        case .library: .sleeping
        case .groceries: .idle
        case .sousChef: .cooking
        case .pantry: .peeking
        case .settings: .idle
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
                PlaceholderScreen(tab: .pantry)
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
        .task {
            SeedData.installIfNeeded(in: modelContext)
            // Re-reads ingredient lines saved before the caption parsing
            // fixes, so recipes already in the library start scaling too.
            IngredientRepair.run(in: modelContext)
        }
    }
}

// MARK: - Placeholders

private struct PlaceholderScreen: View {
    let tab: CozyTab

    var body: some View {
        NavigationStack {
            EmptyStateView(
                title: tab.title,
                message: tab.placeholderMessage,
                pose: tab.pose
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { BlobBackground() }
            .navigationTitle(tab.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text(tab.arrivingInPhase)
                        .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                }
            }
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
