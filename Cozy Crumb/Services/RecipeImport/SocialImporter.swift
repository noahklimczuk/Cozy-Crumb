//
//  SocialImporter.swift
//  Cozy Crumb
//
//  Gets whatever a social platform will publicly give us, without pretending
//  to be a logged-in user.
//
//  What is actually available differs sharply by platform, and the UI is
//  honest about it rather than failing the same way four times:
//
//    YouTube    oEmbed for title/author/thumbnail, and — uniquely — Gemini can
//               watch the video itself from its URL, so this is the one place
//               "analyse the video" is real.
//    TikTok     oEmbed gives the caption, author and thumbnail. The video is
//               not obtainable.
//    Instagram  Open Graph tags when they are served to anonymous requests,
//               which is increasingly not the case.
//    Facebook   Same, and gated harder.
//
//  Comments are not available on any of them without an authenticated API, so
//  we do not claim to read them.
//
//  This file only ever gets at *text*. When the caption turns out not to
//  contain the recipe — which is the norm for short-form cooking video —
//  `SocialMediaResolver` has a go at the post's media, and failing that the
//  user is offered the video-or-caption screen, which always works.
//

import Foundation
import os

enum SocialPlatform: String, Sendable, CaseIterable {
    case youtube
    case tiktok
    case instagram
    case facebook
    case pinterest
    case x
    case threads
    case reddit
    case vimeo

    nonisolated var displayName: String {
        switch self {
        case .youtube: "YouTube"
        case .tiktok: "TikTok"
        case .instagram: "Instagram"
        case .facebook: "Facebook"
        case .pinterest: "Pinterest"
        case .x: "X (Twitter)"
        case .threads: "Threads"
        case .reddit: "Reddit"
        case .vimeo: "Vimeo"
        }
    }

    /// Only YouTube can have its video read directly, because Gemini accepts a YouTube
    /// URL directly.
    nonisolated var supportsVideoAnalysis: Bool {
        self == .youtube
    }

    /// Whether an official oEmbed endpoint serves us metadata.
    nonisolated var hasOEmbed: Bool {
        self == .youtube || self == .tiktok
    }

    nonisolated var captionHelpText: String {
        switch self {
        case .youtube:
            "I'll watch the video and write the recipe down."
        case .tiktok:
            "I'll read the caption, and have a go at the video when the recipe isn't in it."
        case .instagram, .facebook, .pinterest, .x, .threads, .reddit, .vimeo:
            "Social platforms keep posts behind a login, so I may need the video or a screenshot from you."
        }
    }

    nonisolated static func detect(from url: URL) -> SocialPlatform? {
        guard let host = url.host()?.lowercased() else { return nil }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host

        return switch bare {
        case "youtube.com", "m.youtube.com", "youtu.be", "music.youtube.com": .youtube
        case "tiktok.com", "vm.tiktok.com", "vt.tiktok.com", "m.tiktok.com": .tiktok
        case "instagram.com", "instagr.am": .instagram
        case "facebook.com", "fb.com", "fb.watch", "m.facebook.com": .facebook
        case "pinterest.com", "pin.it", "m.pinterest.com": .pinterest
        case "x.com", "twitter.com": .x
        case "threads.net": .threads
        case "reddit.com", "redd.it": .reddit
        case "vimeo.com": .vimeo
        default: nil
        }
    }
}

/// Everything we managed to gather about a post.
nonisolated struct SocialPost: Sendable {
    var platform: SocialPlatform
    /// Canonical URL, tracking parameters removed.
    var url: URL
    var title: String? = nil
    var author: String? = nil
    var caption: String? = nil
    var thumbnailURL: URL? = nil

    /// True when there is enough text to attempt a parse without asking the
    /// user to paste anything.
    nonisolated var hasUsableText: Bool {
        (caption?.count ?? 0) >= 40
    }
}

