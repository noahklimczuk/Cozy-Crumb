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
//  The dark half of the accent palette was re-cut when the accents stopped
//  being small pastel tints and became painted surfaces. Their old dark values
//  were pitched as *tints* — light enough to read as a wash behind a word —
//  and blush's was lighter still than the rest. Once a header slab, a tab bar
//  and two whole screens were painted in them, that produced glaring bands of
//  colour at night and, on the four non-blush accents, text that failed WCAG
//  AA against its own background. The dark values are now genuine dark
//  surfaces: `color` around 7:1 with the light ink, `deep` around 5:1, each a
//  clear step above the page. Light mode is untouched.
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
    nonisolated static let blush = Color(hex: "F8C8D4")
    nonisolated static let blushDeep = Color(hex: "EFA3B8")
    /// Still a pair, unlike `blush` and `blushDeep`. See `AccentPalette.soft`.
    nonisolated static let blushSoft = Color(light: Color(hex: "FDE8EE"), dark: Color(hex: "3E3033"))

    // Accents — rotated across chips, categories and collections
    nonisolated static let mint = Color(hex: "C5E6D4")
    nonisolated static let butter = Color(hex: "FBEEC1")
    nonisolated static let sky = Color(hex: "CFE3F2")
    nonisolated static let lavender = Color(hex: "DED4EE")
    nonisolated static let peach = Color(hex: "FFD9C4")
    nonisolated static let sage = Color(hex: "D9E4C8")

    /// The deep step of each accent, hoisted out of `AccentPalette` so the
    /// rotation can reach them too.
    ///
    /// A recipe with no photo is drawn as a two-stop gradient from its
    /// rotation colour to that colour's deep, and the rotation runs over six
    /// colours while the accent picker only offers five. Deriving the second
    /// stop by mixing toward the ink instead would work and look wrong: it
    /// desaturates, so every placeholder would fade toward the same brown.
    nonisolated static let mintDeep = Color(hex: "A3D3BB")
    nonisolated static let butterDeep = Color(hex: "F0DFA2")
    nonisolated static let skyDeep = Color(hex: "AECDE6")
    nonisolated static let lavenderDeep = Color(hex: "C7B9E0")
    nonisolated static let peachDeep = Color(hex: "F0B392")
    nonisolated static let sageDeep = Color(hex: "B9CDA2")

    nonisolated static let accentRotation: [Color] = [mint, butter, sky, lavender, peach, sage]
    nonisolated static let accentDeepRotation: [Color] = [
        mintDeep, butterDeep, skyDeep, lavenderDeep, peachDeep, sageDeep
    ]

    /// Deterministic accent for a name, so a given collection or category keeps
    /// the same colour across launches.
    ///
    /// Uses djb2 rather than `hashValue`: Swift seeds its hasher randomly per
    /// process, so `hashValue` would hand out a different colour on every
    /// launch. `&*` and `&+` wrap instead of trapping on overflow.
    nonisolated static func rotatedAccent(for key: String) -> Color {
        accentRotation[rotationIndex(for: key)]
    }

    /// The matching deep step, so the two stops of a placeholder gradient are
    /// always the same colour twice rather than two colours.
    nonisolated static func rotatedAccentDeep(for key: String) -> Color {
        accentDeepRotation[rotationIndex(for: key)]
    }

    nonisolated private static func rotationIndex(for key: String) -> Int {
        var hash: UInt64 = 5381
        for byte in key.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return Int(hash % UInt64(accentRotation.count))
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

    /// Ink for anything sitting on an accent-painted surface — the header
    /// slabs, the tab bar, Cook Mode, Sous Chef, a ticked `CheckRow`.
    ///
    /// This flips, and the first version of it didn't, which was the mistake.
    /// The reasoning then was that blush is a light surface in both
    /// appearances, so one dark ink served both. That was true of the palette
    /// as it stood — and the palette as it stood was wrong, because its dark
    /// blush was built to be a small pastel tint and the redesign turned it
    /// into a full-screen ground. See the note on the accent block below.
    ///
    /// With the dark accents re-cut as actual dark surfaces, the rule is the
    /// ordinary one: dark ink on the light versions, light ink on the dark
    /// ones. Measured on the worst surface of each kind:
    ///
    /// | Surface | Light | Dark |
    /// | --- | --- | --- |
    /// | `accent.color` | 9.37 (blush) | 7.15 (sky) |
    /// | `accent.deep` | 6.99 (blush) | 5.03 (sky) |
    ///
    /// The accents are the same pastels in both appearances now, so this is
    /// one dark ink rather than a pair. The contrast figures above are the
    /// light-mode ones, and they are now the only ones: dark mode changes the
    /// page under the slab, not the slab.
    ///
    /// Anything quieter on an accent — an unselected tab label — takes this at
    /// a lighter *weight*, never at reduced opacity. Opacity is what put the
    /// mockup's tab labels at 2.17:1.
    nonisolated static let inkOnAccent = Color(hex: "332B27")

    nonisolated static let outline = Color(light: Color(hex: "E4D5CB"), dark: Color(hex: "4A3E39"))
    nonisolated static let outlineStrong = Color(light: Color(hex: "C9B4A8"), dark: Color(hex: "63534B"))

    /// A surface floating on an accent one — a quick-add field on a header
    /// slab, a control in Cook Mode, a suggestion row on Sous Chef.
    ///
    /// Not `card`: on a painted ground a panel should read as a lift off that
    /// ground rather than a hole cut into it, so this is white pulled toward
    /// the surface it sits on. Translucent, so the tile grid still runs
    /// faintly underneath.
    ///
    /// One value in both appearances, because the accent under it is one
    /// value in both appearances.
    ///
    /// Nothing wearing this may carry a block — a block needs an opaque fill
    /// or its own offset shows through. See `cozyPaled`.
    nonisolated static let surfaceOnAccent = Color.white.opacity(0.80)

    /// The scrim under a recipe's title where it is set over the hero.
    ///
    /// This one is not a surface, it is a contrast guarantee: the hero can be
    /// any photograph the user imported. The ink over it is `inkOnAccent`,
    /// which no longer changes with the appearance, so neither does this.
    nonisolated static let heroScrim = Color.white.opacity(0.82)

    /// The grout in the tile grid where it runs over an accent ground.
    ///
    /// `outline` is tuned against cream, so over a painted ground it needs its
    /// own value: a dark hairline, since the accents are pastel in both
    /// appearances. Drawn at a low opacity by `TileBackground`.
    nonisolated static let tileOnAccent = Color(hex: "6B5A52")

    /// Which ground a control is standing on.
    ///
    /// Not a new palette — a pairing of the one that already exists. The app
    /// has two kinds of ground and they take opposite ink: the page goes dark
    /// after dark and carries `inkPrimary`, which goes light with it; a painted
    /// slab is the same pastel in both appearances and carries `inkOnAccent`,
    /// which never moves. Every contrast bug in this app so far has been a
    /// control that took its fill from one of those and its ink from the other.
    ///
    /// A control that can appear on both asks for a surface instead of a
    /// colour, and gets a matched set. The pairing stops being something each
    /// call site has to remember.
    nonisolated enum Surface: Sendable {
        /// A cream page or a white card.
        case page
        /// A header slab, the tab bar, or one of the accent-ground screens.
        case onAccent

        /// Fill for a field or an unselected control.
        nonisolated var field: Color {
            switch self {
            case .page: CozyColor.card
            case .onAccent: CozyColor.surfaceOnAccent
            }
        }

        /// Fill for a quieter well — an unselected segment.
        nonisolated var well: Color {
            switch self {
            case .page: CozyColor.creamDeep
            case .onAccent: Color.white.opacity(0.28)
            }
        }

        /// Opaque disc behind a badge — the mascot in the header, the cupcake
        /// in the tab bar.
        ///
        /// Opaque, unlike `field`: these hold artwork, and a translucent disc
        /// lets the slab tint the cupcake. `card` cannot do this job on a slab
        /// because it goes near-black after dark, which is how the tab bar's
        /// cupcake came to sit in a black hole on a pink bar.
        nonisolated var badge: Color {
            switch self {
            case .page: CozyColor.card
            case .onAccent: Color(hex: "FFFDFB")
            }
        }

        nonisolated var ink: Color {
            switch self {
            case .page: CozyColor.inkPrimary
            case .onAccent: CozyColor.inkOnAccent
            }
        }

        /// Placeholders, icons and other second-rank marks.
        ///
        /// On an accent surface this is `inkOnAccent` softened rather than
        /// `inkSecondary`, because `inkSecondary` goes light after dark and
        /// this surface does not.
        nonisolated var inkQuiet: Color {
            switch self {
            case .page: CozyColor.inkSecondary
            case .onAccent: CozyColor.inkOnAccent.opacity(0.62)
            }
        }
    }

    // Semantic — gentle, even when wrong
    //
    /// These stay pairs, for the same reason `AccentPalette.soft` does: they
    /// are status *surfaces*, not accent identities. Every one of them is used
    /// as a fill under `inkPrimary` — usually through `cozyPaled`, which mixes
    /// toward `cream` — and body ink goes light after dark. A banner that kept
    /// its pale yellow into dark mode would be light ink on a light wash.
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
        case .mint: CozyColor.mintDeep
        case .butter: CozyColor.butterDeep
        case .sky: CozyColor.skyDeep
        case .lavender: CozyColor.lavenderDeep
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
        case .blush: Color(hex: "D98BA1")
        case .mint: Color(hex: "8ABFA4")
        case .butter: Color(hex: "E0CB92")
        case .sky: Color(hex: "93B8D6")
        case .lavender: Color(hex: "AF9ECF")
        }
    }

    /// Tinted fill behind content.
    ///
    /// The one step of the palette that still flips with the appearance, and
    /// it flips because it is a background rather than a colour: `soft` is a
    /// wash a few percent off the page, and what sits on it is `inkPrimary`,
    /// which goes light after dark. `color`, `deep` and `block` are the same
    /// pastels in both appearances — they carry `inkOnAccent`, which doesn't
    /// move — but a near-white wash under light ink is a blank rectangle.
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
    /// is a painted blush slab with a selected item drawn in a 36pt block.
    ///
    /// This is the painted slab only. The bar is `tabBarContentGap` taller.
    nonisolated static let tabBarHeight: CGFloat = 92

    /// The clear strip above the painted slab, and the gap every scroll view
    /// in the app stops at.
    ///
    /// It was introduced to reserve room for the Sous Chef's cupcake standing
    /// out of the bar. The cupcake sits on the row now, and removing the strip
    /// with it put the last row of every list under the slab, along with the
    /// block that draws 4pt below each card. It stays, for the job it was
    /// quietly also doing.
    nonisolated static let tabBarContentGap: CGFloat = 16

    /// What every screen has to keep clear at the bottom: the slab plus its
    /// strip. See `cozyTabBarClearance()`, which is the only thing that should
    /// be reading this.
    nonisolated static let tabBarTotalHeight: CGFloat = tabBarHeight + tabBarContentGap

    /// A quiet header glyph — the ellipsis on Groceries. Smaller than
    /// `addButtonDiameter`, still a full touch target thanks to its frame.
    nonisolated static let headerGlyphDiameter: CGFloat = 40
}

