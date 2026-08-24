//
//  TileBackground.swift
//  Cozy Crumb
//
//  The page every screen sits on: warm cream, ruled into a soft brick bond
//  like the tiles behind a cooker.
//
//  It replaces the drifting pastel blobs. Blobs were the right idea and the
//  wrong shape — they were the only thing on screen that moved when nobody had
//  asked for movement, they pushed a blur through the compositor on every
//  frame of every screen, and their soft edges gave the hard-edged cards
//  nothing to sit against. Tiles do the same job (the page is never a flat
//  white sheet) while holding still.
//
//  Drawn as one `Shape` rather than a stack of rectangles: the whole pattern
//  is a single stroked path, so a screenful costs one draw call instead of a
//  hundred views.
//

import SwiftUI

struct TileBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// What the page is painted. Cream on most screens; the accent on the two
    /// that are a single coloured ground (Cook Mode, Sous Chef).
    var ground: Color = CozyColor.cream

    /// The grout. `outline` flips light in dark mode, which is what a cream
    /// page wants and the opposite of what a blush one does — see
    /// `CozyColor.tileOnBlush`.
    var line: Color = CozyColor.outline

    /// Tile width. Height is half of it, which is the proportion a subway
    /// tile actually has.
    var tile: CGFloat = CozyMetrics.tilePitch

    /// How present the grout is. Low by design — this is a page, not a
    /// feature, and text has to win.
    var intensity: Double = 0.55

    var body: some View {
        ZStack {
            ground

            // Reduce Transparency asks for plain, legible surfaces. A ruled
            // page is exactly the sort of decoration it means.
            if !reduceTransparency {
                TileGrid(tile: tile)
                    .stroke(line, lineWidth: 1)
                    .opacity(intensity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - The pattern

/// A brick bond: every other course is shifted half a tile, so the vertical
/// joints stagger instead of lining up into columns.
private struct TileGrid: Shape {
    let tile: CGFloat

    private var courseHeight: CGFloat { tile / 2 }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard tile > 1, rect.width > 0, rect.height > 0 else { return path }

        let courses = Int((rect.height / courseHeight).rounded(.up)) + 1

        for course in 0..<courses {
            let top = CGFloat(course) * courseHeight

            // The horizontal joint under this course.
            path.move(to: CGPoint(x: rect.minX, y: top))
            path.addLine(to: CGPoint(x: rect.maxX, y: top))

            // Vertical joints, offset half a tile on alternate courses.
            let offset = course.isMultiple(of: 2) ? 0 : -tile / 2
            var x = rect.minX + offset
            while x < rect.maxX + tile {
                if x > rect.minX {
                    path.move(to: CGPoint(x: x, y: top))
                    path.addLine(to: CGPoint(x: x, y: min(top + courseHeight, rect.maxY)))
                }
                x += tile
            }
        }

        return path
    }
}

// MARK: - Screen background

/// The page for a screen that is one painted ground rather than cream — Cook
/// Mode and Sous Chef. Reads the accent itself so call sites don't have to
/// thread it through.
///
/// The grout goes dark here in both appearances, because the ground is a light
/// surface in both: blush resolves to #E0A6B6 after dark, not to something
/// dim. Same reasoning as `CozyColor.inkOnBlush`, one layer down.
struct AccentTileBackground: View {
    @Environment(\.accentPalette) private var accent

    var body: some View {
        TileBackground(ground: accent.color, line: CozyColor.tileOnBlush, intensity: 0.11)
    }
}

extension View {
    /// Puts the tiled page behind a screen. Every top-level screen wears this.
    func cozyScreenBackground() -> some View {
        background { TileBackground() }
    }

    /// The same page, painted in the accent.
    func cozyAccentScreenBackground() -> some View {
        background { AccentTileBackground() }
    }
}

#Preview("Tiled page") {
    ZStack {
        TileBackground()
        VStack(spacing: CozySpacing.l) {
            MascotView(pose: .idle, size: 100)
            Text("Cozy Crumb")
                .cozyText(CozyFont.display)
            Text(AppBranding.tagline)
                .cozyText(CozyFont.subheadline, color: CozyColor.inkSecondary)
            CrumbCard {
                Text("A card, so the page has something to hold.")
                    .cozyText(CozyFont.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, CozySpacing.l)
        }
    }
}

#Preview("Tiled page — dark") {
    ZStack {
        TileBackground()
        CrumbCard {
            Text("A card, so the page has something to hold.")
                .cozyText(CozyFont.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, CozySpacing.l)
    }
    .preferredColorScheme(.dark)
}
