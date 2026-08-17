//
//  FridgeShotsView.swift
//  Cozy Crumb
//
//  What you've photographed so far, before any of it is sent to be read.
//
//  The camera takes one shot and closes, which is the right behaviour — but a
//  fridge is rarely one shelf. This is where the shots collect, so "one photo
//  per shelf" is a thing you can actually do, and where a bad one gets thrown
//  away before it has a chance to confuse the answer.
//

import SwiftUI
import UIKit

struct FridgeShotsView: View {
    @Environment(\.dismiss) private var dismiss

    let shots: [UIImage]
    var hasCamera: Bool = true
    /// Four is what the reader was built for, and more photos of the same
    /// fridge stop adding anything.
    var limit: Int = 4

    let onTakeAnother: () -> Void
    let onRemove: (Int) -> Void
    let onPickFromPhotos: () -> Void
    let onRead: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: CozySpacing.l) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: CozySpacing.m) {
                        ForEach(Array(shots.enumerated()), id: \.offset) { index, shot in
                            thumbnail(shot, at: index)
                        }
                    }
                    .padding(.horizontal, CozySpacing.l)
                    .padding(.vertical, CozySpacing.s)
                }

                Text(shots.count < limit
                     ? "Tap a photo to throw it away. One per shelf reads best."
                     : "That's as many as I can read at once.")
                    .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, CozySpacing.l)

                Spacer(minLength: 0)

                VStack(spacing: CozySpacing.s) {
                    SquishyButton(
                        title: shots.count == 1 ? "Read this photo" : "Read these \(shots.count) photos",
                        systemImage: "sparkles"
                    ) {
                        onRead()
                    }
                    .disabled(shots.isEmpty)

                    if shots.count < limit {
                        SquishyButton(
                            title: hasCamera ? "Take another" : "Add from photos",
                            systemImage: hasCamera ? "camera" : "photo.on.rectangle",
                            emphasis: .secondary
                        ) {
                            if hasCamera {
                                onTakeAnother()
                            } else {
                                onPickFromPhotos()
                            }
                        }
                    }
                }
                .padding(.horizontal, CozySpacing.l)
                .padding(.bottom, CozySpacing.l)
            }
            .frame(maxWidth: .infinity)
            .background { BlobBackground() }
            .navigationTitle(shots.count == 1 ? "1 photo" : "\(shots.count) photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func thumbnail(_ shot: UIImage, at index: Int) -> some View {
        Button {
            onRemove(index)
        } label: {
            Image(uiImage: shot)
                .resizable()
                .scaledToFill()
                .frame(width: 132, height: 176)
                .clipShape(RoundedRectangle(cornerRadius: CozyRadius.image, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(CozyColor.inkPrimary, CozyColor.cream)
                        .padding(CozySpacing.xs)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: CozyRadius.image, style: .continuous)
                        .strokeBorder(CozyColor.outline, lineWidth: CozyBorder.card)
                }
        }
        .buttonStyle(.squishy)
        .accessibilityLabel("Photo \(index + 1). Tap to remove.")
    }
}
