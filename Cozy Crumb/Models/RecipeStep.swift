//
//  RecipeStep.swift
//  Cozy Crumb
//
//  One numbered instruction. `durationSeconds` is set only when the step
//  states an explicit time, and it powers the inline timer chips in Recipe
//  Detail and the stacked timers in Cook Mode.
//

import Foundation
import SwiftData

@Model
final class RecipeStep {
    @Attribute(.unique) var id: UUID
    var order: Int
    var text: String

    /// Parsed from phrasing like "simmer for 20 minutes". nil when the step
    /// states no time — never guessed.
    var durationSeconds: Int?

    @Attribute(.externalStorage) var imageData: Data?

    var recipe: Recipe?

    init(
        id: UUID = UUID(),
        order: Int,
        text: String,
        durationSeconds: Int? = nil,
        imageData: Data? = nil
    ) {
        self.id = id
        self.order = order
        self.text = text
        self.durationSeconds = durationSeconds
        self.imageData = imageData
    }
}

extension RecipeStep {
    var hasTimer: Bool { durationSeconds != nil }

    /// "20 min", "1 hr 30 min" — the label on the timer chip.
    var durationDisplay: String? {
        guard let durationSeconds, durationSeconds > 0 else { return nil }
        let totalMinutes = durationSeconds / 60

        guard totalMinutes >= 1 else { return "\(durationSeconds) sec" }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        return switch (hours, minutes) {
        case (0, let m): "\(m) min"
        case (let h, 0): "\(h) hr"
        case (let h, let m): "\(h) hr \(m) min"
        }
    }
}
