//
//  AppAppearance.swift
//  Cozy Crumb
//
//  Light, dark, or whatever the phone is doing (Phase 7).
//
//  Until now this was a single "dark mode" switch, which quietly forced the
//  app light for anyone whose phone was already dark — the off position meant
//  "light", not "leave it alone". Following the system is the option most
//  people want and the one they never had, so it's the new default, and the
//  old switch is read once on the way past so nobody's choice is lost.
//

import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .system: "Match phone"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    nonisolated var symbol: String {
        switch self {
        case .system: "iphone"
        case .light: "sun.max"
        case .dark: "moon.stars"
        }
    }

    /// nil hands the decision back to iOS.
    nonisolated var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// Resolves the stored preference, falling back to the old boolean the
    /// first time round so an existing install doesn't lose its dark mode.
    nonisolated static func stored(in defaults: UserDefaults = .standard) -> AppAppearance {
        if let raw = defaults.string(forKey: CozyDefaultsKey.appearance),
           let appearance = AppAppearance(rawValue: raw) {
            return appearance
        }

        // `object(forKey:)` rather than `bool(forKey:)`: an unset key reads as
        // false, which is indistinguishable from someone choosing light.
        if let legacyDarkMode = defaults.object(forKey: CozyDefaultsKey.darkModeEnabled) as? Bool {
            return legacyDarkMode ? .dark : .light
        }

        return .system
    }
}
