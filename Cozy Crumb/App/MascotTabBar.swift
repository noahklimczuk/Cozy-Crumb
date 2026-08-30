//
//  MascotTabBar.swift
//  Cozy Crumb
//
//  The app's own tab bar, replacing the system one.
//
//  Replacing system chrome is not free and it needs a reason. The reason is
//  that the system bar is the one surface in the app that cannot be told to
//  look like the rest of it: it is translucent where everything else is solid,
//  it blurs where everything else has a hard edge, and it puts a hairline
//  above itself where every other edge in the app is a block. Five screens
//  built out of stamped cards sat under a pane of frosted glass.
//
//  What is *not* replaced is the `TabView` behind it. This bar only moves a
//  selection; SwiftUI still owns the five children, so each tab keeps its own
//  `NavigationStack` and coming back to a tab lands where you left it. A
//  hand-rolled switch over five views would throw that away, and losing your
//  place halfway through a recipe because you checked the shopping list is a
//  far worse bug than a blurred bar.
//
//  The mascot rides in it: the Sous Chef is the cupcake's tab, so it wears the
//  cupcake instead of an SF Symbol. Drawn from the static asset rather than
//  `MascotView`, because a tab bar is on screen the entire time the app is and
//  it has no business running a blink loop.
//
//  The bar is now a painted blush slab rather than a white strip — the same
//  slab as the header at the other end of the screen, so the app is held
//  between two of them.
//
//  It draws as an overlay and reserves no space of its own. What keeps content
//  off it is `cozyTabBarClearance()`, applied to each tab's root in
//  `RootTabView` — see the note there for why the bar does not do that job
//  itself. The number is `CozyMetrics.tabBarTotalHeight`, and this bar has to
//  be exactly that tall: slab plus strip.
//

import SwiftUI

/// The window's own bottom safe area — the home indicator, and nothing else.
///
/// Published by `RootTabView` from outside the `TabView`, because inside a tab
/// that number is no longer available: see `TabBarClearance`.
private struct CozyWindowBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var cozyWindowBottomInset: CGFloat {
        get { self[CozyWindowBottomInsetKey.self] }
        set { self[CozyWindowBottomInsetKey.self] = newValue }
    }
}

extension View {
    /// Keeps the bottom of a screen clear of `MascotTabBar`, and no clearer.
    ///
    /// `safeAreaPadding` rather than plain `padding`, because this has to be
    /// safe *area*: a scroll view should still draw through the strip while
    /// scrolling and simply come to rest above it, and a bottom bar of the
    /// screen's own — the Sous Chef's composer, the grocery export bar —
    /// should land on top of the strip rather than under the slab. Plain
    /// padding would inset the frame instead and leave a dead band the page
    /// colour does not reach.
    func cozyTabBarClearance() -> some View {
        modifier(TabBarClearance())
    }
}

/// Makes a tab's bottom inset equal what the bar actually occupies, rather
/// than adding the bar's height to whatever was already there.
///
/// `.toolbar(.hidden, for: .tabBar)` hides the system tab bar but does *not*
/// stop it reserving space: measured inside a tab, the bottom safe area is 83
/// on a phone whose home indicator is 34. The missing 49 is a tab bar that is
/// never drawn. Adding another 108 on top reserved 191 for a bar occupying
/// 142, so every scroll view in the app stopped 49pt short — which is exactly
/// how it was reported: content ending early, with a gap, on every screen.
///
/// The bar is an overlay on the `TabView`, aligned to the window's safe area,
/// so its top edge sits `tabBarTotalHeight` above the home indicator. Content
/// has to stop in the same place, which means a bottom inset of exactly
/// `windowBottom + tabBarTotalHeight`.
///
/// So the tab's own bottom inset is dropped outright and that number set in
/// its place. Setting rather than adding is the whole point: an earlier
/// version of this measured the inset and added the difference, which put the
/// measurement downstream of its own output — `safeAreaPadding` does not
/// resize the view, so the reading never showed the padding's effect, and what
/// it did show was the padding itself. It reported `system 108` where the
/// system gives 83, and 108 was simply the number that pass had just applied.
/// A control loop reading its own output is worse than no measurement, because
/// it looks like one.
///
/// `windowBottom` is measured, but outside the `TabView` where it is only ever
/// the home indicator, and it never feeds back into anything here.
private struct TabBarClearance: ViewModifier {
    @Environment(\.cozyWindowBottomInset) private var windowBottom

    func body(content: Content) -> some View {
        content
            // Drop what the tab was given — home indicator *and* the tab bar
            // that is not drawn — so the next line is the only thing deciding
            // where content stops.
            .ignoresSafeArea(.container, edges: .bottom)
            .safeAreaPadding(.bottom, windowBottom + CozyMetrics.tabBarTotalHeight)
            .modifier(TabClearanceProbe())
    }
}

/// Draws a line exactly where content is allowed to end, under
/// `-cozyLayoutRuler YES`.
///
/// `safeAreaInset` rather than an overlay or a `GeometryReader`, after three
/// probes that each measured the wrong thing. An overlay aligns to the view's
/// outer bounds, so the first one rendered underneath the tab bar — an
/// instrument for measuring the bottom of the screen, hidden by the thing at
/// the bottom of the screen. A `GeometryReader` on the view reports the view's
/// frame, which `safeAreaPadding` does not change, so the second and third
/// read 811 either way.
///
/// `safeAreaInset` places its content against the inside edge of the safe area
/// as it stands, which is the one thing actually being asked about. The line
/// should land flush on the top of the pink slab; any daylight between them is
/// the bug, still there, in pixels.
private struct TabClearanceProbe: ViewModifier {
    func body(content: Content) -> some View {
        if LaunchOptions.showsLayoutRuler {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                Rectangle()
                    .fill(.red)
                    .frame(height: 6)
            }
        } else {
            content
        }
    }
}

