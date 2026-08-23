//
//  ScreenHeader.swift
//  Cozy Crumb
//
//  The tinted block at the top of every tab. It replaces `.navigationTitle`,
//  which is why each screen that adopts it also hides its navigation bar.
//
//  A system large title is a title and nothing else: anything that belongs
//  beside it goes in a toolbar, where it is clipped to the bar's height, and
//  anything that belongs under it goes into the scroll view, where it scrolls
//  away. Both of those were already being worked around — the Cookbook's add
//  button sat next to a search field in a hand-rolled bar precisely because a
//  toolbar would have shrunk it.
//
//  So the header owns all three: a title, one control beside it, and a strip
//  underneath (a search field, a quick-add, a segmented switch). The strip is
//  *inside* the tinted block. Filter chips are not — they belong to the
//  content, they change what the list shows, and they go below the block on
//  the page where the list is.
//
//  The block bleeds under the status bar by ignoring the top safe area on its
//  fill only, so the text stays where the safe area put it.
//

import SwiftUI

struct ScreenHeader<Trailing: View, Below: View>: View {
    @Environment(\.accentPalette) private var accent

    let title: String
    /// The small tracked line above the title. Usually the app's name on a
    /// tab root, so the screen says where it is without a navigation bar.
    var eyebrow: String?
    /// A live summary under the title — "6 to buy · 2 in the basket". Written
    /// by the screen, because only the screen knows the count.
    var caption: String?

    let trailing: Trailing
    let below: Below

    init(
        title: String,
        eyebrow: String? = nil,
        caption: String? = nil,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder below: () -> Below
    ) {
        self.title = title
        self.eyebrow = eyebrow
        self.caption = caption
        self.trailing = trailing()
        self.below = below()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CozySpacing.m) {
            HStack(alignment: .center, spacing: CozySpacing.m) {
                titleBlock
                Spacer(minLength: CozySpacing.s)
                trailing
            }

            below
        }
        .padding(.horizontal, CozySpacing.l)
        .padding(.top, CozySpacing.s)
        .padding(.bottom, CozySpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(
                bottomLeadingRadius: CozyRadius.header,
                bottomTrailingRadius: CozyRadius.header,
                style: .continuous
            )
            .fill(accent.soft)
            .cozyBlockShadow(CozyDepth.deep)
            .ignoresSafeArea(edges: .top)
        }
        // The block is chrome, not content: it must not be squeezed by a
        // scroll view that wants the room.
        .fixedSize(horizontal: false, vertical: true)
        .zIndex(1)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let eyebrow {
                Text(eyebrow)
                    .cozyEyebrow()
            }

            Text(title)
                .cozyText(CozyFont.display)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if let caption {
                Text(caption)
                    .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Slots left empty

extension ScreenHeader where Trailing == EmptyView {
    init(
        title: String,
        eyebrow: String? = nil,
        caption: String? = nil,
        @ViewBuilder below: () -> Below
    ) {
        self.init(title: title, eyebrow: eyebrow, caption: caption, trailing: { EmptyView() }, below: below)
    }
}

extension ScreenHeader where Below == EmptyView {
    init(
        title: String,
        eyebrow: String? = nil,
        caption: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(title: title, eyebrow: eyebrow, caption: caption, trailing: trailing, below: { EmptyView() })
    }
}

extension ScreenHeader where Trailing == EmptyView, Below == EmptyView {
    init(title: String, eyebrow: String? = nil, caption: String? = nil) {
        self.init(
            title: title,
            eyebrow: eyebrow,
            caption: caption,
            trailing: { EmptyView() },
            below: { EmptyView() }
        )
    }
}

// MARK: - Controls that live in a header

/// The loud one. Filled with the accent, the size of the Cookbook's add
/// button, and there is at most one per screen.
struct HeaderActionButton: View {
    @Environment(\.accentPalette) private var accent

    let systemImage: String
    let accessibilityLabel: String
    var accessibilityHint: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(CozyColor.inkPrimary)
                .frame(width: CozyMetrics.addButtonDiameter,
                       height: CozyMetrics.addButtonDiameter)
                .background(accent.color, in: .circle)
                .cozyBlockShadow()
        }
        .buttonStyle(.squishy)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}

/// The quiet one's face, without a button around it.
///
/// Split out because half the header glyphs in the app are menus rather than
/// buttons, and a `Menu` needs to supply its own label. `Menu { … } label: {
/// HeaderGlyphLabel(systemImage: "ellipsis") }` and `HeaderGlyphButton` then
/// look identical, which is the point.
struct HeaderGlyphLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(CozyColor.inkPrimary)
            .frame(width: CozyMetrics.headerGlyphDiameter,
                   height: CozyMetrics.headerGlyphDiameter)
            .background(CozyColor.card, in: .circle)
            .overlay { Circle().strokeBorder(CozyColor.outline, lineWidth: 1) }
            .cozyBlockShadow(CozyDepth.small)
            // Draws at 40pt, stays tappable at 44 (§7.6).
            .frame(width: CozyMetrics.minimumTouchTarget,
                   height: CozyMetrics.minimumTouchTarget)
            .contentShape(.rect)
    }
}

/// The quiet one. Card-coloured, smaller, for anything that isn't the
/// screen's main action.
struct HeaderGlyphButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var accessibilityHint: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HeaderGlyphLabel(systemImage: systemImage)
        }
        .buttonStyle(.squishy)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}

/// The cupcake, ringed in the accent. Decoration, not a control — it is the
/// Cookbook's way of saying hello, and it is hidden from VoiceOver.
struct HeaderMascotBadge: View {
    @Environment(\.accentPalette) private var accent

    var pose: MascotView.Pose = .idle
    var diameter: CGFloat = CozyMetrics.addButtonDiameter

    var body: some View {
        MascotView(pose: pose, size: diameter * 0.78)
            .frame(width: diameter, height: diameter)
            .background(CozyColor.card, in: .circle)
            .overlay { Circle().strokeBorder(accent.deep, lineWidth: CozyBorder.illustrative) }
            .cozyBlockShadow(CozyDepth.small)
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Headers") {
    @Previewable @State var search = ""

    VStack(spacing: 0) {
        ScreenHeader(title: "Cookbook", eyebrow: AppBranding.appName) {
            HeaderMascotBadge()
        } below: {
            HStack(spacing: CozySpacing.m) {
                CozyTextField(placeholder: "Search recipes", text: $search, systemImage: "magnifyingglass")
                HeaderActionButton(systemImage: "plus", accessibilityLabel: "Add a recipe") {}
            }
        }

        ScrollView {
            VStack(spacing: CozySpacing.l) {
                ScreenHeader(
                    title: "Groceries",
                    eyebrow: AppBranding.appName,
                    caption: "6 to buy · 2 in the basket",
                    trailing: { HeaderGlyphButton(systemImage: "ellipsis", accessibilityLabel: "List options") {} }
                )

                ScreenHeader(title: "Settings", eyebrow: AppBranding.appName)
            }
            .padding(.vertical, CozySpacing.l)
        }
    }
    .cozyScreenBackground()
}

#Preview("Headers — dark") {
    ScreenHeader(
        title: "Pantry",
        eyebrow: AppBranding.appName,
        caption: "12 in · 2 going off",
        trailing: { HeaderActionButton(systemImage: "camera", accessibilityLabel: "Photograph the fridge") {} }
    )
    .frame(maxHeight: .infinity, alignment: .top)
    .cozyScreenBackground()
    .preferredColorScheme(.dark)
}
