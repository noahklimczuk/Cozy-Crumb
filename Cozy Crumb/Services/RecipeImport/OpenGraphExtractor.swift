//
//  OpenGraphExtractor.swift
//  Cozy Crumb
//
//  Not a tier of its own — Open Graph tags never contain a real recipe. Two
//  jobs instead:
//
//    1. fill the hero image and source name when a structured tier found a
//       recipe but no picture
//    2. provide the raw material for social imports, where the caption sits in
//       og:description and needs the AI parser (Phase 7) to make sense of it
//
//  OG tags are served to unauthenticated crawlers, which is why this works on
//  sites that otherwise refuse to be read.
//

import Foundation

struct OpenGraphMetadata: Sendable, Equatable {
    var title: String?
    var description: String?
    var imageURL: URL?
    var siteName: String?

    nonisolated init(
        title: String? = nil,
        description: String? = nil,
        imageURL: URL? = nil,
        siteName: String? = nil
    ) {
        self.title = title
        self.description = description
        self.imageURL = imageURL
        self.siteName = siteName
    }

    nonisolated var isEmpty: Bool {
        title == nil && description == nil && imageURL == nil
    }
}

struct OpenGraphExtractor: Sendable {
    nonisolated init() {}

    nonisolated func extract(from html: String, sourceURL: URL?) -> OpenGraphMetadata {
        let scanner = HTMLScanner(html: html)

        let imageString = scanner.metaContent(property: "og:image")
            ?? scanner.metaContent(property: "twitter:image")

        return OpenGraphMetadata(
            title: scanner.metaContent(property: "og:title")
                ?? scanner.metaContent(property: "twitter:title")
                ?? titleTag(in: html),
            description: scanner.metaContent(property: "og:description")
                ?? scanner.metaContent(property: "twitter:description")
                ?? scanner.metaContent(attribute: "name", value: "description"),
            imageURL: imageString.flatMap { absoluteURL($0, relativeTo: sourceURL) },
            siteName: scanner.metaContent(property: "og:site_name") ?? sourceURL?.host()
        )
    }

    /// Some sites publish protocol-relative or root-relative image paths.
    private nonisolated func absoluteURL(_ string: String, relativeTo base: URL?) -> URL? {
        if string.hasPrefix("//") {
            return URL(string: "https:\(string)")
        }
        if string.hasPrefix("/"), let base {
            return URL(string: string, relativeTo: base)?.absoluteURL
        }
        return URL(string: string)
    }

    private nonisolated func titleTag(in html: String) -> String? {
        guard let open = html.range(of: "<title", options: .caseInsensitive),
              let openEnd = html.range(of: ">", range: open.upperBound..<html.endIndex),
              let close = html.range(of: "</title", options: .caseInsensitive, range: openEnd.upperBound..<html.endIndex)
        else { return nil }

        let text = HTMLScanner.plainText(String(html[openEnd.upperBound..<close.lowerBound]))
        return text.isEmpty ? nil : text
    }
}
