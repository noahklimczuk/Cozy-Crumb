//
//  MascotView.swift
//  Cozy Crumb
//
//  The shared cupcake mascot. It appears throughout empty, loading, import,
//  and cook-log states, with one gentle animation system for every screen.
//

import SwiftUI

struct MascotView: View {
    enum Pose: String, CaseIterable, Identifiable, Sendable {
        case idle
        case peeking
        case cooking
        case celebrating
        case sleeping

        var id: String { rawValue }
    }

    private enum EyeExpression: Sendable {
        case open
        case blink
        case winkLeft
        case winkRight

        var closesLeftEye: Bool { self == .blink || self == .winkLeft }
        var closesRightEye: Bool { self == .blink || self == .winkRight }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var pose: Pose = .idle
    var size: CGFloat = 120
    /// Kept for source compatibility with existing mascot call sites.
    var tint: Color?

    @State private var eyeExpression: EyeExpression = .open
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            Image("CupcakeMascot")
                .resizable()
                .scaledToFit()

            animatedEyelids

            if pose == .celebrating {
                sparkles
            }
            if pose == .sleeping {
                sleepMark
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(isBreathing ? 1.018 : 0.992)
        .offset(y: isBreathing ? -u(0.012) : u(0.006))
        .task(id: animationKey) {
            await runAnimations()
        }
        .accessibilityHidden(true)
    }

    private var animatedEyelids: some View {
        GeometryReader { proxy in
            let visualSize = min(proxy.size.width, proxy.size.height)

            if eyeExpression.closesLeftEye {
                eyelid(size: visualSize)
                    .position(x: visualSize * 0.39, y: visualSize * 0.414)
            }
            if eyeExpression.closesRightEye {
                eyelid(size: visualSize)
                    .position(x: visualSize * 0.61, y: visualSize * 0.414)
            }
        }
        .allowsHitTesting(false)
    }

    private func eyelid(size: CGFloat) -> some View {
        ZStack {
            Ellipse()
                .fill(Color(red: 252 / 255, green: 240 / 255, blue: 218 / 255))
                .frame(width: size * 0.115, height: size * 0.105)
            Capsule()
                .fill(CozyColor.inkPrimary)
                .frame(width: size * 0.105, height: size * 0.027)
        }
    }

    private var sparkles: some View {
        ZStack {
            sparkle.offset(x: -u(0.40), y: -u(0.32))
            sparkle.scaleEffect(0.7).offset(x: u(0.39), y: -u(0.20))
            sparkle.scaleEffect(0.55).offset(x: u(0.32), y: u(0.31))
        }
    }

    private var sparkle: some View {
        Image(systemName: "sparkle")
            .font(.system(size: u(0.15), weight: .semibold))
            .foregroundStyle(CozyColor.butter)
    }

    private var sleepMark: some View {
        Text("z")
            .font(.system(size: u(0.20), weight: .bold, design: .rounded))
            .foregroundStyle(CozyColor.inkSecondary)
            .offset(x: u(0.38), y: -u(0.36))
    }

    private var animationKey: String {
        "\(pose.rawValue)-\(reduceMotion)"
    }

    private func runAnimations() async {
        guard !reduceMotion else {
            isBreathing = false
            eyeExpression = .open
            return
        }

        withAnimation(.easeInOut(duration: 2.35).repeatForever(autoreverses: true)) {
            isBreathing = true
        }

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 2.8...5.2)))
            guard !Task.isCancelled else { return }

            let shouldWink = pose == .cooking || Bool.random()
            withAnimation(.easeInOut(duration: 0.10)) {
                eyeExpression = shouldWink
                    ? (Bool.random() ? .winkLeft : .winkRight)
                    : .blink
            }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.12)) {
                eyeExpression = .open
            }
        }
    }

    private func u(_ fraction: CGFloat) -> CGFloat {
        size * fraction
    }
}

#Preview("Cupcake mascot") {
    ScrollView {
        VStack(spacing: CozySpacing.xl) {
            ForEach(MascotView.Pose.allCases) { pose in
                VStack(spacing: CozySpacing.s) {
                    MascotView(pose: pose, size: 120)
                    Text(pose.rawValue.capitalized)
                        .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                }
            }
        }
        .padding(CozySpacing.xl)
    }
    .background(CozyColor.cream)
}
