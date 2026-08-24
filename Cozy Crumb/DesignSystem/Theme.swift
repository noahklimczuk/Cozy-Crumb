//
//  Theme.swift
//  Cozy Crumb
//
//  Colour, shape, spacing and elevation tokens. Every screen composes from
//  these — no raw hex or magic numbers in feature code.
//
//  Dark mode is warm (#2A2321 base), never gray-blue, and deliberately
//  low-contrast-soft rather than harsh.
//
//  Elevation is enamel, not paper: a hard block offset in a warm tone rather
//  than a blurred drop shadow. `cozyBlockShadow` is the default; the blurred
//  `cozyCardShadow` is kept for the few places that genuinely want a lift off
//  the page (a floating toast, a sheet) rather than a printed edge.
//
//  Everything here is marked `nonisolated`. The target sets
//  SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, which would otherwise isolate
//  these tokens to the main actor and make them unreachable from @Model types,
//  which are nonisolated. The design system is immutable Sendable data with no
//  UI state of its own, so isolating it buys nothing and costs a compile error
//  every time a model wants a colour. The View extensions at the bottom stay
//  isolated, because those genuinely are view code.
//

import SwiftUI

// MARK: - Colour

enum CozyColor {

    // Surfaces
    nonisolated static let cream = Color(light: Color(hex: "FFFBF7"), dark: Color(hex: "2A2321"))
    nonisolated static let card = Color(light: Color(hex: "FFFFFF"), dark: Color(hex: "362D2A"))
    nonisolated static let creamDeep = Color(light: Color(hex: "FDF3EA"), dark: Color(hex: "241E1C"))

    // Hero
    nonisolated static let blush = Color(light: Color(hex: "F8C8D4"), dark: Color(hex: "E0A6B6"))
    nonisolated static let blushDeep = Color(light: Color(hex: "EFA3B8"), dark: Color(hex: "C98599"))
    nonisolated static let blushSoft = Color(light: Color(hex: "FDE8EE"), dark: Color(hex: "3E3033"))

    // Accents — rotated across chips, categories and collections
    nonisolated static let mint = Color(light: Color(hex: "C5E6D4"), dark: Color(hex: "6E9682"))
    nonisolated static let butter = Color(light: Color(hex: "FBEEC1"), dark: Color(hex: "9A8C5F"))
    nonisolated static let sky = Color(light: Color(hex: "CFE3F2"), dark: Color(hex: "6C8598"))
    nonisolated static let lavender = Color(light: Color(hex: "DED4EE"), dark: Color(hex: "7E7295"))
    nonisolated static let peach = Color(light: Color(hex: "FFD9C4"), dark: Color(hex: "A3785F"))
    nonisolated static let sage = Color(light: Color(hex: "D9E4C8"), dark: Color(hex: "7E8C68"))

    nonisolated static let accentRotation: [Color] = [mint, butter, sky, lavender, peach, sage]

    /// Deterministic accent for a name, so a given collection or category keeps
    /// the same colour across launches.
    ///
    /// Uses djb2 rather than `hashValue`: Swift seeds its hasher randomly per
    /// process, so `hashValue` would hand out a different colour on every
    /// launch. `&*` and `&+` wrap instead of trapping on overflow.
    nonisolated static func rotatedAccent(for key: String) -> Color {
        var hash: UInt64 = 5381
        for byte in key.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return accentRotation[Int(hash % UInt64(accentRotation.count))]
    }

    // Ink — never pure black
    nonisolated static let inkPrimary = Color(light: Color(hex: "6B5A52"), dark: Color(hex: "F2E7E0"))

    /// Spec listed #9C8A80, which measures 3.21:1 on cream and fails WCAG AA.
    /// Darkened to #826F64 (4.63:1) per the §7.6 instruction to verify and fix.
    nonisolated static let inkSecondary = Color(light: Color(hex: "826F64"), dark: Color(hex: "C4B2A8"))

    /// The quietest ink: eyebrows, counts, "3 recipes" under a folder name.
    ///
    /// Measures 3.36:1 on cream and 4.78:1 on the dark base, so it clears AA
    /// for large text and for non-text UI, but not for body copy. Nothing that
    /// has to be read to use the app is allowed to wear it — if a string is
    /// load-bearing it takes `inkSecondary` instead.
    nonisolated static let inkTertiary = Color(light: Color(hex: "9A867A"), dark: Color(hex: "9C8C84"))

