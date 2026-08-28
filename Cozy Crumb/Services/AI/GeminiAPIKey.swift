//
//  GeminiAPIKey.swift
//  Cozy Crumb
//
//  Which key the app talks to Gemini with.
//
//  Two sources, in this order:
//    1. A key the owner typed into Settings, read from the Keychain.
//    2. The key built into this build, below.
//
//  A built-in key ships inside the app bundle, so it is readable by anyone
//  who has the binary — `strings` over the app is all it takes. Only ship a
//  key you are willing to have in the open, keep it restricted to the
//  Generative Language API, and rotate it if it starts being spent by
//  someone else.
//

import Foundation

enum GeminiAPIKey {

    /// The key baked into this build. Paste it between the quotes.
    ///
    /// Empty means this build carries no key of its own, and the app behaves
    /// exactly as it did before: bring-your-own, entered in Settings.
    nonisolated static let builtIn = ""

    /// The built-in key, or nil when this build doesn't carry one.
    nonisolated static var builtInKey: String? {
        let trimmed = builtIn.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The key to put on the wire.
    ///
    /// The owner's own key wins: someone who has gone to the trouble of
    /// pasting one into Settings wants their quota used, not ours.
    nonisolated static func resolved(keychain: KeychainStore = .shared) -> String? {
        keychain.string(for: .geminiAPIKey) ?? builtInKey
    }

    /// Whether the app can talk to Gemini at all — the one gate every AI
    /// feature checks before offering itself.
    nonisolated static func isAvailable(keychain: KeychainStore = .shared) -> Bool {
        resolved(keychain: keychain) != nil
    }
}
