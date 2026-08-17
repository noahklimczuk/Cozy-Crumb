//
//  CozyDeepLink.swift
//  Cozy Crumb / Cozy CrumbShare
//
//  How a link gets into the app from outside it (Phase 10).
//
//  This file is compiled into *both* targets, which is the whole point: the
//  share extension writes the URL and the app reads it, and if the two ever
//  disagreed about the format the hand-off would silently do nothing.
//
//      cozycrumb://import?url=https%3A%2F%2Fwww.instagram.com%2Freel%2FABC%2F
//
//  The extension can't write to the store — a free Apple ID has no App Groups,
//  so there is no shared container — so opening the app with the link is the
//  hand-off. Parsing is pure, so it can be tested without either target
//  running.
//
//  Anything unrecognised returns nil rather than guessing. An app that opens
//  its importer because something vaguely URL-shaped arrived is worse than one
//  that ignores a link it doesn't understand.
//

import Foundation

nonisolated enum CozyDeepLink: Sendable, Equatable {
    /// Someone shared a link they want turned into a recipe.
    case importRecipe(URL)

    nonisolated static let scheme = "cozycrumb"
    nonisolated static let importHost = "import"

    // MARK: - Reading

    nonisolated init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }

        // Accept both cozycrumb://import?url=… and cozycrumb:///import?url=…,
        // since the two are easy to confuse and both mean the same thing.
        let host = url.host()?.lowercased()
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()

        guard host == Self.importHost || (host == nil && path == Self.importHost) else {
            return nil
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let shared = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let target = URL(string: shared),
              let scheme = target.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        self = .importRecipe(target)
    }

    // MARK: - Writing

    /// The URL the share extension opens.
    ///
    /// The encoding is done by hand rather than through `queryItems`, because a
    /// TikTok share link is mostly query parameters and the whole thing has to
    /// survive as a single value — one unescaped `&` and the app would read the
    /// link up to the first parameter and try to import that.
    nonisolated static func importing(_ url: URL) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")

        guard let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = importHost
        components.percentEncodedQuery = "url=\(encoded)"

        return components.url
    }
}
