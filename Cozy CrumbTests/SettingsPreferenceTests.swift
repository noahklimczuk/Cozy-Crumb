//
//  SettingsPreferenceTests.swift
//  Cozy CrumbTests
//
//  The two preferences with logic behind them rather than a plain toggle:
//  the appearance choice, which has to carry an older install's dark-mode
//  switch across, and the model picker, which now decides what the AI calls
//  actually use.
//

import Foundation
import Testing

@testable import Cozy_Crumb

/// A throwaway defaults domain per test, so nothing leaks between them or
/// touches the simulator's real preferences.
private func makeDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Suite("Appearance preference")
struct AppAppearanceTests {

    @Test("A fresh install follows the phone")
    func defaultsToSystem() {
        #expect(AppAppearance.stored(in: makeDefaults()) == .system)
        #expect(AppAppearance.system.colorScheme == nil)
    }

    @Test("A stored choice is used as written")
    func readsStoredChoice() {
        let defaults = makeDefaults()

        defaults.set(AppAppearance.light.rawValue, forKey: CozyDefaultsKey.appearance)
        #expect(AppAppearance.stored(in: defaults) == .light)

        defaults.set(AppAppearance.dark.rawValue, forKey: CozyDefaultsKey.appearance)
        #expect(AppAppearance.stored(in: defaults) == .dark)
    }

    @Test("The old dark-mode switch carries over, both ways")
    func migratesLegacySwitch() {
        let wasDark = makeDefaults()
        wasDark.set(true, forKey: CozyDefaultsKey.darkModeEnabled)
        #expect(AppAppearance.stored(in: wasDark) == .dark)

        // False here means someone actually chose light, not "never set".
        let wasLight = makeDefaults()
        wasLight.set(false, forKey: CozyDefaultsKey.darkModeEnabled)
        #expect(AppAppearance.stored(in: wasLight) == .light)
    }

    @Test("A new choice wins over the old switch")
    func newChoiceBeatsLegacy() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: CozyDefaultsKey.darkModeEnabled)
        defaults.set(AppAppearance.system.rawValue, forKey: CozyDefaultsKey.appearance)

        #expect(AppAppearance.stored(in: defaults) == .system)
    }

    @Test("Nonsense in the store falls back rather than crashing")
    func ignoresRubbish() {
        let defaults = makeDefaults()
        defaults.set("sepia", forKey: CozyDefaultsKey.appearance)

        #expect(AppAppearance.stored(in: defaults) == .system)
    }
}

@Suite("Model preference")
struct GeminiModelPreferenceTests {

    @Test("Unset means the balanced model")
    func defaultsToBalanced() {
        #expect(GeminiModel.preferred(in: makeDefaults()) == .balanced)
    }

    @Test("The picker's choice is what gets used")
    func readsStoredModel() {
        let defaults = makeDefaults()
        defaults.set(GeminiModel.speedy.rawValue, forKey: CozyDefaultsKey.geminiModel)

        #expect(GeminiModel.preferred(in: defaults) == .speedy)
    }

    @Test("A model ID we no longer ship falls back instead of 404ing")
    func ignoresUnknownModel() {
        let defaults = makeDefaults()
        defaults.set("gemini-1.0-pro-vision-latest", forKey: CozyDefaultsKey.geminiModel)

        #expect(GeminiModel.preferred(in: defaults) == .balanced)
    }

    @Test("Only the fuller model can watch video")
    func videoSupport() {
        #expect(GeminiModel.balanced.supportsVideo)
        #expect(!GeminiModel.speedy.supportsVideo)
    }
}