    /// Ink for anything sitting on a blush surface — the header slabs, the tab
    /// bar, Cook Mode, Sous Chef, a ticked `CheckRow`.
    ///
    /// One value rather than a light/dark pair, which looks like an oversight
    /// and isn't. Blush is a *light* surface in both appearances (#F8C8D4
    /// light, #E0A6B6 dark), so the usual pair would be wrong after dark:
    /// `inkPrimary` resolves to #F2E7E0 there and would be near-invisible on
    /// #E0A6B6. One dark ink is what both appearances actually need.
    ///
    /// The alternative was lightening blush until `inkSecondary` passed, but
    /// the solid blush slab is the design. Darkening the foreground is the
    /// cheaper half of the same fix — the same reasoning as `inkSecondary`
    /// above, one surface further in.
    ///
    /// The spec said #4A3E39, measured against blush. It does clear AA there
    /// (6.96:1 light, 5.05:1 dark) but the design also puts small text on
    /// *blushDeep* — Sous Chef's user bubbles at body size, the pantry's
    /// "TOMORROW" tag at 10pt — and #4A3E39 lands at 3.58:1 on #C98599, the
    /// dark blushDeep. That is a fail, so this goes one step darker:
    ///
    /// | Surface | Ratio |
    /// | --- | --- |
    /// | blush #F8C8D4 / #E0A6B6 | 9.37 / 6.80 |
    /// | blushDeep #EFA3B8 / #C98599 | 6.99 / **4.82** |
    /// | mint / butter / sky / lavender | 10.32 / 11.94 / 10.51 / 9.74 |
    ///
    /// The binding constraint is that 4.82, which is why the value looks
    /// darker than a light-mode eyedropper would suggest it needs to be.
    /// Every accent the picker offers clears AA for body text on both, so
    /// switching to mint or butter can't quietly break a screen.
    ///
    /// Anything quieter on blush — an unselected tab label — takes this at a
    /// lighter *weight*, never at reduced opacity. Opacity is what put the
    /// mockup's tab labels at 2.17:1.
    nonisolated static let inkOnBlush = Color(hex: "332B27")

    nonisolated static let outline = Color(light: Color(hex: "E4D5CB"), dark: Color(hex: "4A3E39"))
    nonisolated static let outlineStrong = Color(light: Color(hex: "C9B4A8"), dark: Color(hex: "63534B"))

    /// The grout in the tile grid where it runs over a blush ground.
    ///
    /// `outline` flips light in dark mode, which is right over cream and wrong
    /// over blush — blush stays a light surface after dark, so its grout stays
    /// a dark hairline. Drawn at a low opacity by `TileBackground`.
    nonisolated static let tileOnBlush = Color(hex: "6B5A52")

    // Semantic — gentle, even when wrong
    nonisolated static let success = Color(light: Color(hex: "A8D5B5"), dark: Color(hex: "6FA382"))
    nonisolated static let warning = Color(light: Color(hex: "F5D08A"), dark: Color(hex: "B39355"))
    nonisolated static let danger = Color(light: Color(hex: "E8A0A0"), dark: Color(hex: "B36F6F"))

    /// Warm-tinted blur shadow. Never gray or black in light mode.
    nonisolated static let shadow = Color(light: Color(hex: "D9C4B8").opacity(0.25),
                                          dark: Color.black.opacity(0.38))

    /// The hard offset behind a card. Opaque, because a block shadow is a
    /// printed edge rather than a cast one — translucency would let the
    /// surface underneath show through and the edge would stop reading.
    nonisolated static let block = Color(light: Color(hex: "E7D3C5"), dark: Color(hex: "1C1716"))
}

// MARK: - Mixing

extension Color {
    /// Pales a pastel toward the page colour without going translucent.
    ///
    /// This exists because of `cozyBlockShadow`. A block is drawn behind the
    /// view it belongs to, so a fill with any transparency lets its own offset
    /// show through and the card reads as smudged rather than stamped. Every
    /// `tint.opacity(0.55)` on a surface that carries a block is one of these
    /// instead.
    nonisolated func cozyPaled(_ amount: Double = 0.45) -> Color {
        mix(with: CozyColor.cream, by: amount)
    }
}

// MARK: - Accent picker