// MARK: - Grids

enum CozyGrid {
    /// Recipe grids: two columns, or one when the text is big enough to need
    /// the whole width.
    ///
    /// This branched on the horizontal size class once, laying out adaptive
    /// columns when it was `.regular` — an iPad, or a Max in landscape. The
    /// app is iPhone-only and portrait-locked now, so the size class is
    /// `.compact` on every device it can run on and that branch could never be
    /// reached. It is text size that decides the count instead, which is the
    /// thing that actually varies.
    ///
    /// Two columns on the widest phone is about 200pt each. At AX5 that is
    /// narrower than the *word* "Sunday", so a title cannot break anywhere but
    /// mid-word: the capture reads "Sunda" over a card whose recipe is called
    /// Sunday Roast Chicken. Raising the line limit let it keep going instead
    /// of truncating, which fixed the clipping and not the reason for it.
    /// No line limit rescues a column narrower than one word.
    ///
    /// One column past AX1, therefore — around 360pt, which is enough for a
    /// title to break where English breaks. Fewer recipes on screen at a text
    /// size that was always going to show fewer of them.
    nonisolated static func recipeColumns(for typeSize: DynamicTypeSize) -> [GridItem] {
        guard typeSize.isAccessibilitySize else {
            return [
                GridItem(.flexible(), spacing: CozySpacing.m),
                GridItem(.flexible(), spacing: CozySpacing.m)
            ]
        }

        return [GridItem(.flexible(), spacing: CozySpacing.m)]
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
    /// `compositingGroup()` first, and it is not optional.
    ///
    /// `.shadow()` does not shadow the finished picture. It propagates down
    /// the subtree and shadows every drawing primitive in it separately, so a
    /// card wearing this drew a hard offset copy of its own fill *and* a hard
    /// offset copy of every glyph sitting on that fill — a 4pt drop shadow on
    /// the title of every recipe card, on "Start cooking", on the text in every
    /// pill. On a card with an opaque background that is not a subtle artefact:
    /// the glyph copies land on top of the fill, where nothing hides them.
    ///
    /// `compositingGroup()` flattens the subtree into one layer first, so the
    /// shadow is taken from the card's silhouette and the type on it stays flat.
    ///
    /// `color` defaults to the generic warm beige, which is what a white card
    /// wants. A control filled with a palette colour passes that palette's
    /// `block` instead, so its offset is a darker version of its own fill.
    func cozyBlockShadow(_ depth: CGFloat = CozyDepth.block,
                         color: Color = CozyColor.block) -> some View {
        compositingGroup()
            .shadow(color: color, radius: 0, x: 0, y: depth)
    }

    /// Soft, warm-tinted elevation. Kept for the handful of things that really
    /// do float above the page — toasts, popovers — rather than sit on it.
    ///
    /// Composited for the same reason as `cozyBlockShadow`: a blurred copy of
    /// the glyphs is harder to spot than a hard one, but it is the same bug and
    /// it is what makes text on a floating card look faintly smeared.
    func cozyCardShadow() -> some View {
        compositingGroup()
            .shadow(color: CozyColor.shadow, radius: 10, x: 0, y: 5)
    }

    /// Lighter blurred elevation, same caveat as `cozyCardShadow`.
    func cozyLiftShadow() -> some View {
        compositingGroup()
            .shadow(color: CozyColor.shadow, radius: 6, x: 0, y: 3)
    }
}
