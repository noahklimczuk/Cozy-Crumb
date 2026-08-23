//
//  HTMLScanner.swift
//  Cozy Crumb
//
//  A deliberately small HTML reader. Not a parser — it does not build a tree,
//  and it would lose an argument with malformed markup. It does exactly the
//  four things the import cascade needs:
//
//    1. pull out <script type="application/ld+json"> blocks
//    2. read <meta> content by property or name
//    3. find elements carrying a given attribute (itemprop="recipeIngredient")
//    4. turn a chunk of markup into readable plain text
//
//  Searching is case-insensitive and done on the original string via
//  range(of:options:), never on a lowercased copy — lowercasing can change
//  string length for some scripts, which would misalign every index.
//

import Foundation

struct HTMLElement: Sendable, Equatable {
    let tagName: String
    /// The raw open tag, e.g. `<li itemprop="recipeIngredient" class="x">`.
    let openTag: String
    /// Markup between the open and close tags. Empty for void elements.
    let innerHTML: String

    /// Explicitly nonisolated so the scanner's nonisolated methods can build
    /// these — the target's default MainActor isolation would otherwise
    /// isolate the implicit memberwise init.
    nonisolated init(tagName: String, openTag: String, innerHTML: String) {
        self.tagName = tagName
        self.openTag = openTag
        self.innerHTML = innerHTML
    }

    /// Readable text content.
    nonisolated var text: String {
        HTMLScanner.plainText(innerHTML)
    }

    /// Text with one line per block-level element.
    ///
    /// `text` flattens everything to a single line, which is right for a
    /// title or an ingredient but loses the only thing that separates one
    /// instruction from the next when a method is marked up as a run of
    /// `<p>` or `<li>`.
    nonisolated var blockSeparatedText: String {
        HTMLScanner.blockSeparatedText(innerHTML)
    }

    /// Microdata often carries the value in `content=` on a void element.
    nonisolated var contentAttribute: String? {
        HTMLScanner.attributeValue("content", in: openTag)
    }

    /// The value a microdata consumer should read: element text if there is
    /// any, otherwise the content attribute.
    nonisolated var microdataValue: String? {
        let inner = text
        if !inner.isEmpty { return inner }
        return contentAttribute.map { HTMLScanner.decodeEntities($0) }
    }
}

struct HTMLScanner: Sendable {
    let html: String

    nonisolated init(html: String) {
        self.html = html
    }

    /// Elements that never have a closing tag.
    private nonisolated static let voidElements: Set<String> = [
        "meta", "img", "br", "hr", "link", "input", "source", "area", "base", "col"
    ]

    // MARK: - Script blocks

    /// Contents of every `<script>` whose type attribute matches.
    nonisolated func scriptContents(type: String) -> [String] {
        var results: [String] = []
        var cursor = html.startIndex

        while let openStart = html.range(of: "<script", options: .caseInsensitive, range: cursor..<html.endIndex) {
            guard let openEnd = html.range(of: ">", range: openStart.upperBound..<html.endIndex) else { break }

            let openTag = String(html[openStart.lowerBound..<openEnd.upperBound])
            let bodyStart = openEnd.upperBound

            guard let closeRange = html.range(of: "</script", options: .caseInsensitive, range: bodyStart..<html.endIndex) else {
                break
            }

            if let declaredType = Self.attributeValue("type", in: openTag),
               declaredType.compare(type, options: .caseInsensitive) == .orderedSame {
                results.append(String(html[bodyStart..<closeRange.lowerBound]))
            }

            cursor = closeRange.upperBound
        }

        return results
    }

    // MARK: - Meta tags

    nonisolated func metaContent(property: String) -> String? {
        metaContent(attribute: "property", value: property)
            ?? metaContent(attribute: "name", value: property)
    }

    nonisolated func metaContent(attribute: String, value: String) -> String? {
        for element in elements(withAttribute: attribute, value: value) where element.tagName == "meta" {
            if let content = element.contentAttribute, !content.isEmpty {
                return Self.decodeEntities(content)
            }
        }
        return nil
    }

    // MARK: - Elements

