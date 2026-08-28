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
//  One call-site rule: a header with only *one* of the two slots filled must
//  name it — `ScreenHeader(title: …, trailing: { … })`. Both slots are
//  closures, so a bare trailing closure matches the `trailing`-only and the
//  `below`-only initialiser equally and the call is ambiguous. Filling both is
//  fine unlabelled, because only one initialiser takes two.
//

import SwiftUI

struct ScreenHeader<Trailing: View, Below: View>: View {
    @Environment(\.accentPalette) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize

    let title: String
    /// The small tracked line above the title. Usually the app's name on a
    /// tab root, so the screen says where it is without a navigation bar.
    var eyebrow: String?
    /// A live summary under the title — "6 to buy · 2 in the basket". Written
    /// by the screen, because only the screen knows the count.
    var caption: String?

    /// Set by `heroTitle(spokenAs:)`. See the note there.
    fileprivate var titleFont: Font = CozyFont.display
    fileprivate var titleTracking: CGFloat = CozyTracking.display
    fileprivate var spokenTitle: String?

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
            // Solid accent, not a tint of it, and square at the bottom: this
            // is a painted slab that meets the page, not a card lying on it.
            //
            // No block either. An offset under a full-bleed slab is a beige
            // line ruled across the screen, which is a seam rather than an
            // edge — the colour change is all the separation it needs.
            UnevenRoundedRectangle(
                bottomLeadingRadius: CozyRadius.header,
                bottomTrailingRadius: CozyRadius.header,
                style: .continuous
            )
            .fill(accent.color)
            .ignoresSafeArea(edges: .top)
        }
        // The block is chrome, not content: it must not be squeezed by a
        // scroll view that wants the room.
        .fixedSize(horizontal: false, vertical: true)
        .zIndex(1)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: CozySpacing.s) {
            // The eyebrow says the app's name, which nobody needs and which
            // at an accessibility size costs a line of a block that is already
            // carrying a title, a caption and a strip on a phone-sized screen.
            if let eyebrow, !typeSize.isAccessibilitySize {
                Text(eyebrow)
                    .cozyEyebrow(color: CozyColor.inkOnAccent, tracking: CozyTracking.eyebrowWide)
            }

            Text(title)
                .cozyText(titleFont, color: CozyColor.inkOnAccent)
                .cozyDisplayTracking(titleTracking)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                // A title broken onto two lines with a hard newline reads as
                // "Cook, book" otherwise.
                .accessibilityLabel(spokenTitle ?? title)

            // Sentence-case caption no longer: on a slab this is a tracked
            // label under a big title, the same weight of thing as the eyebrow
            // above it.
            if let caption {
                Text(caption)
                    .cozyEyebrow(color: CozyColor.inkOnAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - The Cookbook's title

extension ScreenHeader {
    /// Sets the title larger than every other screen's and lets it break onto
    /// two lines — "Cook / book".
    ///
    /// A method rather than another initialiser parameter because there are
    /// already four initialisers here, covering which of the two slots are
    /// filled, and threading two more arguments through all of them to serve
    /// one screen is how a component starts collapsing under its own options.
    ///
    /// `spoken` is what VoiceOver reads, since the title itself carries a hard
    /// line break that would otherwise be announced as a pause.
    func heroTitle(spokenAs spoken: String) -> ScreenHeader {
        var copy = self
        copy.titleFont = CozyFont.displayHero
        copy.titleTracking = CozyTracking.displayHero
        copy.spokenTitle = spoken
        return copy
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

/// The loud one. There is at most one per screen.
///
/// A rounded square in the accent's *deep* step rather than a circle in its
/// flat one: it sits on a slab already painted `accent.color`, so a circle in
/// the same colour would have been invisible, and squaring it off lets it
/// line up with the search field beside it.
struct HeaderActionButton: View {
    @Environment(\.accentPalette) private var accent

    let systemImage: String
    let accessibilityLabel: String
    var accessibilityHint: String = ""
    /// Overrides the fill. The Pantry's camera is butter, because it opens a
    /// different kind of thing than a plus does.
    var fill: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(CozyColor.inkOnAccent)
                .frame(width: CozyMetrics.headerActionSize,
                       height: CozyMetrics.headerActionSize)
                .background(fill ?? accent.deep,
                            in: .rect(cornerRadius: CozyRadius.field, style: .continuous))
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
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(CozyColor.inkOnAccent)
            .frame(width: CozyMetrics.headerGlyphDiameter,
                   height: CozyMetrics.headerGlyphDiameter)
            // A bare glyph now. The white disc and its hairline were there to
            // separate the control from a pale tinted header; against a solid
            // slab they made a quiet action look like a second primary one.
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
    var diameter: CGFloat = CozyMetrics.headerMascotDiameter
    /// Thick enough to read as a drawn ring rather than a stroke. It has to
    /// hold its own against an 88pt cupcake and a 52pt title.
    var ring: CGFloat = 5

    var body: some View {
        MascotView(pose: pose, size: diameter * 0.75)
            .frame(width: diameter, height: diameter)
            // The slab's badge disc, not the page's card. `card` goes
            // near-black after dark, which put the mascot in a hole.
            .background(CozyColor.Surface.onAccent.badge, in: .circle)
            .overlay { Circle().strokeBorder(accent.deep, lineWidth: ring) }
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
                CozyTextField(placeholder: "Search recipes", text: $search,
                              systemImage: "magnifyingglass", surface: .onAccent)
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
