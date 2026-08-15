//
//  AppBranding.swift
//  Cozy Crumb
//
//  Single source of truth for the app's identity. The working name is not
//  final — changing `appName` here is the only edit required to rename it.
//

import Foundation

enum AppBranding {
    /// Working name. Not final.
    static let appName = "Cozy Crumb"

    /// Shown on the onboarding cards and the About screen.
    static let tagline = "Your cookbook, cozied up."

    /// Must match PRODUCT_BUNDLE_IDENTIFIER in the target's build settings.
    static let bundleIdentifier = "ca.klimczuk.cozycrumb"

    /// Custom scheme used by the Share Extension to hand a URL to the main app.
    /// (A free Apple ID cannot use App Groups, so the extension cannot write to
    /// the shared store directly — see the Phase 10 notes.)
    static let urlScheme = "cozycrumb"

    /// Where the user gets a Gemini key. Linked from Settings.
    static let apiKeyURL = URL(string: "https://aistudio.google.com/apikey")

    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var versionDisplayString: String {
        "Version \(marketingVersion) (\(buildNumber))"
    }
}