struct MascotTabBar: View {
    @Environment(\.accentPalette) private var accent
    @Environment(\.cozyMotion) private var motion

    @Binding var selection: CozyTab

    var body: some View {

        // Bottom-aligned, so the five labels share a line.
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(CozyTab.allCases) { tab in
                item(for: tab)
            }
        }
        .padding(.horizontal, CozySpacing.xs)
        .padding(.bottom, CozySpacing.m)
        .frame(maxWidth: .infinity, minHeight: CozyMetrics.tabBarHeight)
        // A clear strip on top of the painted slab, so what content stops at is
        // the strip and not the pink. `cozyTabBarClearance` reserves the two
        // together, which is why this padding and that number have to agree:
        // slab plus strip is `tabBarTotalHeight`, and the bar is drawn exactly
        // that tall. Change one and change the other.
        .padding(.top, CozyMetrics.tabBarContentGap)
        .background {
            // Solid accent, square across the top, no block. Squaring it off
            // is what makes it a painted bar rather than a card stuck to the
            // bottom of the screen; padding the fill down by the same strip
            // keeps the slab at tabBarHeight while the bar itself is taller.
            accent.color
                .padding(.top, CozyMetrics.tabBarContentGap)
                .ignoresSafeArea(edges: .bottom)
        }
        // Five labels across the narrowest phone cannot also grow to AX5:
        // past about AX1 they truncate however hard `minimumScaleFactor`
        // works, and a bar of "Sou…" and "Grocer…" helps nobody. VoiceOver
        // still reads each label in full, and every screen the bar leads to
        // scales all the way up.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }

    private func item(for tab: CozyTab) -> some View {
        let isSelected = tab == selection

        return Button {
            // No haptic here: `.squishy` already fires one on press, and two
            // taps for one tap reads as a stutter rather than a confirmation.
            guard tab != selection else { return }
            withAnimation(motion(Motion.snappy)) { selection = tab }
        } label: {
            VStack(spacing: 5) {
                icon(for: tab, isSelected: isSelected)

                Text(tab.title)
                    // Weight, never opacity. A quieter label on a blush bar is
                    // a lighter cut of the same ink: dropping the opacity
                    // instead is what put the mockup's unselected labels at
                    // 2.17:1, and #A08C81 was that colour baked in.
                    .font(CozyFont.caption2.weight(isSelected ? .bold : .medium))
                    .lineLimit(1)
                    // Takes up the last of the slack inside the cap above.
                    .minimumScaleFactor(0.85)
                    // A gutter each side, so neighbours cannot touch.
                    //
                    // The AX5 capture read "Cookbo…Groceries Sous Ch…" — three
                    // labels with no space between them, which is less legible
                    // than a shorter label would have been. `minimumScaleFactor`
                    // shrinks the glyphs but nothing was reserving the gap, so
                    // the columns grew until they met.
                    .padding(.horizontal, 2)
            }
            .foregroundStyle(CozyColor.inkOnAccent)
            .frame(maxWidth: .infinity)
            .frame(minHeight: CozyMetrics.minimumTouchTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.squishy)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private func icon(for tab: CozyTab, isSelected: Bool) -> some View {
        if tab == .sousChef {
            mascot(isSelected: isSelected)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: CozyRadius.control, style: .continuous)
                    .fill(accent.deep)
                    .opacity(isSelected ? 1 : 0)

                Image(systemName: tab.symbol)
                    .font(.system(size: 21, weight: .semibold))
            }
            .frame(width: 52, height: 36)
        }
    }

    /// The Sous Chef's cupcake, in the same slot as the other four icons.
    ///
    /// It used to be bigger than its neighbours and lifted clear of the slab,
    /// which put one column out of line with the other four and made the bar
    /// read as four tabs plus a button. It sits on the row now.
    ///
    /// Its selected state is the ring thickening and the label going bold,
    /// where the other four get a filled block. That is a quieter difference
    /// than theirs — it is what the design asks for, and VoiceOver is told
    /// properly either way by the `.isSelected` trait on the button.
    ///
    /// Still drawn from the static asset rather than `MascotView` — the bar is
    /// on screen the entire time the app is, and it has no business running a
    /// blink loop.
    private func mascot(isSelected: Bool) -> some View {
        Image("CupcakeMascot")
            .resizable()
            .scaledToFit()
            .padding(5)
            // The same 52x36 slot the four blocks occupy, so every icon in the
            // bar shares one baseline.
            .frame(width: 34, height: 34)
            // The bar is a painted slab, so the disc is the slab's badge.
            // `card` here drew a black circle round the cupcake at night.
            .background(CozyColor.Surface.onAccent.badge, in: .circle)
            .overlay {
                Circle().strokeBorder(accent.deep, lineWidth: isSelected ? 3 : 2)
            }
            .frame(width: 52, height: 36)
    }
}

// MARK: - Previews

#Preview("Tab bar") {
    @Previewable @State var selection: CozyTab = .library

    VStack {
        Spacer()
        Text(selection.title)
            .cozyText(CozyFont.display)
        Spacer()
        MascotTabBar(selection: $selection)
    }
    .cozyScreenBackground()
}

#Preview("Tab bar — dark, AX3") {
    @Previewable @State var selection: CozyTab = .sousChef

    VStack {
        Spacer()
        MascotTabBar(selection: $selection)
    }
    .cozyScreenBackground()
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
}
