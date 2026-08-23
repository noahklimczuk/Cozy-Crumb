//
//  BlobBackground.swift
//  Cozy Crumb
//
//  Soft pastel blobs drifting slowly behind content (§7.2). Frozen entirely
//  when Reduce Motion is on — the blobs still draw, they just stop moving.
//
//  No screen wears this any more; `TileBackground` is the page now, and the
//  reasoning for the swap is at the top of that file. It is kept because it is
//  a finished piece of the design system and the decision to retire it for
//  good is a separate one from the redesign — but there is deliberately no
//  `cozyBackground()` modifier left, so nothing can pick it up by accident.
//

import Foundation
import SwiftUI

struct BlobBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Base opacity. Kept very low so text always wins.
    var intensity: Double = 0.08

    var body: some View {
        ZStack {
            CozyColor.cream

            if !reduceTransparency {
                GeometryReader { proxy in
                    if reduceMotion {
                        blobs(phase: 0, in: proxy.size)
                    } else {
                        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { context in
                            let phase = context.date.timeIntervalSinceReferenceDate
                            blobs(phase: phase, in: proxy.size)
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func blobs(phase: TimeInterval, in size: CGSize) -> some View {
        ZStack {
            blob(CozyColor.blush, diameter: size.width * 0.85,
                 baseX: size.width * 0.18, baseY: size.height * 0.16,
                 period: 34, amplitude: 26, phase: phase, offset: 0)

            blob(CozyColor.mint, diameter: size.width * 0.70,
                 baseX: size.width * 0.86, baseY: size.height * 0.30,
                 period: 41, amplitude: 32, phase: phase, offset: 1.7)

            blob(CozyColor.butter, diameter: size.width * 0.78,
                 baseX: size.width * 0.24, baseY: size.height * 0.82,
                 period: 47, amplitude: 24, phase: phase, offset: 3.1)

            blob(CozyColor.lavender, diameter: size.width * 0.60,
                 baseX: size.width * 0.82, baseY: size.height * 0.88,
                 period: 39, amplitude: 30, phase: phase, offset: 4.6)
        }
        .blur(radius: 48)
    }

    private func blob(
        _ color: Color,
        diameter: CGFloat,
        baseX: CGFloat,
        baseY: CGFloat,
        period: Double,
        amplitude: CGFloat,
        phase: TimeInterval,
        offset: Double
    ) -> some View {
        let t = (phase / period) * 2 * .pi + offset
        return Circle()
            .fill(color)
            .opacity(intensity)
            .frame(width: diameter, height: diameter)
            .position(
                x: baseX + CGFloat(sin(t)) * amplitude,
                y: baseY + CGFloat(cos(t * 0.8)) * amplitude
            )
    }
}

#Preview("Blob background") {
    ZStack {
        BlobBackground()
        VStack(spacing: CozySpacing.m) {
            MascotView(pose: .idle, size: 100)
            Text("Cozy Crumb")
                .cozyText(CozyFont.display)
            Text(AppBranding.tagline)
                .cozyText(CozyFont.subheadline, color: CozyColor.inkSecondary)
        }
    }
}
