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
        BlobBackground()
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
        BlobBackground()
        CozyLoadingView(messages: [
            "Squinting at the back of the shelf…",
            "Is that a lime or a lemon…",
            "Counting the eggs…"
        ])
    }
}

#Preview("Error") {
    ZStack {
        BlobBackground()
        CozyErrorView(message: "The kitchen's a bit quiet — check your connection?", onRetry: {})
    }
}
