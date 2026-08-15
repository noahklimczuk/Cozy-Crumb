//
//  MascotView.swift
//  Cozy Crumb
//
//  The crumb. Drawn entirely from SwiftUI shapes — no image assets — so it
//  re-tints with the accent picker and stays crisp at every size.
//
//  Appears in empty states, loading states, the fridge-scan wait, the Cook
//  Mode finish screen, and About.
//

import SwiftUI

struct MascotView: View {
    enum Pose: String, CaseIterable, Identifiable, Sendable {
        /// Default. Neutral smile, occasional blink.
        case idle
        /// Eyes up and to the side — used while scanning a fridge photo.
        case peeking
        /// Winking. Used mid-task and on the Sous Chef.
        case cooking
        /// Happy closed eyes with sparkles — cook logged, import saved.
        case celebrating
        /// Closed eyes and a "z" — empty states and quiet screens.
        case sleeping

        var id: String { rawValue }
    }

    @Environment(\.accentPalette) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var pose: Pose = .idle
    var size: CGFloat = 120
    /// Overrides the accent tint when a specific colour is needed.
    var tint: Color?

    @State private var isBlinking = false
    @State private var isBobbing = false

    var body: some View {
        ZStack {
            body_
            face
            if pose == .celebrating {
                sparkles
            }
            if pose == .sleeping {
                sleepMark
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(pose == .celebrating ? -6 : 0))
        .offset(y: isBobbing ? -u(0.02) : 0)
        .task(id: animationKey) {
            await runIdleAnimations()
        }
        .accessibilityHidden(true)
    }

    // MARK: - Pieces

    private var bodyColor: Color { tint ?? accent.color }

    private var body_: some View {
        ZStack {
            Circle()
                .fill(bodyColor)
            Circle()
                .strokeBorder(CozyColor.outlineStrong, lineWidth: CozyBorder.illustrative)
            // A soft highlight so the crumb reads as rounded, not flat.
            Ellipse()
                .fill(Color.white.opacity(0.28))
                .frame(width: u(0.34), height: u(0.20))
                .offset(x: -u(0.16), y: -u(0.24))
                .blur(radius: u(0.03))
        }
    }

    private var face: some View {
        ZStack {
            // Cheeks
            HStack(spacing: u(0.30)) {
                cheek
                cheek
            }
            .offset(y: u(0.09))

            // Eyes
            HStack(spacing: u(0.20)) {
                eye
                eye
            }
            .offset(x: eyeOffsetX, y: -u(0.04) + eyeOffsetY)

            // Mouth
            mouth
                .offset(y: u(0.14))
        }
    }

    private var cheek: some View {
        Ellipse()
            .fill(CozyColor.blushDeep.opacity(0.45))
            .frame(width: u(0.15), height: u(0.10))
    }

    @ViewBuilder
    private var eye: some View {
        switch pose {
        case .celebrating:
            // Happy closed arcs.
            ArcShape()
                .stroke(CozyColor.inkPrimary, style: StrokeStyle(lineWidth: u(0.035), lineCap: .round))
                .frame(width: u(0.15), height: u(0.09))
        case .sleeping:
            Capsule()
                .fill(CozyColor.inkPrimary)
                .frame(width: u(0.13), height: u(0.028))
        default:
            Capsule()
                .fill(CozyColor.inkPrimary)
                .frame(width: u(0.09), height: isBlinking ? u(0.028) : u(0.12))
                .cozyAnimation(Motion.snappy, value: isBlinking)
        }
    }

    @ViewBuilder
    private var mouth: some View {
        switch pose {
        case .celebrating:
            // Open happy mouth.
            Ellipse()
                .fill(CozyColor.inkPrimary)
                .frame(width: u(0.14), height: u(0.11))
        case .sleeping:
            Circle()
                .fill(CozyColor.inkPrimary.opacity(0.7))
                .frame(width: u(0.05), height: u(0.05))
        default:
            SmileShape()
                .stroke(CozyColor.inkPrimary, style: StrokeStyle(lineWidth: u(0.032), lineCap: .round))
                .frame(width: u(0.20), height: u(0.09))
        }
    }

    private var sparkles: some View {
        ZStack {
            sparkle.offset(x: -u(0.44), y: -u(0.34))
            sparkle.scaleEffect(0.7).offset(x: u(0.42), y: -u(0.22))
            sparkle.scaleEffect(0.55).offset(x: u(0.34), y: u(0.36))
        }
    }

    private var sparkle: some View {
        Image(systemName: "sparkle")
            .font(.system(size: u(0.16), weight: .semibold))
            .foregroundStyle(CozyColor.butter)
    }

    private var sleepMark: some View {
        Text("z")
            .font(.system(size: u(0.22), weight: .bold, design: .rounded))
            .foregroundStyle(CozyColor.inkSecondary)
            .offset(x: u(0.40), y: -u(0.38))
    }

    // MARK: - Pose geometry

    /// The crumb glances up-left when peeking into a fridge.
    private var eyeOffsetX: CGFloat {
        switch pose {
        case .peeking: -u(0.03)
        case .cooking: u(0.02)
        default: 0
        }
    }

    private var eyeOffsetY: CGFloat {
        pose == .peeking ? -u(0.03) : 0
    }

    // MARK: - Animation

    /// Recomputed when either input changes so `.task` restarts cleanly.
    private var animationKey: String {
        "\(pose.rawValue)-\(reduceMotion)"
    }

    private func runIdleAnimations() async {
        guard !reduceMotion else {
            isBlinking = false
            isBobbing = false
            return
        }

        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
            isBobbing = true
        }

        // Sleeping crumbs don't blink.
        guard pose != .sleeping, pose != .celebrating else { return }

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 2.5...6.0)))
            guard !Task.isCancelled else { return }
            isBlinking = true
            try? await Task.sleep(for: .milliseconds(130))
            isBlinking = false
        }
    }

    /// Unit helper — every dimension is a fraction of the mascot's size.
    private func u(_ fraction: CGFloat) -> CGFloat {
        size * fraction
    }
}

// MARK: - Shapes

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY * 1.8)
        )
        return path
    }
}

/// Upward arc used for happy closed eyes.
private struct ArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.6)
        )
        return path
    }
}

#Preview("Mascot poses") {
    ScrollView {
        VStack(spacing: CozySpacing.xl) {
            ForEach(MascotView.Pose.allCases) { pose in
                VStack(spacing: CozySpacing.s) {
                    MascotView(pose: pose, size: 110)
                    Text(pose.rawValue.capitalized)
                        .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                }
            }
        }
        .padding(CozySpacing.xl)
    }
    .frame(maxWidth: .infinity)
    .background(CozyColor.cream)
}

#Preview("Mascot accents") {
    HStack(spacing: CozySpacing.l) {
        ForEach(AccentPalette.allCases) { palette in
            MascotView(pose: .idle, size: 64)
                .environment(\.accentPalette, palette)
        }
    }
    .padding()
    .background(CozyColor.cream)
}
