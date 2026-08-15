//
//  CozyError.swift
//  Cozy Crumb
//
//  Every failure the user can see, with copy written in the app's voice.
//  Views never render a raw error string.
//

import Foundation

enum CozyError: Error, Sendable, Equatable {
    case offline
    case badURL
    case httpStatus(Int)
    case notAWebPage
    case noRecipeFound
    case decodingFailed
    case imageUnavailable
    case timedOut
    case cancelled
    case unknown(String)

    /// Shown directly to the user. Warm, short, never blaming them.
    nonisolated var friendlyMessage: String {
        switch self {
        case .offline:
            "Looks like you're offline."
        case .badURL:
            "That doesn't look like a link I can open."
        case .httpStatus(404):
            "That page seems to have moved."
        case .httpStatus(403), .httpStatus(401):
            "That site won't let me in, I'm afraid."
        case .httpStatus:
            "That site isn't answering right now."
        case .notAWebPage:
            "That link isn't a web page I can read."
        case .noRecipeFound:
            "I couldn't find a recipe on that page."
        case .decodingFailed:
            "I couldn't make sense of that page."
        case .imageUnavailable:
            "Couldn't fetch the photo — the recipe's still fine."
        case .timedOut:
            "That took too long. Want to try again?"
        case .cancelled:
            "Stopped."
        case .unknown:
            "The kitchen's a bit quiet — check your connection?"
        }
    }

    /// Whether offering a retry button makes sense.
    nonisolated var isRetryable: Bool {
        switch self {
        case .offline, .httpStatus, .timedOut, .unknown: true
        case .badURL, .notAWebPage, .noRecipeFound, .decodingFailed, .imageUnavailable, .cancelled: false
        }
    }

    /// Maps a URLSession error into something we can show.
    nonisolated static func from(urlError: URLError) -> CozyError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            .offline
        case .timedOut:
            .timedOut
        case .cancelled:
            .cancelled
        case .badURL, .unsupportedURL:
            .badURL
        default:
            .unknown(urlError.code.rawValue.description)
        }
    }
}
