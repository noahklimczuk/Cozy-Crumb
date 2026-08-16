//
//  GeminiModel.swift
//  Cozy Crumb
//
//  Model IDs in one place so they can be swapped without touching call sites.
//

import Foundation

enum GeminiModel: String, CaseIterable, Identifiable, Sendable {
    /// Default. Stable, multimodal, handles both the text and the vision work.
    case balanced = "gemini-3.6-flash"
    /// Faster and cheaper. Good enough for straightforward caption parsing.
    case speedy = "gemini-3.5-flash-lite"

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .balanced: "Balanced"
        case .speedy: "Speedy"
        }
    }

    nonisolated var explanation: String {
        switch self {
        case .balanced: "Best at messy captions and video. The default."
        case .speedy: "Quicker and cheaper. Fine for tidy recipes."
        }
    }

    /// Video understanding needs the fuller model; Flash-Lite is text-first.
    nonisolated var supportsVideo: Bool {
        self == .balanced
    }

    /// The model Settings is set to.
    ///
    /// Every AI call site defaults to this rather than to a hard-coded case,
    /// which is what makes the picker in Settings mean something — it was
    /// writing a preference nothing read.
    nonisolated static var preferred: GeminiModel {
        preferred(in: .standard)
    }

    /// A model ID stored by an older build — or a hand-edited one — falls back
    /// to the default rather than being sent to the API to 404.
    nonisolated static func preferred(in defaults: UserDefaults) -> GeminiModel {
        guard let raw = defaults.string(forKey: CozyDefaultsKey.geminiModel),
              let model = GeminiModel(rawValue: raw) else {
            return .balanced
        }
        return model
    }
}

enum GeminiEndpoint {
    nonisolated static let host = "https://generativelanguage.googleapis.com"
    nonisolated static let version = "v1beta"

    /// Key goes in the x-goog-api-key header, never the query string — a URL
    /// with a key in it leaks into logs and crash reports.
    nonisolated static func generateContent(model: GeminiModel) -> URL? {
        URL(string: "\(host)/\(version)/models/\(model.rawValue):generateContent")
    }

    nonisolated static func streamGenerateContent(model: GeminiModel) -> URL? {
        URL(string: "\(host)/\(version)/models/\(model.rawValue):streamGenerateContent?alt=sse")
    }

    /// Where the user gets a key.
    nonisolated static let apiKeyPage = URL(string: "https://aistudio.google.com/apikey")
}