/// User-selectable app accent (§5.9). Held in the environment so components
/// re-tint without any of them reaching for UserDefaults directly.
enum AccentPalette: String, CaseIterable, Identifiable, Sendable {
    case blush, mint, butter, sky, lavender

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .blush: "Blush"
        case .mint: "Mint"
        case .butter: "Butter"
        case .sky: "Sky"
        case .lavender: "Lavender"
        }
    }

    /// Primary fill.
    nonisolated var color: Color {
        switch self {
        case .blush: CozyColor.blush
        case .mint: CozyColor.mint
        case .butter: CozyColor.butter
        case .sky: CozyColor.sky
        case .lavender: CozyColor.lavender
        }
    }

    /// Pressed / emphasis.
    nonisolated var deep: Color {
        switch self {
        case .blush: CozyColor.blushDeep
        case .mint: Color(light: Color(hex: "A3D3BB"), dark: Color(hex: "5B7F6D"))
        case .butter: Color(light: Color(hex: "F0DFA2"), dark: Color(hex: "84774E"))
        case .sky: Color(light: Color(hex: "AECDE6"), dark: Color(hex: "5A7183"))
        case .lavender: Color(light: Color(hex: "C7B9E0"), dark: Color(hex: "6A5F80"))
        }
    }

    /// The hard offset under a control filled with this palette.
    ///
    /// `CozyColor.block` is a generic warm beige, which is right under a white
    /// card and muddy under a coloured button — a blush button on a beige
    /// block reads as two unrelated things stacked up. A primary control's
    /// offset should be a darker version of its own fill, so this is one step
    /// past `deep`: #D98BA1 under blush, #E0CB92 under butter.
    nonisolated var block: Color {
        switch self {
        case .blush: Color(light: Color(hex: "D98BA1"), dark: Color(hex: "A66A7C"))
        case .mint: Color(light: Color(hex: "8ABFA4"), dark: Color(hex: "476357"))
        case .butter: Color(light: Color(hex: "E0CB92"), dark: Color(hex: "6B603E"))
        case .sky: Color(light: Color(hex: "93B8D6"), dark: Color(hex: "47596A"))
        case .lavender: Color(light: Color(hex: "AF9ECF"), dark: Color(hex: "544B66"))
        }
    }

    /// Tinted fill behind content.
    nonisolated var soft: Color {
        switch self {
        case .blush: CozyColor.blushSoft
        case .mint: Color(light: Color(hex: "E8F5EE"), dark: Color(hex: "2E3833"))
        case .butter: Color(light: Color(hex: "FDF8E4"), dark: Color(hex: "38352A"))
        case .sky: Color(light: Color(hex: "EAF3FA"), dark: Color(hex: "2A333A"))
        case .lavender: Color(light: Color(hex: "F1ECFA"), dark: Color(hex: "332F3C"))
        }
    }
}

extension EnvironmentValues {
    @Entry var accentPalette: AccentPalette = .blush
}

// MARK: - Shape

/// Flatter than the first pass. A 24pt radius on a 340pt card reads as a
/// pebble; the enamel look wants a corner you can still see the corner of.
///
/// One ladder, climbing with the size of the thing: the bigger the surface,
/// the rounder it is allowed to be. Picking a radius is picking a rung, not
/// typing a number.
enum CozyRadius {
    /// Metadata pills, aisle tags, urgency tags — the size of a word.
    nonisolated static let pill: CGFloat = 8

    /// Small controls that aren't capsules: the sort menu's label.
    nonisolated static let chip: CGFloat = 10

    /// Floating glyph squares, the servings stepper, a tab bar item.
    nonisolated static let control: CGFloat = 12

    /// Text fields, check rows, the smaller buttons.
    nonisolated static let field: CGFloat = 14

    /// Primary buttons, step cards.
    nonisolated static let button: CGFloat = 16

    /// Sheets, settings groups, the Cook Mode timer.
    nonisolated static let sheet: CGFloat = 18

    /// Recipe cards.
    nonisolated static let card: CGFloat = 20

    nonisolated static let image: CGFloat = 12

    /// The bottom corners of a `ScreenHeader`'s block.
    ///
    /// Zero, and kept as a token rather than deleted so the header still says
    /// what shape it is. The block is a painted slab that runs the full width
    /// of the screen and meets the content edge-to-edge; rounding its bottom
    /// corners turned it into a very wide card floating on the page, which is
    /// the look this redesign is getting away from.
    nonisolated static let header: CGFloat = 0
}

enum CozyBorder {
    nonisolated static let card: CGFloat = 1.5
    nonisolated static let illustrative: CGFloat = 2
}

// MARK: - Spacing

enum CozySpacing {
    nonisolated static let xs: CGFloat = 4
    nonisolated static let s: CGFloat = 8
    nonisolated static let m: CGFloat = 12
    nonisolated static let l: CGFloat = 16
    nonisolated static let xl: CGFloat = 24
    nonisolated static let xxl: CGFloat = 32
}

/// Minimum tappable area (§7.6). Cute little chips still need real hit boxes.
enum CozyMetrics {
    nonisolated static let minimumTouchTarget: CGFloat = 44

    /// The Cookbook's add button. Deliberately bigger than a toolbar glyph —
    /// it's the one control the whole app is built around.
    ///
    /// A 50pt rounded square now rather than a 56pt circle: it sits beside a
    /// 50pt search field in the header strip and the two read as one unit
    /// when they share a height and a corner.
    nonisolated static let headerActionSize: CGFloat = 50

