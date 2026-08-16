//
//  CozyDefaults.swift
//  Cozy Crumb
//
//  UserDefaults keys in one place. Everything here is surfaced in Settings.
//

import Foundation

enum CozyDefaultsKey {
    static let accentPalette = "settings.accentPalette"
    static let hapticsEnabled = "settings.hapticsEnabled"
    /// Light, dark, or match the phone. Replaces `darkModeEnabled`, which is
    /// still read once by `AppAppearance.stored(in:)` so an existing choice
    /// carries over.
    static let appearance = "settings.appearance"
    static let darkModeEnabled = "settings.darkModeEnabled"
    static let measurementSystem = "settings.measurementSystem"
    static let geminiModel = "settings.geminiModel"
    /// Ticking a grocery item off also stocks the pantry with it (§5.5).
    static let checkOffAddsToPantry = "settings.checkOffAddsToPantry"
    /// Show grocery amounts as the sizes shops actually sell.
    static let roundUpShoppingAmounts = "settings.roundUpShoppingAmounts"
    /// How the Cookbook's recipe grids are ordered.
    static let librarySort = "library.sort"
}