    /// Every element whose `attribute` equals `value`.
    ///
    /// Matching is exact after trimming, except that microdata allows
    /// space-separated lists (`itemprop="name description"`), so those are
    /// split and checked individually.
    nonisolated func elements(withAttribute attribute: String, value: String) -> [HTMLElement] {
        var results: [HTMLElement] = []
        var cursor = html.startIndex

        while let attributeRange = html.range(
            of: attribute,
            options: .caseInsensitive,
            range: cursor..<html.endIndex
        ) {
            cursor = attributeRange.upperBound

            // Walk back to the '<' that opens this tag.
            guard let tagStart = html.range(
                of: "<",
                options: .backwards,
                range: html.startIndex..<attributeRange.lowerBound
            )?.lowerBound else { continue }

            guard let tagEnd = html.range(of: ">", range: attributeRange.upperBound..<html.endIndex) else {
                break
            }

            let openTag = String(html[tagStart..<tagEnd.upperBound])

            // The attribute must belong to this tag, not sit in text before it.
            guard let found = Self.attributeValue(attribute, in: openTag) else { continue }

            let matches = found
                .split(separator: " ")
                .contains { $0.compare(value, options: .caseInsensitive) == .orderedSame }
            guard matches else { continue }

            guard let tagName = Self.tagName(of: openTag) else { continue }

            let inner: String
            if Self.voidElements.contains(tagName) || openTag.hasSuffix("/>") {
                inner = ""
            } else {
                inner = innerHTML(ofTag: tagName, startingAfter: tagEnd.upperBound)
            }

            results.append(HTMLElement(tagName: tagName, openTag: openTag, innerHTML: inner))
            cursor = tagEnd.upperBound
        }

        return results
    }

    /// Scans forward tracking nesting depth so a `<div>` inside a `<div>`
    /// doesn't end the outer one early.
    private nonisolated func innerHTML(ofTag tagName: String, startingAfter index: String.Index) -> String {
        var depth = 1
        var cursor = index

        while cursor < html.endIndex {
            let openNext = html.range(of: "<\(tagName)", options: .caseInsensitive, range: cursor..<html.endIndex)
            let closeNext = html.range(of: "</\(tagName)", options: .caseInsensitive, range: cursor..<html.endIndex)

            guard let closeNext else {
                // Unbalanced markup — take what's left rather than nothing.
                return String(html[index..<html.endIndex])
            }

            if let openNext, openNext.lowerBound < closeNext.lowerBound {
                depth += 1
                cursor = openNext.upperBound
                continue
            }

            depth -= 1
            if depth == 0 {
                return String(html[index..<closeNext.lowerBound])
            }
            cursor = closeNext.upperBound
        }

        return String(html[index..<html.endIndex])
    }

    // MARK: - Tag helpers

    /// `<li class="x">` → `li`
    nonisolated static func tagName(of openTag: String) -> String? {
        var name = ""
        var started = false

        for character in openTag {
            if character == "<" {
                started = true
                continue
            }
            guard started else { continue }
            if character.isLetter || character.isNumber {
                name.append(character)
            } else {
                break
            }
        }

        return name.isEmpty ? nil : name.lowercased()
    }

    /// Reads an attribute's value out of an open tag. Handles double quotes,
    /// single quotes, and unquoted values.
    nonisolated static func attributeValue(_ attribute: String, in openTag: String) -> String? {
        var cursor = openTag.startIndex

        while let nameRange = openTag.range(
            of: attribute,
            options: .caseInsensitive,
            range: cursor..<openTag.endIndex
        ) {
            cursor = nameRange.upperBound

            // Must be a whole attribute name: preceded by whitespace or '<',
            // so "property" doesn't match inside "data-property".
            if nameRange.lowerBound > openTag.startIndex {
                let before = openTag[openTag.index(before: nameRange.lowerBound)]
                guard before.isWhitespace || before == "<" else { continue }
            }

            // Skip whitespace, expect '='.
            var index = nameRange.upperBound
            while index < openTag.endIndex, openTag[index].isWhitespace {
                index = openTag.index(after: index)
            }
            guard index < openTag.endIndex, openTag[index] == "=" else { continue }
            index = openTag.index(after: index)
            while index < openTag.endIndex, openTag[index].isWhitespace {
                index = openTag.index(after: index)
            }
            guard index < openTag.endIndex else { continue }

            let quote = openTag[index]
            if quote == "\"" || quote == "'" {
                let valueStart = openTag.index(after: index)
                guard let closing = openTag[valueStart...].firstIndex(of: quote) else { continue }
                return String(openTag[valueStart..<closing])
            }

            // Unquoted: run to whitespace or the end of the tag.
            var end = index
            while end < openTag.endIndex, !openTag[end].isWhitespace, openTag[end] != ">" {
                end = openTag.index(after: end)
            }
            return String(openTag[index..<end])
        }

        return nil
    }