    /// The cupcake beside a screen title. Much bigger than the control next to
    /// it, because it is the one thing on the header that is purely hello.
    nonisolated static let headerMascotDiameter: CGFloat = 88

    /// Pitch of the tile grid on the page behind every screen.
    nonisolated static let tilePitch: CGFloat = 56

    /// Artwork on a recipe card, in the Cookbook and on the meal plan alike —
    /// one number so the two can't drift apart.
    ///
    /// A card is for scanning: the picture is there to be recognised, not
    /// studied, and a shorter one puts more of the cookbook on screen at once.
    /// Seeing a photo properly is the recipe screen's job, and its hero is
    /// sized for exactly that.
    nonisolated static let cardHeroHeight: CGFloat = 118

    /// Where the artwork stops growing with the text size, so an accessibility
    /// size can't leave the title pushed off the bottom of the card.
    nonisolated static let cardHeroHeightCap: CGFloat = 190

    /// The photo at the top of a recipe. One number rather than a share of the
    /// screen: the hero now sits under a header block instead of running to
    /// the top edge, and a proportional height made that block float at some
    /// sizes and jam against the title at others.
    nonisolated static let recipeHeroHeight: CGFloat = 330

    /// Height of `MascotTabBar`'s own row, not counting the home-indicator
    /// inset it sits above.
    ///
    /// 92 rather than 58, because the bar is no longer a strip of glyphs: it
    /// is a painted blush slab with a selected item drawn in a 36pt block and
    /// the Sous Chef mascot raised out of the top of it. The mascot's overhang
    /// is `tabBarMascotLift` on top of this.
    nonisolated static let tabBarHeight: CGFloat = 92

    /// The Sous Chef mascot's diameter in the tab bar, and how far it stands
    /// proud of the bar's top edge.
    ///
    /// The lift is not decoration the content can be allowed to slide under —
    /// the safe-area inset the bar reserves is the sum of the two, so a
    /// scroll view stops above the cupcake rather than behind it.
    nonisolated static let tabBarMascotDiameter: CGFloat = 50
    nonisolated static let tabBarMascotLift: CGFloat = 16

    /// A quiet header glyph — the ellipsis on Groceries. Smaller than
    /// `addButtonDiameter`, still a full touch target thanks to its frame.
    nonisolated static let headerGlyphDiameter: CGFloat = 40
}

// MARK: - Grids

enum CozyGrid {
    /// Recipe grids: two columns on a phone, and as many comfortable columns as
    /// fit on an iPad or in landscape, rather than two very wide ones.
    nonisolated static func recipeColumns(for sizeClass: UserInterfaceSizeClass?) -> [GridItem] {
        guard sizeClass == .regular else {
            return [
                GridItem(.flexible(), spacing: CozySpacing.m),
                GridItem(.flexible(), spacing: CozySpacing.m)
            ]
        }

        return [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: CozySpacing.m)]
    }
}

// MARK: - Elevation

/// How far a block sits off the page. Only three depths, so the app can't
/// invent a fourth by eye.
enum CozyDepth {
    /// Chips, small glyph buttons, anything the size of a word.
    nonisolated static let small: CGFloat = 3

    /// The default. Cards, rows, buttons.
    nonisolated static let block: CGFloat = 4

    /// Screen chrome — the header block and the tab bar.
    nonisolated static let deep: CGFloat = 6
}

extension View {
    /// The app's elevation: a hard offset in `CozyColor.block`, no blur.
    ///
    /// Offset straight down rather than diagonally, so it reads the same in a
    /// right-to-left layout.
    ///
    /// SwiftUI shadows the composited view, so this belongs on something with
    /// an opaque fill — on a bare `Text` it would draw a solid coloured copy
    /// of the glyphs 4pt below them.
    ///
    /// `color` defaults to the generic warm beige, which is what a white card
    /// wants. A control filled with a palette colour passes that palette's
    /// `block` instead, so its offset is a darker version of its own fill.
    func cozyBlockShadow(_ depth: CGFloat = CozyDepth.block,
                         color: Color = CozyColor.block) -> some View {
        shadow(color: color, radius: 0, x: 0, y: depth)
    }

    /// Soft, warm-tinted elevation. Kept for the handful of things that really
    /// do float above the page — toasts, popovers — rather than sit on it.
    func cozyCardShadow() -> some View {
        shadow(color: CozyColor.shadow, radius: 10, x: 0, y: 5)
    }

    /// Lighter blurred elevation, same caveat as `cozyCardShadow`.
    func cozyLiftShadow() -> some View {
        shadow(color: CozyColor.shadow, radius: 6, x: 0, y: 3)
    }
}