actor SocialImporter {

    private let session: URLSession
    private let openGraph = OpenGraphExtractor()

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            self.session = URLSession(configuration: configuration)
        }
    }

    // MARK: - Fetch

    func fetch(url rawURL: URL, platform: SocialPlatform) async -> SocialPost {
        let url = Self.canonical(rawURL, platform: platform)

        var post = SocialPost(platform: platform, url: url)

        if platform.hasOEmbed, let oembed = await fetchOEmbed(for: url, platform: platform) {
            post.title = oembed.title
            post.author = oembed.authorName
            post.thumbnailURL = oembed.thumbnailURL.flatMap { URL(string: $0) }

            // TikTok puts the whole caption in the oEmbed title.
            if platform == .tiktok {
                post.caption = oembed.title
            }
        }

        // Open Graph fills the gaps, and is the only source for Instagram and
        // Facebook. It often fails on those two; that is expected.
        if let metadata = await fetchOpenGraph(for: url) {
            post.title = post.title ?? metadata.title
            post.author = post.author ?? metadata.siteName
            post.thumbnailURL = post.thumbnailURL ?? metadata.imageURL

            if let description = metadata.description, !description.isEmpty {
                let cleaned = Self.cleanCaption(description, platform: platform)
                if (cleaned.count) > (post.caption?.count ?? 0) {
                    post.caption = cleaned
                }
            }
        }

        return post
    }

    // MARK: - oEmbed

    /// Both YouTube and TikTok publish official, unauthenticated oEmbed
    /// endpoints. This is a documented public API, not scraping.
    private func fetchOEmbed(for url: URL, platform: SocialPlatform) async -> OEmbedResponse? {
        guard let encoded = url.absoluteString.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))
        ) else { return nil }

        let endpoint: String = switch platform {
        case .youtube: "https://www.youtube.com/oembed?format=json&url=\(encoded)"
        case .tiktok: "https://www.tiktok.com/oembed?url=\(encoded)"
        default: ""
        }

        guard !endpoint.isEmpty, let endpointURL = URL(string: endpoint) else { return nil }

        var request = URLRequest(url: endpointURL)
        request.setValue(NetworkConstants.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)

            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                Log.importer.info("oEmbed \(platform.rawValue, privacy: .public) returned \(http.statusCode, privacy: .public)")
                return nil
            }

            return try? JSONDecoder().decode(OEmbedResponse.self, from: data)
        } catch {
            Log.importer.info("oEmbed \(platform.rawValue, privacy: .public) unavailable")
            return nil
        }
    }

    private func fetchOpenGraph(for url: URL) async -> OpenGraphMetadata? {
        var request = URLRequest(url: url)
        request.setValue(NetworkConstants.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }

            guard let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
                return nil
            }

            return openGraph.extract(from: html, sourceURL: url)
        } catch {
            return nil
        }
    }

    // MARK: - URL handling

    /// Normalises share URLs and strips tracking parameters, so a link copied
    /// from the app and one copied from a browser produce the same import and
    /// hit the same duplicate check.
    nonisolated static func canonical(_ url: URL, platform: SocialPlatform) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        // youtu.be/ID -> youtube.com/watch?v=ID
        if platform == .youtube, url.host()?.lowercased().contains("youtu.be") == true {
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !id.isEmpty, let rebuilt = URL(string: "https://www.youtube.com/watch?v=\(id)") {
                return rebuilt
            }
        }

        // youtube.com/shorts/ID -> youtube.com/watch?v=ID
        if platform == .youtube, url.path.lowercased().contains("/shorts/") {
            let parts = url.path.components(separatedBy: "/shorts/")
            if let id = parts.last?.trimmingCharacters(in: CharacterSet(charactersIn: "/")), !id.isEmpty {
                let cleanID = id.components(separatedBy: "?").first ?? id
                if let rebuilt = URL(string: "https://www.youtube.com/watch?v=\(cleanID)") {
                    return rebuilt
                }
            }
        }

        if platform == .youtube {
            components.host = "www.youtube.com"
            // Keep only the video id; drop playlist position, si, feature…
            let videoID = components.queryItems?.first { $0.name == "v" }
            components.queryItems = videoID.map { [$0] }
        } else {
            let junk: Set<String> = [
                "utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term",
                "igshid", "igsh", "fbclid", "gclid", "si", "_r", "_t", "is_from_webapp",
                "sender_device", "web_id", "share_app_id", "share_link_id", "mibextid"
            ]
            let kept = components.queryItems?.filter { !junk.contains($0.name.lowercased()) }
            components.queryItems = (kept?.isEmpty ?? true) ? nil : kept
        }

        return components.url ?? url
    }

    // MARK: - Caption cleaning

    /// Instagram and Facebook wrap the caption in engagement noise, e.g.
    /// `1,234 likes, 56 comments - someone on March 3, 2025: "real caption"`.
    /// This digs the caption back out.
    nonisolated static func cleanCaption(_ raw: String, platform: SocialPlatform) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if platform == .instagram || platform == .facebook {
            // Prefer the quoted portion when the wrapper is present.
            if let firstQuote = text.firstIndex(of: "\""),
               let lastQuote = text.lastIndex(of: "\""),
               firstQuote < lastQuote {
                let inner = String(text[text.index(after: firstQuote)..<lastQuote])
                if inner.count > 20 {
                    text = inner
                }
            } else if let colon = text.firstIndex(of: ":"),
                      text[text.startIndex..<colon].localizedCaseInsensitiveContains("likes") {
                text = String(text[text.index(after: colon)...])
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - oEmbed shape

nonisolated struct OEmbedResponse: Decodable, Sendable {
    var title: String?
    var authorName: String?
    var thumbnailURL: String?

    enum CodingKeys: String, CodingKey {
        case title
        case authorName = "author_name"
        case thumbnailURL = "thumbnail_url"
    }
}
