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
//  The squish now has something to squish against: the primary button sits on
//  a block, so pressing it looks like pushing it flat onto the page rather
//  than shrinking it in mid-air.
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
        /// Filled with the accent's deep step, on a block of its own colour.
        /// One per screen.
        case primary
        /// Drawn as an outline and nothing else, for the action sitting beside
        /// the primary one.
        case secondary
        /// Soft-tinted, for tertiary or destructive-lite actions.
        case quiet
    }

    @Environment(\.accentPalette) private var accent

    let title: String
    var systemImage: String?
    var emphasis: Emphasis = .primary
    var isFullWidth: Bool = true
    /// The screen's one loud bar — "Start cooking", "Next step" — is taller
    /// than a button in a stack of them.
    var minHeight: CGFloat = CozyMetrics.minimumTouchTarget + 6
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: CozySpacing.s) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.body.weight(.bold))
                }
                Text(title)
                    .font(emphasis == .primary ? CozyFont.cardTitle : CozyFont.bodyEmphasis)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, CozySpacing.xl)
            .padding(.vertical, CozySpacing.m)
            .frame(maxWidth: isFullWidth ? .infinity : nil, minHeight: minHeight)
            .background(background, in: .rect(cornerRadius: CozyRadius.button, style: .continuous))
            .modifier(ButtonEdge(emphasis: emphasis, accent: accent))
        }
        .buttonStyle(.squishy)
        .accessibilityLabel(title)
    }

    private var background: Color {
        switch emphasis {
        // Clear, not card: an outlined button is a shape drawn on the page,
        // and a white fill under a 2.5pt border made it look like a card
        // someone had traced around.
        case .primary: accent.deep
        case .secondary: .clear
        case .quiet: accent.soft
        }
    }

    private var ink: Color {
        emphasis == .primary ? CozyColor.inkOnAccent : CozyColor.inkPrimary
    }
}

/// Which edge each emphasis wears.
///
/// A primary button is the one thing on the screen you are meant to press, so
/// it gets the block — in its own colour, so the offset reads as the button's
/// own edge rather than a beige shape behind it. The other two are
/// alternatives sitting beside it, and three blocks in a row reads as three
/// primary buttons.
private struct ButtonEdge: ViewModifier {
    let emphasis: SquishyButton.Emphasis
    let accent: AccentPalette

    func body(content: Content) -> some View {
        switch emphasis {
        case .primary:
            content.cozyBlockShadow(CozyDepth.block, color: accent.block)
        case .secondary:
            content.overlay {
                RoundedRectangle(cornerRadius: CozyRadius.button, style: .continuous)
                    .strokeBorder(accent.deep, lineWidth: 2.5)
            }
        case .quiet:
            content
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
                .font(.body.weight(.bold))
                .foregroundStyle(isOn ? CozyColor.inkOnAccent : CozyColor.inkPrimary)
                .frame(width: CozyMetrics.minimumTouchTarget,
                       height: CozyMetrics.minimumTouchTarget)
                .background(isOn ? (tint ?? accent.color) : CozyColor.card, in: .circle)
                // The accent's block only when the fill *is* the accent. A
                // call site that passes its own tint — butter for a favourite
                // — would otherwise get a pink edge under a yellow circle.
                .cozyBlockShadow(CozyDepth.small,
                                 color: isOn && tint == nil ? accent.block : CozyColor.block)
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
