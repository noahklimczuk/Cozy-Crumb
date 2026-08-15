//
//  CrumbConfetti.swift
//  Cozy Crumb
//
//  A small burst of crumbs for the "I made this" moment (§5.3). Cheap, short,
//  and skipped entirely under Reduce Motion.
//

import Foundation
import SwiftUI

struct CrumbConfetti: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Flip to true to fire a burst.
    let isActive: Bool
    var count: Int = 18

    @State private var hasBurst = false

    private struct Crumb: Identifiable {
        let id: Int
        let angle: Double
        let distance: CGFloat
        let size: CGFloat
        let tint: Color
        let spin: Double
    }

    private var crumbs: [Crumb] {
        // Seeded off the index rather than random, so a crumb keeps its
        // trajectory across the animation's redraws.
        (0..<count).map { index in
            let fraction = Double(index) / Double(count)
            return Crumb(
                id: index,
                angle: fraction * 2 * .pi,
                distance: 90 + CGFloat((index * 37) % 70),
                size: 5 + CGFloat((index * 13) % 6),
                tint: CozyColor.accentRotation[index % CozyColor.accentRotation.count],
                spin: Double((index * 71) % 360)
            )
        }
    }

    var body: some View {
        ZStack {
            ForEach(crumbs) { crumb in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(crumb.tint)
                    .frame(width: crumb.size, height: crumb.size * 0.75)
                    .rotationEffect(.degrees(hasBurst ? crumb.spin : 0))
                    .offset(
                        x: hasBurst ? cos(crumb.angle) * crumb.distance : 0,
                        y: hasBurst ? sin(crumb.angle) * crumb.distance + 40 : 0
                    )
                    .opacity(hasBurst ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: isActive) { _, active in
            guard active, !reduceMotion else { return }
            hasBurst = false
            withAnimation(.easeOut(duration: 1.1)) {
                hasBurst = true
            }
        }
    }
}

#Preview("Confetti") {
    @Previewable @State var isActive = false

    ZStack {
        CozyColor.cream.ignoresSafeArea()
        VStack(spacing: CozySpacing.xl) {
            ZStack {
                MascotView(pose: .celebrating, size: 110)
                CrumbConfetti(isActive: isActive)
            }
            SquishyButton(title: "Burst", isFullWidth: false) {
                isActive.toggle()
            }
        }
    }
}
