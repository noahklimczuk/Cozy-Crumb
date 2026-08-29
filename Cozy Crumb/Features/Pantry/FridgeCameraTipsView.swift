//
//  FridgeCameraTipsView.swift
//  Cozy Crumb
//
//  Shown once, the first time someone points the camera at their fridge.
//
//  It earns its place because the quality of the answer depends almost
//  entirely on the quality of the photo, and none of what makes a good one is
//  obvious: a whole shelf beats a close-up, labels have to face the camera,
//  and nothing hidden behind the milk is ever going to be found. Told once,
//  those three things are the difference between a useful list and a shrug.
//
//  After the first time the camera opens straight away — the tips are still
//  reachable from the tray, and nobody wants a lesson every time.
//

import SwiftUI

struct FridgeCameraTipsView: View {
    @Environment(\.dismiss) private var dismiss

    /// Whether the camera is there to be opened. On the Simulator it isn't,
    /// and offering a button that does nothing is worse than saying so.
    var hasCamera: Bool = true

    let onStart: () -> Void
    let onPickFromPhotos: () -> Void

    private struct Tip: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
    }

    private let tips: [Tip] = [
        Tip(
            symbol: "refrigerator",
            title: "One shelf at a time",
            detail: "Open the door, stand back far enough to get a whole shelf in, and let it fill the frame."
        ),
        Tip(
            symbol: "tag",
            title: "Turn the labels forward",
            detail: "It reads packets the way you would. A jar facing the wall is just a jar."
        ),
        Tip(
            symbol: "eye",
            title: "Only what's visible counts",
            detail: "Anything hiding behind the milk won't be found — move things forward, or take a second photo."
        ),
        Tip(
            symbol: "checklist",
            title: "Nothing's added until you say so",
            detail: "You get a list to look over first, and can drop anything it got wrong."
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CozySpacing.l) {
                    header

                    VStack(spacing: CozySpacing.m) {
                        ForEach(tips) { tip in
                            row(for: tip)
                        }
                    }

                    VStack(spacing: CozySpacing.s) {
                        if hasCamera {
                            SquishyButton(title: "Open the camera", systemImage: "camera.fill") {
                                onStart()
                            }
                        }

                        Button(hasCamera ? "Choose from photos instead" : "Choose from photos") {
                            onPickFromPhotos()
                        }
                        .font(CozyFont.subheadline)
                        .foregroundStyle(CozyColor.inkSecondary)
                        .frame(minHeight: CozyMetrics.minimumTouchTarget)
                    }
                }
                .padding(CozySpacing.l)
            }
            .cozyScreenBackground()
            .navigationTitle("Snap the fridge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        HStack(alignment: .top, spacing: CozySpacing.m) {
            MascotView(pose: .peeking, size: 64)

            Text("Take a photo of what's in and I'll write down everything I can see.")
                .cozyText(CozyFont.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(for tip: Tip) -> some View {
        CrumbCard(padding: CozySpacing.m) {
            HStack(alignment: .top, spacing: CozySpacing.m) {
                Image(systemName: tip.symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(CozyColor.blushDeep)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tip.title)
                        .cozyText(CozyFont.bodyEmphasis)
                    Text(tip.detail)
                        .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tip.title). \(tip.detail)")
    }
}

#Preview("Fridge camera tips") {
    FridgeCameraTipsView(onStart: {}, onPickFromPhotos: {})
}
