//
//  Typography.swift
//  Cozy Crumb
//
//  Two faces. The display one is no longer optional.
//
//  Body copy is SF Rounded, as it always was — it carries the personality and
//  it is already on every device (§7.3). Headings are Bricolage Grotesque
//  ExtraBold, tracked tight and set large, and that is now half the character
//  of the app rather than an upgrade on a fallback: a 52pt two-line screen
//  title at -0.035em is a different design in SF Rounded Heavy.
//
//  The fallback path is still here and still correct, so a build that somehow
//  loses the font files renders rather than crashes. It just isn't the one
//  anybody should be looking at. Both faces ship in Resources/Fonts and are
//  listed under `UIAppFonts`; `hasDisplayFace` is the check that they landed.
//
//  The faces are cut at a 1.09em line height rather than upstream's 1.20,
//  which is where the tight display leading comes from — SwiftUI cannot set a
//  line height below the font's own. See Resources/Fonts/README.md.
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

    /// The Cookbook's title, and nothing else. Set larger than every other
    /// screen and broken onto two lines, because the cookbook is the app.
    nonisolated static let displayHero = heading(52, relativeTo: .largeTitle, fallback: .heavy)

    /// Screen titles, and the recipe title over a hero.
    nonisolated static let display = heading(44, relativeTo: .largeTitle, fallback: .heavy)

    /// The one big line on a screen that has no header slab — Sous Chef's
    /// "Ask me anything".
    nonisolated static let title = heading(32, relativeTo: .title, fallback: .heavy)

    /// Section headings: "Ingredients", "Method", "All recipes".
    nonisolated static let title2 = heading(26, relativeTo: .title2, fallback: .heavy)

    /// The smallest heading that still gets the display face at a size you'd
    /// call a heading — a pantry item's name, the servings value, "Next step".
    nonisolated static let title3 = heading(20, relativeTo: .title3, fallback: .bold)

    /// Titles on a card: a recipe card, a settings group, "Start cooking".
    ///
    /// This is where the display face takes over from `headline`. A recipe
    /// card's title is the thing you actually read the grid for, and in SF
    /// Rounded semibold it was competing with the metadata under it.
    nonisolated static let cardTitle = heading(19, relativeTo: .headline, fallback: .bold)

    /// Emphasis within body copy, list row titles.
    nonisolated static let headline = Font.system(.headline, design: .rounded, weight: .semibold)

    /// The small all-caps line above a screen title. Tracked out by
    /// `cozyEyebrow` rather than here, because tracking is a view modifier.
    nonisolated static let eyebrow = Font.system(.caption2, design: .rounded, weight: .bold)

    /// An eyebrow that wants the display face — Cook Mode's "STEP ONE OF SIX",
    /// which is a heading pretending to be a label.
    nonisolated static let eyebrowDisplay = heading(15, relativeTo: .subheadline, fallback: .bold)

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
    /// Built on `.title` rather than a fixed size: the one screen someone
    /// reads from two feet away with steamed-up glasses still scales with
    /// Dynamic Type, like everything else here. Takes the display face's
    /// *SemiBold*, not its ExtraBold — a paragraph set in the heading weight
    /// is a wall.
    nonisolated static let cookStep = heading(34, relativeTo: .title, soft: true, fallback: .semibold)
}

// MARK: - Tracking and leading

