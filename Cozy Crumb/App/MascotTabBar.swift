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
//  between two of them. It is also much taller, because the cupcake stands out
//  of the top of it. That overhang is reserved as padding on the bar itself,
//  which means the safe-area inset handed back to each tab already accounts
//  for it and no scroll view ever runs underneath the mascot.
//

import SwiftUI

struct MascotTabBar: View {
    @Environment(\.accentPalette) private var accent
    @Environment(\.cozyMotion) private var motion

    @Binding var selection: CozyTab

    var body: some View {
        // Bottom-aligned, so the five labels share a line before the Sous Chef
        // column is lifted off it. Centring them instead would stagger every
        // label against its neighbour, because the cupcake's column is taller
        // than the four beside it.
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(CozyTab.allCases) { tab in
                item(for: tab)
            }
        }
        .padding(.horizontal, CozySpacing.xs)
        .padding(.bottom, CozySpacing.m)
        .frame(maxWidth: .infinity, minHeight: CozyMetrics.tabBarHeight)
        // The strip the cupcake stands up into. It is padding on the bar
        // rather than an overhang drawn outside it, so the safe-area inset the
        // bar hands back grows by exactly the amount the mascot rises — a
        // scroll view stops above the cupcake instead of behind it.
        .padding(.top, CozyMetrics.tabBarMascotLift)
        .background {
            // Solid accent, square across the top, no block. Squaring it off
            // is what makes it a painted bar rather than a card stuck to the
            // bottom of the screen; padding the fill down by the same strip
            // keeps the slab at tabBarHeight while the bar itself is taller.
            accent.color
                .padding(.top, CozyMetrics.tabBarMascotLift)
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
        let isRaised = tab == .sousChef

        return Button {
            // No haptic here: `.squishy` already fires one on press, and two
            // taps for one tap reads as a stutter rather than a confirmation.
            guard tab != selection else { return }
            withAnimation(motion(Motion.snappy)) { selection = tab }
        } label: {
            VStack(spacing: isRaised ? 3 : 5) {
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
            }
            .foregroundStyle(CozyColor.inkOnAccent)
            .frame(maxWidth: .infinity)
            .frame(minHeight: CozyMetrics.minimumTouchTarget)
            // Shape first, then lift. `contentShape` fixes what counts as the
            // button, and `offset` carries that shape along with the drawing,
            // so the raised cupcake is tappable where it appears rather than
            // where it would have been. Shaping *after* the offset would pin
            // the hit area to the layout frame and leave the cupcake dead.
            //
            // The whole column rises, label included, rather than the circle
            // alone: a tap target that doesn't match the thing you are looking
            // at is the one bug in a tab bar nobody forgives.
            .contentShape(.rect)
            .offset(y: isRaised ? -CozyMetrics.tabBarMascotLift : 0)
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

    /// The Sous Chef's cupcake, standing out of the top of the bar.
    ///
    /// Bigger than the blocks beside it and lifted clear of the slab by its
    /// column's offset, so the tab the app is named after is the one thing in
    /// the bar you can hit without looking. The bar reserves the lift as real
    /// padding, so nothing above it is ever underneath the cupcake.
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
            .padding(9)
            .frame(width: CozyMetrics.tabBarMascotDiameter,
                   height: CozyMetrics.tabBarMascotDiameter)
            .background(CozyColor.card, in: .circle)
            .overlay {
                Circle().strokeBorder(accent.deep, lineWidth: isSelected ? 4 : 3)
            }
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
