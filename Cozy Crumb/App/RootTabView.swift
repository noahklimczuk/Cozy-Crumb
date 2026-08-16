//
//  RootTabView.swift
//  Cozy Crumb
//
//  Tab shell. Screens are still placeholders — each notes the phase that
//  delivers it — but they now sit on the real background and carry the
//  accent and haptics preferences down through the environment.
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
        case .library: "Library"
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
    @AppStorage(CozyDefaultsKey.darkModeEnabled) private var darkModeEnabled = false

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

    var body: some View {
        TabView(selection: $selection) {
            Tab(CozyTab.library.title, systemImage: CozyTab.library.symbol, value: .library) {
                LibraryView()
            }
            Tab(CozyTab.groceries.title, systemImage: CozyTab.groceries.symbol, value: .groceries) {
                PlaceholderScreen(tab: .groceries)
            }
            Tab(CozyTab.sousChef.title, systemImage: CozyTab.sousChef.symbol, value: .sousChef) {
                PlaceholderScreen(tab: .sousChef)
            }
            Tab(CozyTab.pantry.title, systemImage: CozyTab.pantry.symbol, value: .pantry) {
                PlaceholderScreen(tab: .pantry)
            }
            Tab(CozyTab.settings.title, systemImage: CozyTab.settings.symbol, value: .settings) {
                SettingsPlaceholderScreen(
                    accent: accentBinding,
                    hapticsEnabled: $hapticsEnabled,
                    darkModeEnabled: $darkModeEnabled
                )
            }
        }
        .tint(accent.deep)
        .environment(\.accentPalette, accent)
        .environment(\.hapticsEnabled, hapticsEnabled)
        .preferredColorScheme(darkModeEnabled ? .dark : .light)
        .task {
            SeedData.installIfNeeded(in: modelContext)
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

/// Settings is a placeholder too, but it hosts the design-system gallery so
/// the whole visual language can be checked on a real device.
private struct SettingsPlaceholderScreen: View {
    @Binding var accent: AccentPalette
    @Binding var hapticsEnabled: Bool
    @Binding var darkModeEnabled: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CozySpacing.l) {
                    CrumbCard {
                        VStack(alignment: .leading, spacing: CozySpacing.m) {
                            Text("Design System")
                                .cozyText(CozyFont.title2)
                            Text("Every colour, type style, component and motion curve on one screen.")
                                .cozyText(CozyFont.subheadline, color: CozyColor.inkSecondary)
                            NavigationLink {
                                ComponentGalleryView(accent: $accent)
                            } label: {
                                HStack {
                                    Text("Open the gallery")
                                        .cozyText(CozyFont.bodyEmphasis)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(CozyColor.inkSecondary)
                                }
                                .frame(minHeight: CozyMetrics.minimumTouchTarget)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.squishy)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    CrumbCard {
                        Toggle(isOn: $hapticsEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Haptics")
                                    .cozyText(CozyFont.bodyEmphasis)
                                Text("A soft tap on every press.")
                                    .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                            }
                        }
                        .tint(accent.deep)
                    }

                    CrumbCard {
                        Toggle(isOn: $darkModeEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dark mode")
                                    .cozyText(CozyFont.bodyEmphasis)
                                Text("Use Cozy Crumb's warm nighttime palette.")
                                    .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                            }
                        }
                        .tint(accent.deep)
                    }

                    CrumbCard(fill: CozyColor.creamDeep) {
                        VStack(spacing: CozySpacing.s) {
                            Text("The rest of Settings arrives in Phase 7")
                                .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                                .multilineTextAlignment(.center)
                            Text(AppBranding.versionDisplayString)
                                .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(CozySpacing.l)
            }
            .background { BlobBackground() }
            .navigationTitle("Settings")
        }
    }
}

#Preview("Tabs") {
    RootTabView()
        .modelContainer(PreviewData.container)
}

#Preview("Tabs — dark") {
    RootTabView()
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
