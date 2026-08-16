//
//  CozyDefaults.swift
//  Cozy Crumb
//
//  UserDefaults keys in one place. Settings (Phase 7) will add the model
//  picker, units preference, and the remaining toggles here.
//

import Foundation

enum CozyDefaultsKey {
    static let accentPalette = "settings.accentPalette"
    static let hapticsEnabled = "settings.hapticsEnabled"
    static let darkModeEnabled = "settings.darkModeEnabled"
    static let measurementSystem = "settings.measurementSystem"
    static let geminiModel = "settings.geminiModel"
    /// Ticking a grocery item off also stocks the pantry with it (§5.5).
    static let checkOffAddsToPantry = "settings.checkOffAddsToPantry"
    /// Show grocery amounts as the sizes shops actually sell.
    static let roundUpShoppingAmounts = "settings.roundUpShoppingAmounts"
}
