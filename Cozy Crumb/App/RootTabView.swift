//
//  RootTabView.swift
//  Cozy Crumb
//
//  Phase 0 tab scaffold. Each tab is a labelled placeholder; the real screens
//  arrive in their own phases. The design system lands in Phase 1, so nothing
//  here is styled yet on purpose.
//

import SwiftUI

enum CozyTab: Hashable, CaseIterable {
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
}

struct RootTabView: View {
    @State private var selection: CozyTab = .library

    var body: some View {
        TabView(selection: $selection) {
            Tab(CozyTab.library.title, systemImage: CozyTab.library.symbol, value: .library) {
                PlaceholderScreen(tab: .library)
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
                PlaceholderScreen(tab: .settings)
            }
        }
    }
}

private struct PlaceholderScreen: View {
    let tab: CozyTab

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text(tab.title)
                    .font(.title2.weight(.semibold))
                Text("Arriving in \(tab.arrivingInPhase).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(tab.title), arriving in \(tab.arrivingInPhase)")
            .navigationTitle(tab.title)
        }
    }
}

#Preview {
    RootTabView()
}
