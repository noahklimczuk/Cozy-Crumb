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

        // Bottom-aligned, so the five labels share a line.
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(CozyTab.allCases) { tab in
                item(for: tab)
            }
        }
        .padding(.horizontal, CozySpacing.xs)
        .padding(.bottom, CozySpacing.m)
        .frame(maxWidth: .infinity, minHeight: CozyMetrics.tabBarHeight)
        // A clear strip on top of the painted slab, and it is load-bearing.
        //
        // What `safeAreaInset` hands back to every screen is this view's whole
        // height, so the strip is how far above the slab a scroll view stops.
        // Without it content ends flush against the pink — the last row half
        // under it, and a card's block, which draws 4pt outside its own frame,
        // entirely under it. That is what "scrolling is broken and things
        // overlap" looked like on every tab.
        //
        // It used to be here to reserve room for the cupcake standing out of
        // the bar. The cupcake sits on the row now; the gap is still needed,
        // for the other reason it was always doing this job.
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
            .background(CozyColor.card, in: .circle)
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
