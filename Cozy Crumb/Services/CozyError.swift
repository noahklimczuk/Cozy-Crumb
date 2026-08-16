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

    // AI
    case missingAPIKey
    case invalidAPIKey
    case modelUnavailable
    case rateLimited
    case blockedBySafety
    case emptyResponse
    case responseTruncated
    case aiRequestRejected

    // Social
    case socialNeedsCaption
    case captionTooShort

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

        case .missingAPIKey:
            "Add your key in Settings to wake up the Sous Chef."
        case .invalidAPIKey:
            "That key didn't work — double-check it in Settings."
        case .modelUnavailable:
            "This key doesn't have access to that model."
        case .rateLimited:
            "The kitchen's a bit busy — give it a second."
        case .blockedBySafety:
            "I got a bit tongue-tied on that one — try rephrasing?"
        case .emptyResponse:
            "I came back with nothing that time. Worth another go?"
        case .responseTruncated:
            "That recipe ran long and I lost the end of it. Try again?"
        case .aiRequestRejected:
            "Something about that request confused me. Try again?"

        case .socialNeedsCaption:
            "This one's shy — paste the caption here and I'll sort it out."
        case .captionTooShort:
            "There's not much to go on there. Paste a bit more?"

        case .unknown:
            "The kitchen's a bit quiet — check your connection?"
        }
    }

    /// Whether offering a retry button makes sense.
    nonisolated var isRetryable: Bool {
        switch self {
        case .offline, .httpStatus, .timedOut, .unknown: true
        case .rateLimited, .emptyResponse, .responseTruncated, .aiRequestRejected: true
        case .badURL, .notAWebPage, .noRecipeFound, .decodingFailed, .imageUnavailable, .cancelled: false
        case .missingAPIKey, .invalidAPIKey, .modelUnavailable, .blockedBySafety: false
        case .socialNeedsCaption, .captionTooShort: false
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
