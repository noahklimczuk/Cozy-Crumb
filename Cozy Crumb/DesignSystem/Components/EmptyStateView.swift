//
//  EmptyStateView.swift
//  Cozy Crumb
//
//  Every list gets one of these — no blank screens, ever (§8.18). Also covers
//  the loading and error states so a screen's three non-content states all
//  share one look.
//

import Foundation
import SwiftUI

extension View {
    /// Lets a screen-filling layout scroll once it outgrows the screen.
    ///
    /// An empty state is normally centred in whatever space is left over, and
    /// at ordinary text sizes it fits with room to spare. At an accessibility
    /// size it does not: the AX5 capture of the Sous Chef showed the mascot
    /// sliced off by the Dynamic Island at the top and the paragraph running
    /// off past the tab bar at the bottom, because nothing in that screen
    /// could scroll. A centred layout that overflows loses content at *both*
    /// ends, which is the worst version of this bug.
    ///
    /// `minHeight` is the container's own height, so the content is still
    /// centred exactly as before whenever it fits; it only starts scrolling
    /// once it doesn't. `.basedOnSize` keeps the bounce away in the common
    /// case, so a screen that fits doesn't suddenly feel like a list.
    ///
    /// Apply this only where the caller already fills the space it is given.
    /// Inside a self-sizing container — a card — the `GeometryReader` would
    /// take every point on offer and stretch it.
    func cozyScrollsWhenTall() -> some View {
        GeometryReader { proxy in
            ScrollView {
                self.frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    var pose: MascotView.Pose = .sleeping
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: CozySpacing.l) {
            MascotView(pose: pose, size: 116)

            VStack(spacing: CozySpacing.s) {
                Text(title)
                    .cozyText(CozyFont.title2)
                    .multilineTextAlignment(.center)
                    // The same `fixedSize` the message below has always had,
                    // and the reason the two behaved differently at large
                    // text sizes. Without it the title is offered a single
                    // line's worth of height and truncates rather than wraps:
                    // the AX5 captures read "Nothing o…" and "The Sou…" while
                    // the paragraph under them wrapped perfectly well.
                    .fixedSize(horizontal: false, vertical: true)

                Text(message)
                    .cozyText(CozyFont.subheadline, color: CozyColor.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                SquishyButton(title: actionTitle, isFullWidth: false, action: action)
                    .padding(.top, CozySpacing.xs)
            }
        }
        .padding(CozySpacing.xl)
        .frame(maxWidth: 420)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityHint(message)
    }
}

/// Loading state with rotating status lines — used for the fridge scan, where
/// the call takes several seconds and a bare spinner would feel broken (§5.7).
struct CozyLoadingView: View {
    let messages: [String]
    var pose: MascotView.Pose = .peeking
    /// Seconds between status lines.
    var interval: TimeInterval = 2.4

    @State private var index = 0

    var body: some View {
        VStack(spacing: CozySpacing.l) {
            MascotView(pose: pose, size: 116)

            Text(currentMessage)
                .cozyText(CozyFont.subheadline, color: CozyColor.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                .id(currentMessage)
                .transition(.opacity)
                .cozyAnimation(Motion.gentle, value: index)
        }
        .padding(CozySpacing.xl)
        .task(id: messages) {
            guard messages.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                index = (index + 1) % messages.count
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(currentMessage)
    }

    private var currentMessage: String {
        guard !messages.isEmpty else { return "" }
        return messages[min(index, messages.count - 1)]
    }
}

/// Error state. Copy is written in the app's voice, never a raw error string.
struct CozyErrorView: View {
    let message: String
    var retryTitle: String = "Try again"
    var onRetry: (() -> Void)?

    var body: some View {
        EmptyStateView(
            title: "Hmm.",
            message: message,
            pose: .idle,
            actionTitle: onRetry == nil ? nil : retryTitle,
            action: onRetry
        )
    }
}

#Preview("Empty") {
    ZStack {
        TileBackground()
        EmptyStateView(
            title: "Your cookbook's a blank page.",
            message: "Paste a link to get started — I'll do the tidying up.",
            pose: .sleeping,
            actionTitle: "Paste a link",
            action: {}
        )
    }
}

#Preview("Loading") {
    ZStack {
        TileBackground()
        CozyLoadingView(messages: [
            "Squinting at the back of the shelf…",
            "Is that a lime or a lemon…",
            "Counting the eggs…"
        ])
    }
}

#Preview("Error") {
    ZStack {
        TileBackground()
        CozyErrorView(message: "The kitchen's a bit quiet — check your connection?", onRetry: {})
    }
}
