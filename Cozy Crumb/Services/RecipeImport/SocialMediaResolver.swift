//
//  SocialMediaResolver.swift
//  Cozy Crumb
//
//  For the posts where the recipe isn't written down anywhere.
//
//  A huge number of Instagram Reels and TikToks put the whole recipe in the
//  video — spoken over the top, or as text burned into the frames — and leave
//  the caption as "the BEST weeknight pasta 🍝🔥 recipe below 👇" with nothing
//  below. `SocialImporter` gets us the caption; when the caption turns out not
//  to be a recipe, this is what we try next.
//
//  It looks for the media a post is built from, using only what those sites
//  hand to an anonymous request:
//
//    Instagram  the public embed page (/embed/captioned/), which serves the
//               full caption and the poster image without a login, plus any
//               og:video / video_url the page happens to carry.
//    TikTok     the post page, whose rehydration blob carries the description
//               and a play address for the video.
//
//  All of it is best-effort by design. These pages change shape without
//  warning, and both platforms serve logged-out visitors less every year, so
//  every lookup here is allowed to come back empty — the import flow then asks
//  the user to hand over the video or a couple of screenshots, which is the
//  one route that always works.
//
//  The parsing is pure and static so it can be tested against saved fixtures;
//  only the actor does any networking.
//

import Foundation
import os

/// The media a post is made of, as far as we could tell from outside.
nonisolated struct SocialMedia: Sendable, Equatable {
    /// A directly downloadable video file, when the page exposed one.
    var videoURL: URL?
    /// Cover frame first, then any carousel slides — recipe cards are usually
    /// slide two onwards.
    var imageURLs: [URL] = []
    /// A caption read from the embed page, which is often fuller than the one
    /// Open Graph gives out.
    var caption: String?

    nonisolated var isEmpty: Bool {
        videoURL == nil && imageURLs.isEmpty && (caption?.isEmpty ?? true)
    }
}

