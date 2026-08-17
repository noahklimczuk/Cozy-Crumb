//
//  CozyDeepLinkTests.swift
//  Cozy CrumbTests
//
//  The share extension and the app only agree on one thing — the shape of
//  cozycrumb://import?url=… — and nothing at runtime will tell you when they
//  stop agreeing. The hand-off just quietly does nothing. So both directions
//  are pinned here.
//

import Foundation
import Testing

@testable import Cozy_Crumb

@Suite("Links from outside the app")
struct CozyDeepLinkTests {

    private func roundTrip(_ address: String) throws -> URL {
        let original = try #require(URL(string: address))
        let deepLink = try #require(CozyDeepLink.importing(original))
        let parsed = try #require(CozyDeepLink(url: deepLink))

        guard case .importRecipe(let target) = parsed else {
            Issue.record("Expected an import link")
            return original
        }

        return target
    }

    @Test("A plain link survives the trip")
    func plainLink() throws {
        let address = "https://www.instagram.com/reel/C8xYzAbCdEf/"

        #expect(try roundTrip(address).absoluteString == address)
    }

    @Test("A link full of query parameters survives intact")
    func queryHeavyLink() throws {
        // The realistic case: TikTok's share sheet hands over a tracking-laden
        // URL, and an unescaped & would truncate it at "?is_from_webapp=1".
        let address = "https://www.tiktok.com/@cook/video/7361?is_from_webapp=1&sender_device=pc&web_id=123"

        #expect(try roundTrip(address).absoluteString == address)
    }

    @Test("Characters that mean something in a URL are carried, not interpreted")
    func awkwardCharacters() throws {
        let address = "https://example.com/recipes?q=caf%C3%A9+cr%C3%A8me&tag=30%25#method"

        #expect(try roundTrip(address).absoluteString == address)
    }

    @Test("The written link is the scheme the Info.plist registers")
    func writesOurScheme() throws {
        let original = try #require(URL(string: "https://example.com/x"))
        let deepLink = try #require(CozyDeepLink.importing(original))

        #expect(deepLink.scheme == "cozycrumb")
        #expect(deepLink.host() == "import")
    }

    @Test("Both spellings of the import link are read")
    func acceptsEitherSpelling() throws {
        let hostForm = try #require(URL(string: "cozycrumb://import?url=https%3A%2F%2Fexample.com%2Fa"))
        let pathForm = try #require(URL(string: "cozycrumb:///import?url=https%3A%2F%2Fexample.com%2Fa"))

        #expect(CozyDeepLink(url: hostForm) == .importRecipe(URL(string: "https://example.com/a")!))
        #expect(CozyDeepLink(url: pathForm) == .importRecipe(URL(string: "https://example.com/a")!))
    }

    @Test("Anything else is ignored rather than guessed at", arguments: [
        // Not ours.
        "https://example.com/recipe",
        "shortcuts://run?url=https%3A%2F%2Fexample.com",
        // Ours, but not an import.
        "cozycrumb://open",
        "cozycrumb://recipe?url=https%3A%2F%2Fexample.com",
        // An import with nothing importable in it.
        "cozycrumb://import",
        "cozycrumb://import?link=https%3A%2F%2Fexample.com",
        // A target we have no business opening.
        "cozycrumb://import?url=file%3A%2F%2F%2Fetc%2Fpasswd",
        "cozycrumb://import?url=javascript%3Aalert(1)",
        "cozycrumb://import?url=cozycrumb%3A%2F%2Fimport"
    ])
    func rejectsEverythingElse(address: String) throws {
        let url = try #require(URL(string: address))

        #expect(CozyDeepLink(url: url) == nil)
    }

    @Test("The scheme is matched case-insensitively, the way iOS hands it over")
    func toleratesCasing() throws {
        let url = try #require(URL(string: "CozyCrumb://Import?url=https%3A%2F%2Fexample.com%2Fa"))

        #expect(CozyDeepLink(url: url) == .importRecipe(URL(string: "https://example.com/a")!))
    }
}
