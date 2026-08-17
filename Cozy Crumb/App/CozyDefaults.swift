//
//  CozyDefaults.swift
//  Cozy Crumb
//
//  UserDefaults keys in one place. Everything here is surfaced in Settings.
//
//  `nonisolated` for the same reason as `Log`: the target defaults types to
//  MainActor, and these keys are read from nonisolated code —
//  `GeminiModel.preferred(in:)` and `AppAppearance.stored(in:)` both resolve a
//  preference without a view around. They're immutable strings, so isolating
//  them buys nothing and costs a compile error at every such call site.
//

import Foundation

nonisolated enum CozyDefaultsKey {
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
    /// Whether the "how to photograph a fridge" tips have been through once.
    /// After that the camera button goes straight to the viewfinder.
    static let seenFridgeCameraTips = "pantry.seenFridgeCameraTips"
}