actor SocialMediaResolver {

    /// Gemini takes media inline as base64, and the request as a whole has to
    /// stay under 20 MB. 12 MB of video leaves room for the encoding overhead
    /// and the prompt; anything longer gets sampled into frames instead.
    nonisolated static let inlineVideoByteLimit = 12 * 1024 * 1024

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: configuration)
        }
    }

    // MARK: - Resolving

    /// Best-effort lookup of the media behind a post. Never throws: an empty
    /// result is an ordinary outcome, not an error.
    func resolve(post: SocialPost) async -> SocialMedia {
        switch post.platform {
        case .instagram:
            return await resolveInstagram(post: post)
        case .tiktok:
            return await resolveTikTok(post: post)
        default:
            // Everywhere else, the page's own Open Graph tags are all there is.
            guard let html = await html(for: post.url) else { return SocialMedia() }
            return Self.media(inHTML: html, sourceURL: post.url)
        }
    }

    private func resolveInstagram(post: SocialPost) async -> SocialMedia {
        var media = SocialMedia()

        // The embed page is the only Instagram surface that still answers a
        // logged-out request reliably.
        if let shortcode = Self.instagramShortcode(from: post.url),
           let embed = Self.instagramEmbedURL(shortcode: shortcode),
           let html = await html(for: embed, referer: post.url) {
            media = Self.media(inHTML: html, sourceURL: embed)
            media.caption = media.caption ?? Self.instagramEmbedCaption(inHTML: html)
        }

        if media.videoURL == nil || media.caption == nil {
            if let html = await html(for: post.url) {
                let fallback = Self.media(inHTML: html, sourceURL: post.url)
                media.videoURL = media.videoURL ?? fallback.videoURL
                media.caption = media.caption ?? fallback.caption
                media.imageURLs = media.imageURLs.isEmpty ? fallback.imageURLs : media.imageURLs
            }
        }

        return media
    }

    private func resolveTikTok(post: SocialPost) async -> SocialMedia {
        guard let html = await html(for: post.url) else { return SocialMedia() }
        return Self.media(inHTML: html, sourceURL: post.url)
    }

    // MARK: - Downloading

    /// Downloads a video, refusing anything too big to send inline. Returns the
    /// bytes and the MIME type to declare.
    func downloadVideo(
        from url: URL,
        referer: URL?,
        byteLimit: Int = SocialMediaResolver.inlineVideoByteLimit
    ) async -> (data: Data, mimeType: String)? {
        // Ask first. A Reel that turns out to be 60 MB is not worth pulling
        // down a phone's data connection to then throw away.
        if let advertised = await contentLength(of: url, referer: referer), advertised > byteLimit {
            Log.importer.info("Post video is \(advertised, privacy: .public) bytes — too big to send inline")
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue(NetworkConstants.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        if let referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                Log.importer.info("Post video fetch refused")
                return nil
            }

            guard data.count <= byteLimit, !data.isEmpty else { return nil }

            let mimeType = response.mimeType?.lowercased()
            return (data, mimeType?.hasPrefix("video/") == true ? mimeType! : "video/mp4")
        } catch {
            Log.importer.info("Post video fetch failed")
            return nil
        }
    }

    private func contentLength(of url: URL, referer: URL?) async -> Int? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue(NetworkConstants.userAgent, forHTTPHeaderField: "User-Agent")
        if let referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }

        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              http.expectedContentLength > 0 else {
            return nil
        }

        return Int(http.expectedContentLength)
    }

    // MARK: - Fetching

    private func html(for url: URL, referer: URL? = nil) async -> String? {
        var request = URLRequest(url: url)
        request.setValue(NetworkConstants.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("en-GB,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        if let referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            return nil
        }

        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    // MARK: - Parsing

    /// Reads whatever media a page advertises. Written against Instagram and
    /// TikTok markup, but everything it looks for is either Open Graph or a
    /// plainly-named JSON key, so it degrades quietly on anything else.
    nonisolated static func media(inHTML html: String, sourceURL: URL?) -> SocialMedia {
        let scanner = HTMLScanner(html: html)

        let videoCandidates = [
            scanner.metaContent(property: "og:video:secure_url"),
            scanner.metaContent(property: "og:video:url"),
            scanner.metaContent(property: "og:video"),
            scanner.metaContent(property: "twitter:player:stream"),
            // TikTok's rehydration blob. `playAddr` is the streaming copy and
            // `downloadAddr` the watermarked one; either will do.
            jsonStringValue(forKey: "playAddr", in: html),
            jsonStringValue(forKey: "downloadAddr", in: html),
            // Instagram's embed payload.
            jsonStringValue(forKey: "video_url", in: html)
        ]

        let videoURL = videoCandidates
            .compactMap { $0 }
            .lazy
            .compactMap { absoluteURL($0, relativeTo: sourceURL) }
            .first { $0.scheme?.hasPrefix("http") == true }

        var images: [URL] = []
        var seen: Set<String> = []

        let imageCandidates = [
            scanner.metaContent(property: "og:image"),
            scanner.metaContent(property: "twitter:image")
        ].compactMap { $0 } + allJSONStringValues(forKey: "display_url", in: html)
            + allJSONStringValues(forKey: "thumbnail_url", in: html)

        for candidate in imageCandidates {
            guard let url = absoluteURL(candidate, relativeTo: sourceURL),
                  url.scheme?.hasPrefix("http") == true,
                  seen.insert(url.absoluteString).inserted else { continue }
            images.append(url)
            // A carousel of ten slides is more than the model needs to read a
            // recipe card, and every one costs a download.
            if images.count >= 6 { break }
        }

        let caption = [
            // TikTok's own name for the caption, and the only place it appears
            // in full — oEmbed truncates it.
            jsonStringValue(forKey: "desc", in: html),
            scanner.metaContent(property: "og:description")
        ]
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .max { $0.count < $1.count }

        return SocialMedia(
            videoURL: videoURL,
            imageURLs: images,
            caption: (caption?.isEmpty ?? true) ? nil : caption
        )
    }

    /// `instagram.com/reel/ABC123/` → `ABC123`. Covers posts, reels, reels
    /// shared as `/reels/`, and IGTV.
    nonisolated static func instagramShortcode(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        let markers: Set<String> = ["p", "reel", "reels", "tv"]

        for (index, part) in parts.enumerated() where markers.contains(part.lowercased()) {
            let next = index + 1
            if next < parts.count, !parts[next].isEmpty {
                return parts[next]
            }
        }

        return nil
    }

    nonisolated static func instagramEmbedURL(shortcode: String) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
        guard let escaped = shortcode.addingPercentEncoding(withAllowedCharacters: allowed),
              !escaped.isEmpty else { return nil }

        return URL(string: "https://www.instagram.com/p/\(escaped)/embed/captioned/")
    }

    /// The embed page renders the caption as markup rather than JSON, inside a
    /// `Caption` div that also carries the poster's name and the timestamp.
    nonisolated static func instagramEmbedCaption(inHTML html: String) -> String? {
        guard let open = html.range(of: "class=\"Caption\""),
              let contentStart = html.range(of: ">", range: open.upperBound..<html.endIndex),
              let close = html.range(of: "</div", range: contentStart.upperBound..<html.endIndex) else {
            return nil
        }

        let text = HTMLScanner.plainText(String(html[contentStart.upperBound..<close.lowerBound]))
        return text.count >= 20 ? text : nil
    }

    // MARK: - JSON scraping

    /// Reads the value of the first `"key":"value"` pair in a page, without
    /// parsing the whole blob — these payloads are megabytes of state we have
    /// no use for, and their shape changes constantly.
    nonisolated static func jsonStringValue(forKey key: String, in text: String) -> String? {
        allJSONStringValues(forKey: key, in: text, limit: 1).first
    }

    nonisolated static func allJSONStringValues(
        forKey key: String,
        in text: String,
        limit: Int = 8
    ) -> [String] {
        var values: [String] = []
        var searchStart = text.startIndex
        let needle = "\"\(key)\":\""

        while values.count < limit,
              let keyRange = text.range(of: needle, range: searchStart..<text.endIndex) {
            searchStart = keyRange.upperBound

            var raw = ""
            var index = keyRange.upperBound

            while index < text.endIndex {
                let character = text[index]

                if character == "\\" {
                    // Keep escapes intact; they're unpicked in one go below.
                    let next = text.index(after: index)
                    guard next < text.endIndex else { break }
                    raw.append(character)
                    raw.append(text[next])
                    index = text.index(after: next)
                    continue
                }

                if character == "\"" { break }

                raw.append(character)
                index = text.index(after: index)
            }

            searchStart = index
            let unescaped = unescapedJSONString(raw)
            if !unescaped.isEmpty {
                values.append(unescaped)
            }
        }

        return values
    }

    /// These payloads escape their URLs twice over — `\/` for the slashes and
    /// `&` for the query separators. Letting JSONSerialization do it means
    /// we handle the unicode escapes properly rather than guessing at the
    /// common ones.
    nonisolated static func unescapedJSONString(_ raw: String) -> String {
        guard let data = "\"\(raw)\"".data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let string = decoded as? String else {
            return raw
                .replacingOccurrences(of: "\\/", with: "/")
                .replacingOccurrences(of: "\\u0026", with: "&")
        }

        return string
    }

    private nonisolated static func absoluteURL(_ string: String, relativeTo base: URL?) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("//") {
            return URL(string: "https:\(trimmed)")
        }
        if trimmed.hasPrefix("/"), let base {
            return URL(string: trimmed, relativeTo: base)?.absoluteURL
        }

        return URL(string: trimmed)
    }
}
