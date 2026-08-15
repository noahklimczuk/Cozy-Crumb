//
//  Log.swift
//  Cozy Crumb
//
//  Central logging. Never `print()` in shipped code, and never log an API key,
//  a request body, or a response body — see the GeminiClient requirements.
//

import os

// Logging is safe to use from background actors as well as UI code.
nonisolated enum Log {
    static let app = Logger(subsystem: AppBranding.bundleIdentifier, category: "app")
    static let data = Logger(subsystem: AppBranding.bundleIdentifier, category: "data")
    static let importer = Logger(subsystem: AppBranding.bundleIdentifier, category: "import")
    static let ai = Logger(subsystem: AppBranding.bundleIdentifier, category: "ai")
}
