//
//  SquishyButton.swift
//  Cozy Crumb
//
//  Every tappable element in the app uses this (§7.4): scales to 0.94 on press
//  with `snappy`, returns with `bouncy`, and fires a soft impact.
//
//  Haptics go through SwiftUI's .sensoryFeedback rather than a UIKit generator
//  so the press effect stays inside the view hierarchy and honours the global
//  toggle without any imperative call.
//

import SwiftUI

// MARK: - Style

struct SquishyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // Environment must be read inside a View, not in makeBody itself.
        SquishyBody(configuration: configuration)
    }

    private struct SquishyBody: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.hapticsEnabled) private var hapticsEnabled

        let configuration: SquishyButtonStyle.Configuration

        var body: some View {
            let pressed = configuration.isPressed

            configuration.label
                .scaleEffect(reduceMotion ? 1 : (pressed ? 0.94 : 1))
                .animation(
                    reduceMotion ? Motion.reduced : (pressed ? Motion.snappy : Motion.bouncy),
                    value: pressed
                )
                .sensoryFeedback(trigger: pressed) { _, isPressed in
                    guard hapticsEnabled, isPressed else { return nil }
                    return .impact(flexibility: .soft)
                }
        }
    }
}

extension ButtonStyle where Self == SquishyButtonStyle {
    static var squishy: SquishyButtonStyle { SquishyButtonStyle() }
}

// MARK: - Button

/// The app's primary call to action — a big squishy pill.
struct SquishyButton: View {
    enum Emphasis {
        /// Filled with the current accent. One per screen.
        case primary
        /// Outlined on card, for secondary actions.
        case secondary
        /// Soft-tinted, for tertiary or destructive-lite actions.
        case quiet
    }

    @Environment(\.accentPalette) private var accent

    let title: String
    var systemImage: String?
    var emphasis: Emphasis = .primary
    var isFullWidth: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: CozySpacing.s) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                }
                Text(title)
                    .font(CozyFont.bodyEmphasis)
            }
            .foregroundStyle(CozyColor.inkPrimary)
            .padding(.horizontal, CozySpacing.xl)
            .padding(.vertical, CozySpacing.m)
            .frame(maxWidth: isFullWidth ? .infinity : nil,
                   minHeight: CozyMetrics.minimumTouchTarget)
            .background(background, in: .rect(cornerRadius: CozyRadius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CozyRadius.button, style: .continuous)
                    .strokeBorder(border, lineWidth: CozyBorder.card)
            }
        }
        .buttonStyle(.squishy)
        .accessibilityLabel(title)
    }

    private var background: Color {
        switch emphasis {
        case .primary: accent.color
        case .secondary: CozyColor.card
        case .quiet: accent.soft
        }
    }

    private var border: Color {
        switch emphasis {
        case .primary: accent.deep
        case .secondary: CozyColor.outline
        case .quiet: .clear
        }
    }
}

// MARK: - Icon button

/// Circular icon button — toolbar actions, the heart on a recipe card.
struct SquishyIconButton: View {
    @Environment(\.accentPalette) private var accent

    let systemImage: String
    let accessibilityLabel: String
    var isOn: Bool = false
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(isOn ? CozyColor.inkPrimary : CozyColor.inkSecondary)
                .frame(width: CozyMetrics.minimumTouchTarget,
                       height: CozyMetrics.minimumTouchTarget)
                .background(isOn ? (tint ?? accent.color) : CozyColor.card, in: .circle)
                .overlay {
                    Circle().strokeBorder(CozyColor.outline, lineWidth: CozyBorder.card)
                }
                .cozyLiftShadow()
        }
        .buttonStyle(.squishy)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

#Preview("Buttons") {
    VStack(spacing: CozySpacing.l) {
        SquishyButton(title: "Save this recipe", systemImage: "heart.fill") {}
        SquishyButton(title: "Send to Notes", emphasis: .secondary) {}
        SquishyButton(title: "Copy list", emphasis: .quiet) {}
        HStack(spacing: CozySpacing.m) {
            SquishyIconButton(systemImage: "heart.fill", accessibilityLabel: "Favourite", isOn: true) {}
            SquishyIconButton(systemImage: "square.and.arrow.up", accessibilityLabel: "Share") {}
            SquishyIconButton(systemImage: "trash", accessibilityLabel: "Delete") {}
        }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CozyColor.cream)
}
