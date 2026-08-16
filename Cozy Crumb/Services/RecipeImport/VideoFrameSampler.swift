//
//  VideoFrameSampler.swift
//  Cozy Crumb
//
//  Turns a video into a handful of stills.
//
//  Sending the whole video is always better — the recipe is often spoken
//  rather than shown, and frames throw the audio away. But a request has to
//  fit inside Gemini's inline limit, and a two-minute 4K recording from
//  someone's camera roll does not. Sampling evenly across the clip keeps the
//  on-screen ingredient list and the method captions, which is usually where
//  the recipe actually lives in a Reel.
//

import AVFoundation
import CoreGraphics
import Foundation
import os

enum VideoFrameSampler {

    /// Evenly spaced stills, oldest first. Returns an empty array rather than
    /// failing — the caller always has the paste-the-caption route left.
    nonisolated static func frames(
        from url: URL,
        maximum: Int = 8,
        maxDimension: CGFloat = 768
    ) async -> [Data] {
        let asset = AVURLAsset(url: url)

        guard let duration = try? await asset.load(.duration), duration.seconds.isFinite else {
            Log.importer.info("Could not read the video's duration")
            return []
        }

        let seconds = max(duration.seconds, 0.1)
        let count = max(1, min(maximum, Int(seconds / 2) + 1))

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        // A frame a half-second either side of the ask is no worse for reading
        // text off, and seeking exactly is slow.
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        var frames: [Data] = []

        for index in 0..<count {
            // Offset into each slice rather than sampling its edges: the first
            // and last moments of a clip are usually a title card or a
            // like-and-subscribe.
            let fraction = (Double(index) + 0.5) / Double(count)
            let time = CMTime(seconds: seconds * fraction, preferredTimescale: 600)

            guard let result = try? await generator.image(at: time),
                  let data = ImageProcessor.jpeg(from: result.image, quality: 0.6) else {
                continue
            }

            frames.append(data)
        }

        Log.importer.info("Sampled \(frames.count, privacy: .public) frames from a video")
        return frames
    }
}
