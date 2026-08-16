//
//  Typography.swift
//  Cozy Crumb
//
//  SF Rounded throughout — it carries the whole personality (§7.3).
//
//  These are built on semantic text styles rather than fixed point sizes so
//  Dynamic Type scales them for free, all the way to AX5. Fixed sizes via
//  .system(size:) do not scale at all, which would break the §7.6 requirement.
//  The trade is that Apple's style sizes sit near, not exactly on, the sizes
//  listed in the spec (Title lands at 28 rather than 24, Body at 17 rather
//  than 16, Caption at 12 rather than 13).
//
//  `nonisolated` for the same reason as Theme — see the note there.
//

import SwiftUI

enum CozyFont {
    /// 34pt Bold — screen titles, the mascot's big moments.
    nonisolated static let display = Font.system(.largeTitle, design: .rounded, weight: .bold)

    /// Section headers, recipe titles on detail screens.
    nonisolated static let title = Font.system(.title, design: .rounded, weight: .bold)

    /// Card titles.
    nonisolated static let title2 = Font.system(.title2, design: .rounded, weight: .bold)

    /// Emphasis within body copy, list row titles.
    nonisolated static let headline = Font.system(.headline, design: .rounded, weight: .semibold)

    /// Default reading text.
    nonisolated static let body = Font.system(.body, design: .rounded)

    /// Body with emphasis.
    nonisolated static let bodyEmphasis = Font.system(.body, design: .rounded, weight: .semibold)

    /// Supporting text under a title.
    nonisolated static let subheadline = Font.system(.subheadline, design: .rounded)

    /// Pills, tags, metadata.
    nonisolated static let caption = Font.system(.caption, design: .rounded, weight: .medium)

    /// Smallest supporting text — source attributions.
    nonisolated static let caption2 = Font.system(.caption2, design: .rounded)

    /// Cook Mode step text. Deliberately huge and readable across a kitchen.
    ///
    /// Built on `.title` rather than a fixed 28pt: the style lands at 28pt at
    /// the default text size anyway, and this way the one screen someone reads
    /// from two feet away with steamed-up glasses still scales with Dynamic
    /// Type, like everything else here.
    nonisolated static let cookStep = Font.system(.title, design: .rounded, weight: .semibold)
}

extension View {
    /// Applies a font and the matching ink colour in one step.
    nonisolated func cozyText(_ font: Font, color: Color = CozyColor.inkPrimary) -> some View {
        self.font(font).foregroundStyle(color)
    }
}
