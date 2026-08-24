//
//  Typography.swift
//  Cozy Crumb
//
//  Two faces, one of them optional.
//
//  Body copy is SF Rounded, as it always was — it carries the personality and
//  it is already on every device (§7.3). Headings want something with more
//  character than SF has at heavy weights, so they ask for Bricolage Grotesque
//  and fall back to SF Rounded Heavy when it isn't in the bundle.
//
//  That fallback is not a stub. The app ships and looks right with no font
//  files at all; adding `BricolageGrotesque-ExtraBold.ttf` and
//  `-SemiBold.ttf` to the target and listing both under `UIAppFonts` is a
//  purely additive change that `hasDisplayFace` picks up at launch.
//
//  These are built on semantic text styles rather than fixed point sizes so
//  Dynamic Type scales them for free, all the way to AX5. Fixed sizes via
//  .system(size:) do not scale at all, which would break the §7.6 requirement,
//  and `Font.custom(_:size:relativeTo:)` is the custom-face equivalent.
//
//  `nonisolated` for the same reason as Theme — see the note there.
//

import CoreText
import SwiftUI

enum CozyFont {

    // MARK: - The display face

    /// PostScript names, not file names. These are what the font actually
    /// calls itself once registered; the filenames are irrelevant to lookup.
    ///
    /// `nonisolated` because everything that reads them is: the target
    /// defaults types to MainActor, so an unannotated constant here is
    /// main-actor isolated and `hasDisplayFace` below — which is explicitly
    /// nonisolated — cannot see it.
    nonisolated private static let displayFaceName = "BricolageGrotesque-ExtraBold"
    nonisolated private static let displaySoftFaceName = "BricolageGrotesque-SemiBold"

    /// Whether the display face is actually installed in this build.
    ///
    /// Asked through CoreText rather than `UIFont(name:)` because this is a
    /// `nonisolated` constant and CoreText is a plain C API with no actor
    /// isolation of its own. `CTFontCreateWithName` never fails — it
    /// substitutes — so the answer is whether the font we got back is the one
    /// we asked for.
    nonisolated static let hasDisplayFace: Bool = isInstalled(displayFaceName)

    nonisolated private static func isInstalled(_ postScriptName: String) -> Bool {
        let font = CTFontCreateWithName(postScriptName as CFString, 12, nil)
        return (CTFontCopyPostScriptName(font) as String) == postScriptName
    }

    /// A heading font: the display face at `size`, scaling against `style`, or
    /// SF Rounded at `weight` when the face isn't there.
    nonisolated private static func heading(
        _ size: CGFloat,
        relativeTo style: Font.TextStyle,
        soft: Bool = false,
        fallback weight: Font.Weight
    ) -> Font {
        guard hasDisplayFace else {
            return .system(style, design: .rounded, weight: weight)
        }
        return .custom(soft ? displaySoftFaceName : displayFaceName, size: size, relativeTo: style)
    }

    // MARK: - Headings

    /// Screen titles, the mascot's big moments. The largest thing in the app.
    nonisolated static let display = heading(34, relativeTo: .largeTitle, fallback: .heavy)

    /// Section headers, recipe titles on detail screens.
    nonisolated static let title = heading(28, relativeTo: .title, fallback: .heavy)

    /// Card titles.
    nonisolated static let title2 = heading(22, relativeTo: .title2, fallback: .bold)

    /// Emphasis within body copy, list row titles.
    nonisolated static let headline = Font.system(.headline, design: .rounded, weight: .semibold)

    /// The small all-caps line above a screen title. Tracked out in
    /// `ScreenHeader` rather than here, because tracking is a view modifier.
    nonisolated static let eyebrow = Font.system(.caption2, design: .rounded, weight: .bold)

    // MARK: - Body

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

    // MARK: - Numbers

    /// Standing numbers: the servings stepper, a countdown, a quantity that
    /// changes in place. Monospaced digits so the layout doesn't twitch as the
    /// value ticks over — 11 must be exactly as wide as 88.
    nonisolated static let numeral = Font.system(.title2, design: .rounded, weight: .bold)
        .monospacedDigit()

    /// The same, small enough to sit inside a row.
    nonisolated static let numeralSmall = Font.system(.subheadline, design: .rounded, weight: .bold)
        .monospacedDigit()

    // MARK: - Cook Mode

    /// Cook Mode step text. Deliberately huge and readable across a kitchen.
    ///
    /// Built on `.title` rather than a fixed 28pt: the style lands at 28pt at
    /// the default text size anyway, and this way the one screen someone reads
    /// from two feet away with steamed-up glasses still scales with Dynamic
    /// Type, like everything else here. Takes the display face's *SemiBold*,
    /// not its ExtraBold — a paragraph set in the heading weight is a wall.
    nonisolated static let cookStep = heading(28, relativeTo: .title, soft: true, fallback: .semibold)
}

extension View {
    /// Applies a font and the matching ink colour in one step.
    nonisolated func cozyText(_ font: Font, color: Color = CozyColor.inkPrimary) -> some View {
        self.font(font).foregroundStyle(color)
    }

    /// The small tracked-out capitals above a screen title.
    nonisolated func cozyEyebrow(color: Color = CozyColor.inkTertiary) -> some View {
        self.font(CozyFont.eyebrow)
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
