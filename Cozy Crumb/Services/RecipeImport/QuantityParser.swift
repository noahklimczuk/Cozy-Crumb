//
//  QuantityParser.swift
//  Cozy Crumb
//
//  Reads the numbers people actually write on recipes: 1, 1.5, 1/2, ½, 1½,
//  and ranges like "1-2" or "1 to 2".
//

import Foundation

enum QuantityParser {

    /// Unicode fraction characters and what they're worth.
    nonisolated static let unicodeFractions: [Character: Double] = [
        "½": 1.0 / 2, "⅓": 1.0 / 3, "⅔": 2.0 / 3,
        "¼": 1.0 / 4, "¾": 3.0 / 4,
        "⅕": 1.0 / 5, "⅖": 2.0 / 5, "⅗": 3.0 / 5, "⅘": 4.0 / 5,
        "⅙": 1.0 / 6, "⅚": 5.0 / 6,
        "⅐": 1.0 / 7,
        "⅛": 1.0 / 8, "⅜": 3.0 / 8, "⅝": 5.0 / 8, "⅞": 7.0 / 8,
        "⅑": 1.0 / 9, "⅒": 1.0 / 10
    ]

    /// Parses a single token: "2", "1.5", "3/4", "½", "1½".
    nonisolated static func parse(_ token: String) -> Double? {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // A bare unicode fraction, possibly with a leading whole number.
        if let fractionCharacter = trimmed.last, let fractionValue = unicodeFractions[fractionCharacter] {
            let prefix = String(trimmed.dropLast())
            if prefix.isEmpty { return fractionValue }
            if let whole = Double(prefix) { return whole + fractionValue }
            return nil
        }

        // "3/4"
        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/")
            guard parts.count == 2,
                  let numerator = Double(parts[0]),
                  let denominator = Double(parts[1]),
                  denominator != 0 else { return nil }
            return numerator / denominator
        }

        // Decimal comma, common outside the US.
        if trimmed.contains(","), !trimmed.contains("."), let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")) {
            return value
        }

        return Double(trimmed)
    }

    /// Splits a token that runs a number straight into a word: "100g" becomes
    /// ("100", "g"). Returns nil when the token is all number or all word,
    /// since there is nothing to separate.
    nonisolated static func splitLeadingNumber(_ token: String) -> (number: String, rest: String)? {
        var number = ""
        var index = token.startIndex

        while index < token.endIndex {
            let character = token[index]
            let isNumeric = character.isNumber
                || character == "."
                || character == ","
                || character == "/"
                || unicodeFractions[character] != nil

            guard isNumeric else { break }

            number.append(character)
            index = token.index(after: index)
        }

        guard !number.isEmpty, index < token.endIndex else { return nil }

        let rest = String(token[index...])
        guard rest.contains(where: \.isLetter) else { return nil }

        return (number, rest)
    }

    /// Pulls a quantity off the front of a line, returning it and what's left.
    ///
    /// Handles mixed numbers written with a space ("1 1/2 cup", "1 ½ cup") and
    /// ranges, where the lower bound wins — cooking down is easier than up.
    nonisolated static func leadingQuantity(in line: String) -> (value: Double, remainder: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        var tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !tokens.isEmpty else { return nil }

        var first = tokens[0]

        // Ranges: "1-2", "1–2", "1 to 2". Take the lower bound.
        for separator in ["-", "–", "—"] where first.contains(separator) {
            let parts = first.components(separatedBy: separator)
            if parts.count == 2, parse(parts[0]) != nil, parse(parts[1]) != nil {
                first = parts[0]
            }
        }

        // Captions jam the number and the unit together — "100g butter",
        // "2tbsp oil", "500ml stock" — where a recipe site would write
        // "100 g butter". Splitting them here is what lets the unit be
        // recognised at all, and without it the whole line parses as having
        // no quantity.
        var jammedUnit: String?
        if parse(first) == nil, let split = splitLeadingNumber(first) {
            first = split.number
            jammedUnit = split.rest
        }

        guard var value = parse(first) else { return nil }
        tokens.removeFirst()

        if let jammedUnit {
            tokens.insert(jammedUnit, at: 0)
        }

        // "1 to 2 cups"
        if tokens.count >= 2, tokens[0].lowercased() == "to", parse(tokens[1]) != nil {
            tokens.removeFirst(2)
        } else if let next = tokens.first {
            // Mixed number split across tokens: "1 1/2" or "1 ½".
            let isWholeNumber = value == value.rounded() && !first.contains("/")
            if isWholeNumber, let fraction = parse(next), fraction < 1 {
                value += fraction
                tokens.removeFirst()
            }
        }

        return (value, tokens.joined(separator: " "))
    }
}