/// Tracking for the display face, in points at each style's design size.
///
/// The design specifies these in ems and SwiftUI's `.tracking(_:)` takes
/// points, so each one is the em value multiplied out: -0.035em at 52pt is
/// -1.8pt. `cozyDisplayTracking` scales them with Dynamic Type from there, so
/// the ratio survives at AX5.
///
/// Tracking is a property of a *run of text*, not of a font, which is why
/// these are not folded into the `CozyFont` values — a `Font` cannot carry
/// them and a view modifier can.
enum CozyTracking {
    /// -0.035em at 52pt.
    nonisolated static let displayHero: CGFloat = -1.8
    /// -0.035em at 44pt.
    nonisolated static let display: CGFloat = -1.55
    /// -0.03em at 32pt.
    nonisolated static let title: CGFloat = -0.95
    /// -0.025em at 26pt.
    nonisolated static let title2: CGFloat = -0.65
    /// -0.02em at 20pt.
    nonisolated static let title3: CGFloat = -0.4
    /// -0.02em at 19pt.
    nonisolated static let cardTitle: CGFloat = -0.38
    /// -0.02em at 34pt.
    nonisolated static let cookStep: CGFloat = -0.7

    // Eyebrows track *out*, not in. These are the em values the design uses,
    // multiplied out at the 10pt the eyebrow style sets at.
    /// .24em — the Cookbook's "COZY CRUMB".
    nonisolated static let eyebrowWide: CGFloat = 2.4
    /// .20em — the default: screen captions, a recipe's source.
    nonisolated static let eyebrow: CGFloat = 2.0
    /// .12em — aisle tags and urgency tags, which are shorter and tighter.
    nonisolated static let eyebrowTight: CGFloat = 1.2
    /// .14em at 15pt — Cook Mode's step label, which is set in the display face.
    nonisolated static let eyebrowStep: CGFloat = 2.1
}

/// Extra leading, in points at the design size.
///
/// Only ever positive. The display face is cut at a 1.09em line height (see
/// the note in Resources/Fonts/README.md) so the tight display line heights
/// come from the font itself; SwiftUI has no negative `lineSpacing`, so
/// anything that wants to be *looser* than 1.09 asks here.
enum CozyLeading {
    /// 1.24em at 34pt, up from the face's own 1.09.
    nonisolated static let cookStep: CGFloat = 5
}

private struct CozyScaledTracking: ViewModifier {
    @ScaledMetric private var tracking: CGFloat

    init(_ points: CGFloat, relativeTo style: Font.TextStyle) {
        _tracking = ScaledMetric(wrappedValue: points, relativeTo: style)
    }

    func body(content: Content) -> some View {
        content.tracking(tracking)
    }
}

private struct CozyScaledLeading: ViewModifier {
    @ScaledMetric private var leading: CGFloat

    init(_ points: CGFloat, relativeTo style: Font.TextStyle) {
        _leading = ScaledMetric(wrappedValue: points, relativeTo: style)
    }

    func body(content: Content) -> some View {
        content.lineSpacing(leading)
    }
}

extension View {
    /// Applies a font and the matching ink colour in one step.
    nonisolated func cozyText(_ font: Font, color: Color = CozyColor.inkPrimary) -> some View {
        self.font(font).foregroundStyle(color)
    }

    /// Tightens a run of display type, scaling the tracking with Dynamic Type.
    ///
    /// Pass a `CozyTracking` value, never a number: the em-to-point conversion
    /// belongs in one place, and a display title without its tracking is the
    /// most visible way to be almost right.
    func cozyDisplayTracking(_ points: CGFloat,
                             relativeTo style: Font.TextStyle = .largeTitle) -> some View {
        modifier(CozyScaledTracking(points, relativeTo: style))
    }

    /// Opens a run of display type out past the face's own 1.09em.
    func cozyDisplayLeading(_ points: CGFloat,
                            relativeTo style: Font.TextStyle = .title) -> some View {
        modifier(CozyScaledLeading(points, relativeTo: style))
    }

    /// The small tracked-out capitals above a screen title, or under one.
    ///
    /// The default ink is `inkTertiary`, which is right on cream and fails on
    /// blush — anything on a slab passes `CozyColor.inkOnBlush`.
    func cozyEyebrow(color: Color = CozyColor.inkTertiary,
                     tracking: CGFloat = CozyTracking.eyebrow) -> some View {
        self.font(CozyFont.eyebrow)
            .cozyDisplayTracking(tracking, relativeTo: .caption2)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
