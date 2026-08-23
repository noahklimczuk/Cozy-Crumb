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

import SwiftUI

struct MascotTabBar: View {
    @Environment(\.accentPalette) private var accent
    @Environment(\.cozyMotion) private var motion

    @Binding var selection: CozyTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CozyTab.allCases) { tab in
                item(for: tab)
            }
        }
        .padding(.horizontal, CozySpacing.xs)
        .padding(.vertical, CozySpacing.xs)
        .frame(maxWidth: .infinity, minHeight: CozyMetrics.tabBarHeight)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: CozyRadius.header,
                topTrailingRadius: CozyRadius.header,
                style: .continuous
            )
            .fill(CozyColor.card)
            // The one block in the app that points up: the bar is stuck to
            // the bottom edge, so a shadow below it would be off the screen.
            .shadow(color: CozyColor.block, radius: 0, x: 0, y: -CozyDepth.small)
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
            VStack(spacing: 3) {
                icon(for: tab, isSelected: isSelected)

                Text(tab.title)
                    .font(CozyFont.caption2.weight(isSelected ? .bold : .medium))
                    .lineLimit(1)
                    // Takes up the last of the slack inside the cap above.
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? CozyColor.inkPrimary : CozyColor.inkSecondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: CozyMetrics.minimumTouchTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.squishy)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func icon(for tab: CozyTab, isSelected: Bool) -> some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(accent.color)
                .opacity(isSelected ? 1 : 0)

            glyph(for: tab)
        }
        .frame(width: 46, height: 26)
    }

    @ViewBuilder
    private func glyph(for tab: CozyTab) -> some View {
        if tab == .sousChef {
            Image("CupcakeMascot")
                .resizable()
                .scaledToFit()
                .frame(width: 21, height: 21)
        } else {
            Image(systemName: tab.symbol)
                .font(.system(size: 16, weight: .semibold))
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