    // MARK: - Text

    /// Markup in, readable text out: tags removed, entities decoded,
    /// whitespace collapsed.
    nonisolated static func plainText(_ markup: String) -> String {
        collapseWhitespace(decodeEntities(stripTags(markup)))
    }

    /// Removes tags. Block-level tags become spaces so words don't fuse
    /// together when `<li>a</li><li>b</li>` collapses.
    nonisolated static func stripTags(_ markup: String) -> String {
        var output = ""
        output.reserveCapacity(markup.count)

        var insideTag = false
        for character in markup {
            if character == "<" {
                insideTag = true
                output.append(" ")
            } else if character == ">" {
                insideTag = false
            } else if !insideTag {
                output.append(character)
            }
        }

        return output
    }

    private nonisolated static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "ndash": "–", "mdash": "—", "hellip": "…",
        "rsquo": "\u{2019}", "lsquo": "\u{2018}", "rdquo": "\u{201D}",
        "ldquo": "\u{201C}", "deg": "°", "frac12": "½", "frac14": "¼",
        "frac34": "¾", "frac13": "⅓", "frac23": "⅔", "times": "×",
        "middot": "·", "bull": "•", "eacute": "é", "egrave": "è",
        "agrave": "à", "ccedil": "ç", "ouml": "ö", "uuml": "ü"
    ]

    /// Decodes named and numeric entities. Unknown entities are left as-is —
    /// showing `&weird;` beats deleting text we didn't understand.
    nonisolated static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }

        var output = ""
        output.reserveCapacity(text.count)

        var cursor = text.startIndex
        while cursor < text.endIndex {
            guard text[cursor] == "&",
                  let semicolon = text[cursor...].firstIndex(of: ";"),
                  text.distance(from: cursor, to: semicolon) <= 10 else {
                output.append(text[cursor])
                cursor = text.index(after: cursor)
                continue
            }

            let body = String(text[text.index(after: cursor)..<semicolon])

            if body.hasPrefix("#") {
                let digits = String(body.dropFirst())
                let scalarValue: UInt32?

                if digits.hasPrefix("x") || digits.hasPrefix("X") {
                    scalarValue = UInt32(digits.dropFirst(), radix: 16)
                } else {
                    scalarValue = UInt32(digits)
                }

                if let scalarValue, let scalar = Unicode.Scalar(scalarValue) {
                    output.append(Character(scalar))
                    cursor = text.index(after: semicolon)
                    continue
                }
            } else if let replacement = namedEntities[body.lowercased()] {
                output.append(replacement)
                cursor = text.index(after: semicolon)
                continue
            }

            output.append(text[cursor])
            cursor = text.index(after: cursor)
        }

        return output
    }

    /// Runs of whitespace become one space; leading and trailing trimmed.
    nonisolated static func collapseWhitespace(_ text: String) -> String {
        text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Tags that end a chunk of prose. A `<span>` inside a sentence does not;
    /// a `<p>` between two sentences does.
    nonisolated static let blockTags: Set<String> = [
        "p", "li", "div", "br", "tr", "td", "section", "article",
        "h1", "h2", "h3", "h4", "h5", "h6", "ol", "ul", "dd", "dt", "blockquote"
    ]

    /// Like `plainText`, but keeps block boundaries as line breaks.
    ///
    /// Separate from `plainText` rather than replacing it: `text` is read by
    /// every extractor for titles, ingredients and yields, all of which want
    /// one flat line. Only the method needs its blocks kept apart.
    nonisolated static func blockSeparatedText(_ markup: String) -> String {
        var output = ""
        output.reserveCapacity(markup.count)

        var tagBuffer = ""
        var insideTag = false

        for character in markup {
            if character == "<" {
                insideTag = true
                tagBuffer = ""
            } else if character == ">" {
                insideTag = false
                output.append(isBlockTag(tagBuffer) ? "\n" : " ")
            } else if insideTag {
                tagBuffer.append(character)
            } else {
                output.append(character)
            }
        }

        return decodeEntities(output)
            .components(separatedBy: .newlines)
            .map(collapseWhitespace)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// Reads the tag name out of the inside of a tag, opening or closing.
    private nonisolated static func isBlockTag(_ tagBody: String) -> Bool {
        let name = tagBody
            .drop { $0 == "/" }
            .prefix { $0.isLetter || $0.isNumber }
            .lowercased()

        return blockTags.contains(name)
    }
}
