//
//  GeminiAPIKey.swift
//  Cozy Crumb
//
//  Which key the app talks to Gemini with.
//
//  Two sources, in this order:
//    1. A key the owner typed into Settings, read from the Keychain.
//    2. The key this build ships with, read from `Secrets.plist` in the app
//       bundle.
//
//  Secrets.plist is deliberately *not* in git. This repository is public, and
//  a Gemini key committed to a public repository is found by GitHub's secret
//  scanning and disabled by Google, usually the same day — a key in the repo
//  is a key that stops working. Keeping the file out of git costs one manual
//  copy per checkout and is the difference between a build that works and one
//  that mysteriously stops.
//
//  To give a build its own key:
//
//      cp Config/Secrets.example.plist "Cozy Crumb/Resources/Secrets.plist"
//      # then put the key in the GeminiAPIKey entry
//
//  `Cozy Crumb` is a synchronised group, so Xcode picks the file up and copies
//  it into the app with no project changes. Without it there is no built-in
//  key and the app is bring-your-own, exactly as it was before.
//
//  A key shipped this way is still readable by anyone holding the binary — a
//  plist inside an .ipa is just a plist. Keep it restricted to the Generative
//  Language API, and rotatable.
//

import Foundation

/// The shape of Secrets.plist. Decodable rather than a dictionary cast so a
/// typo in the file is a decode failure we can log, not a silent nil.
private nonisolated struct GeminiSecretsFile: Decodable {
    var geminiAPIKey: String?

    enum CodingKeys: String, CodingKey {
        case geminiAPIKey = "GeminiAPIKey"
    }
}

nonisolated enum GeminiAPIKey {

    private static let secretsResource = "Secrets"
    private static let secretsEntry = "GeminiAPIKey"

    /// The key this build ships with, or nil when it ships without one.
    ///
    /// Read once: a file inside the bundle cannot change under a running app.
    static let builtInKey: String? = {
        // No file is the ordinary case for a fresh checkout and for CI. It is
        // not a failure, so it is not logged.
        guard let url = Bundle.main.url(forResource: secretsResource, withExtension: "plist") else {
            return nil
        }

        guard let data = try? Data(contentsOf: url),
              let secrets = try? PropertyListDecoder().decode(GeminiSecretsFile.self, from: data),
              let key = secrets.geminiAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            // Shipped but unreadable looks exactly like no key at all from the
            // outside, which is a miserable thing to debug. Say so — the name
            // of the missing entry only, never a value.
            Log.ai.error("Secrets.plist carries no usable \(secretsEntry, privacy: .public)")
            return nil
        }

        return key
    }()

    /// The key to put on the wire.
    ///
    /// The owner's own key wins: someone who has gone to the trouble of
    /// pasting one into Settings wants their quota used, not ours.
    static func resolved(keychain: KeychainStore = .shared) -> String? {
        keychain.string(for: .geminiAPIKey) ?? builtInKey
    }

    /// Whether the app can talk to Gemini at all — the one gate every AI
    /// feature checks before offering itself.
    static func isAvailable(keychain: KeychainStore = .shared) -> Bool {
        resolved(keychain: keychain) != nil
    }
}
