//
//  Motion.swift
//  Cozy Crumb
//
//  Spring constants and the single Reduce Motion code path (§7.4).
//
//  Views never branch on accessibilityReduceMotion themselves — they call
//  .cozyAnimation(_:value:) or read \.cozyMotion, and the swap to a plain fade
//  happens in exactly one place.
//
//  `nonisolated` for the same reason as Theme — see the note there.
//

import SwiftUI

enum Motion {
    /// Default for anything playful — card entrances, hearts, checkmarks.
    nonisolated static let bouncy = Animation.spring(response: 0.38, dampingFraction: 0.62)

    /// Press-down and other immediate responses.
    nonisolated static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.78)

    /// Large or slow movement — sheets, drawers, background drift.
    nonisolated static let gentle = Animation.spring(response: 0.55, dampingFraction: 0.85)

    /// Substituted for every spring above when Reduce Motion is on.
    nonisolated static let reduced = Animation.easeInOut(duration: 0.15)
}

/// Resolves a requested animation against the user's Reduce Motion setting.
struct MotionResolver: Sendable {
    let prefersReducedMotion: Bool

    nonisolated func callAsFunction(_ animation: Animation) -> Animation {
        prefersReducedMotion ? Motion.reduced : animation
    }

    /// Springs that overshoot are pointless under Reduce Motion; use this for
    /// scale/overshoot effects that should simply not happen.
    nonisolated func scale(_ pressed: CGFloat, resting: CGFloat = 1.0, isActive: Bool) -> CGFloat {
        guard !prefersReducedMotion else { return resting }
        return isActive ? pressed : resting
    }
}

extension EnvironmentValues {
    /// Reads Reduce Motion once so views can resolve animations without
    /// each of them querying the accessibility environment.
    var cozyMotion: MotionResolver {
        MotionResolver(prefersReducedMotion: accessibilityReduceMotion)
    }
}

extension View {
    /// Animates `value` changes with `animation`, downgrading to a short fade
    /// when Reduce Motion is enabled.
    func cozyAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(CozyAnimationModifier(animation: animation, value: value))
    }

    /// Standard insertion/removal for list and grid content (§7.4).
    func cozyTransition() -> some View {
        transition(.scale.combined(with: .opacity))
    }
}

private struct CozyAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? Motion.reduced : animation, value: value)
    }
}
