//
//  ImportCoordinator.swift
//  Cozy Crumb
//
//  Runs the cascade: fetch the page, try each tier in order, stop at the first
//  confident result.
//
//  A page that loads but yields no recipe is NOT an error — it returns a result
//  with no recipe plus whatever Open Graph data was found, so the review screen
//  can drop the user into manual entry with the title and photo already filled
//  in. Only genuine failures (offline, 404, not HTML) come back as errors.
//

import Foundation
import os

/// What a completed import attempt produced.
struct ImportResult: Sendable {
    /// nil when no tier could find a recipe on the page.
    var recipe: ImportedRecipe?
    /// Always populated with whatever the page advertised.
    var metadata: OpenGraphMetadata
    /// True for hosts that never serve recipe markup to anonymous requests.
    var isSocialSource: Bool
    /// The fetched page HTML, used for AI fallback when structured scrapers find no recipe.
    var rawHTML: String?

    nonisolated init(recipe: ImportedRecipe?, metadata: OpenGraphMetadata, isSocialSource: Bool, rawHTML: String? = nil) {
        self.recipe = recipe
        self.metadata = metadata
        self.isSocialSource = isSocialSource
        self.rawHTML = rawHTML
    }
}

actor ImportCoordinator {

    private let session: URLSession
    private let tiers: [any RecipeExtracting]
    private let openGraph = OpenGraphExtractor()

    /// Hosts that require auth and actively block scraping. We read their public
    /// metadata or hand off to dedicated social/video parsers.
    private nonisolated static let socialHosts: Set<String> = [
        "instagram.com", "www.instagram.com", "instagr.am",
        "tiktok.com", "www.tiktok.com", "vm.tiktok.com", "vt.tiktok.com", "m.tiktok.com",
        "youtube.com", "www.youtube.com", "youtu.be", "m.youtube.com", "music.youtube.com",
        "facebook.com", "www.facebook.com", "fb.com", "fb.watch", "m.facebook.com",
        "pinterest.com", "www.pinterest.com", "pin.it", "m.pinterest.com",
        "x.com", "www.x.com", "twitter.com", "www.twitter.com",
        "threads.net", "www.threads.net",
        "reddit.com", "www.reddit.com", "redd.it",
        "vimeo.com", "www.vimeo.com"
    ]

    init(session: URLSession? = nil, tiers: [any RecipeExtracting]? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 45
            self.session = URLSession(configuration: configuration)
        }

        self.tiers = tiers ?? [JSONLDExtractor(), MicrodataExtractor()]
    }

    // MARK: - Import

    func importRecipe(from url: URL) async -> Result<ImportResult, CozyError> {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .failure(.badURL)
        }

        let html: String
        switch await fetchHTML(from: url) {
        case .success(let value): html = value
        case .failure(let error): return .failure(error)
        }

        return .success(parse(html: html, sourceURL: url))
    }

    /// Runs the tiers against already-fetched markup. Pure, so tests can drive
    /// it with saved fixtures and no network.
    nonisolated func parse(html: String, sourceURL: URL?) -> ImportResult {
        let metadata = openGraph.extract(from: html, sourceURL: sourceURL)
        let isSocial = sourceURL?.host().map { Self.socialHosts.contains($0.lowercased()) } ?? false

        var best: ImportedRecipe?

        for tier in tiers {
            guard let candidate = tier.extract(from: html, sourceURL: sourceURL), candidate.isUsable else {
                continue
            }

            // A complete result ends the cascade. An incomplete one is kept as
            // a floor while a later tier gets a chance to do better.
            if candidate.isComplete {
                best = candidate
                break
            }

            if best == nil {
                best = candidate
            }
        }

        if var recipe = best {
            recipe = filling(recipe, from: metadata)
            return ImportResult(recipe: recipe, metadata: metadata, isSocialSource: isSocial, rawHTML: html)
        }

        return ImportResult(recipe: nil, metadata: metadata, isSocialSource: isSocial, rawHTML: html)
    }

    /// Open Graph fills the gaps a structured tier left behind — usually the
    /// hero image, which sites often omit from their JSON-LD.
    private nonisolated func filling(_ recipe: ImportedRecipe, from metadata: OpenGraphMetadata) -> ImportedRecipe {
        var filled = recipe

        if filled.imageURL == nil {
            filled.imageURL = metadata.imageURL
        }
        if filled.summary?.isEmpty ?? true {
            filled.summary = metadata.description
        }
        if filled.sourceName?.isEmpty ?? true {
            filled.sourceName = metadata.siteName
        }

        return filled
    }

    // MARK: - Fetch

    private func fetchHTML(from url: URL) async -> Result<String, CozyError> {
        var request = URLRequest(url: url)
        request.setValue(NetworkConstants.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)

            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                Log.importer.info("Import fetch returned \(http.statusCode, privacy: .public)")
                return .failure(.httpStatus(http.statusCode))
            }

            if let mime = response.mimeType?.lowercased(), !mime.contains("html"), !mime.contains("xml") {
                return .failure(.notAWebPage)
            }

            guard let html = Self.decode(data, response: response) else {
                return .failure(.decodingFailed)
            }

            return .success(html)
        } catch let error as URLError {
            return .failure(.from(urlError: error))
        } catch {
            return .failure(.unknown("fetch"))
        }
    }

    /// Honours the response's declared encoding, then falls back. ISO-8859-1
    /// is the last resort because it never fails, which beats showing nothing.
    private nonisolated static func decode(_ data: Data, response: URLResponse) -> String? {
        if let name = response.textEncodingName {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
                if let text = String(data: data, encoding: encoding) {
                    return text
                }
            }
        }

        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }
}
