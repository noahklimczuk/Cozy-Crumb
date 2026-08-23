//
//  DurationParser.swift
//  Cozy Crumb
//
//  Two jobs: ISO 8601 durations from structured data ("PT1H30M"), and plain
//  English times inside a step ("simmer for 20 minutes").
//
//  Step times are only read when the step actually states one. A missing time
//  stays missing — a guessed timer is worse than no timer.
//

import Foundation

enum DurationParser {

    // MARK: - ISO 8601

    /// Parses "PT1H30M", "PT20M", "P1DT2H", "PT45S".
    ///
    /// Note the ambiguity in the standard: `M` before the `T` is months, after
    /// it is minutes. Splitting on `T` is what keeps those apart.
    nonisolated static func seconds(fromISO8601 text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard trimmed.hasPrefix("P") else { return nil }

        let body = String(trimmed.dropFirst())
        let datePart: String
        let timePart: String

        if let separator = body.firstIndex(of: "T") {
            datePart = String(body[body.startIndex..<separator])
            timePart = String(body[body.index(after: separator)...])
        } else {
            datePart = body
            timePart = ""
        }

        var total = 0
        var found = false

        for (value, unit) in components(of: datePart) {
            switch unit {
            case "D": total += value * 86_400; found = true
            case "W": total += value * 604_800; found = true
            // Years and months are not meaningful for a recipe; ignore rather
            // than inventing a length for them.
            default: break
            }
        }

        for (value, unit) in components(of: timePart) {
            switch unit {
            case "H": total += value * 3600; found = true
            case "M": total += value * 60; found = true
            case "S": total += value; found = true
            default: break
            }
        }

        return found ? total : nil
    }

    nonisolated static func minutes(fromISO8601 text: String) -> Int? {
        guard let seconds = seconds(fromISO8601: text) else { return nil }
        return seconds / 60
    }

    /// Splits "1H30M" into [(1, "H"), (30, "M")].
    private nonisolated static func components(of text: String) -> [(Int, String)] {
        var results: [(Int, String)] = []
        var digits = ""

        for character in text {
            if character.isNumber {
                digits.append(character)
            } else if character == "." || character == "," {
                // Fractional durations are legal but vanishingly rare here.
                digits.append(".")
            } else if let value = Double(digits) {
                results.append((Int(value), String(character)))
                digits = ""
            } else {
                digits = ""
            }
        }

        return results
    }

    // MARK: - Plain English

    private nonisolated static let unitSeconds: [String: Int] = [
        "second": 1, "seconds": 1, "sec": 1, "secs": 1,
        "minute": 60, "minutes": 60, "min": 60, "mins": 60,
        "hour": 3600, "hours": 3600, "hr": 3600, "hrs": 3600
    ]

    /// Finds the first stated duration in a step, or nil.
    ///
    /// Adjacent larger-then-smaller pairs combine, so "1 hour 30 minutes" is
    /// 5400 seconds. Times mentioned later in the step are ignored: a step
    /// saying "rest 5 minutes, then bake 40" should time the thing it opens
    /// with, not the sum of everything in the sentence.
    nonisolated static func seconds(inStepText text: String) -> Int? {
        // "." and "/" survive the split so "1.5" and "1/2" stay whole, which
        // also glues a sentence's full stop onto the last word: "20 minutes."
        // yields the token "minutes.", which matches no unit, so the step
        // silently loses its timer. Trimming only the edges keeps the
        // fractions intact.
        let tokens = text
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "." && $0 != "/" && !QuantityParser.unicodeFractions.keys.contains($0) })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "./")) }
            .filter { !$0.isEmpty }

        var index = 0
        while index < tokens.count {
            guard let value = QuantityParser.parse(tokens[index]),
                  index + 1 < tokens.count,
                  let multiplier = unitSeconds[tokens[index + 1]] else {
                index += 1
                continue
            }

            var total = Int((value * Double(multiplier)).rounded())
            var next = index + 2

            // "1 hour 30 minutes"
            if next + 1 < tokens.count,
               let secondValue = QuantityParser.parse(tokens[next]),
               let secondMultiplier = unitSeconds[tokens[next + 1]],
               secondMultiplier < multiplier {
                total += Int((secondValue * Double(secondMultiplier)).rounded())
                next += 2
            }

            return total
        }

        return nil
    }

    // MARK: - Display

    /// "20 min", "1 hr 30 min". Shared by the timer chips so nothing has to
    /// build a throwaway model object just to format a number.
    nonisolated static func display(seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }

        let totalMinutes = seconds / 60
        guard totalMinutes >= 1 else { return "\(seconds) sec" }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        return switch (hours, minutes) {
        case (0, let m): "\(m) min"
        case (let h, 0): "\(h) hr"
        case (let h, let m): "\(h) hr \(m) min"
        }
    }

    // MARK: - Yield

    /// Pulls a serving count out of "4 servings", "Serves 6", "makes 12".
    nonisolated static func servings(from text: String) -> Int? {
        let tokens = text
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)

        for token in tokens {
            if let value = Int(token), value > 0, value <= 200 {
                return value
            }
        }

        return nil
    }
}
