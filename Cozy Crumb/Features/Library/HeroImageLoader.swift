//
//  HeroImageLoader.swift
//  Cozy Crumb
//
//  Decodes a recipe's hero photo down to the size it is actually drawn at,
//  off the main thread, and remembers the result.
//
//  This exists because of a launch that would not launch. `RecipeHeroView`
//  called `UIImage(data:)` directly inside its `body`, which decodes the
//  *whole* image: a photo imported from a recipe site is routinely 4000x3000
//  or larger, and a decoded 4000x3000 image is around 48MB of bitmap
//  regardless of the fact that it is about to be drawn into a card two inches
//  wide. A grid of them, decoded synchronously while SwiftUI was evaluating
//  the Cookbook's body, is what stalled the app before it could draw a frame —
//  with eleven recipes, which is why every theory about the store being too
//  large was wrong.
//
//  Two things fix it, and both are needed. Downsampling means a card decodes a
//  few hundred kilobytes instead of tens of megabytes; doing it off the main
//  thread means even that never happens while a view is being built.
//
//  ImageIO rather than `UIImage(data:)` + resize: `CGImageSourceCreateThumbnail`
//  decodes straight to the target size, so the full-size bitmap is never
//  allocated at all. Resizing afterwards would mean paying the cost first,
//  which is the cost being avoided.
//

import CoreGraphics
import Foundation
import ImageIO
import UIKit
import os

nonisolated enum HeroImageLoader {

    /// Longest edge, in pixels, for a photo drawn on a card.
    ///
    /// A card's picture is about 200pt wide, so 800px covers it at 3x with
    /// room to spare. Detail screens pass something larger.
    static let cardPixelSize: CGFloat = 800

    /// Longest edge for the full-width photo on a recipe screen.
    static let detailPixelSize: CGFloat = 1600

    /// Decoded images, keyed by recipe and target size.
    ///
    /// `NSCache` rather than a dictionary: it evicts itself under memory
    /// pressure, which is the exact condition this code is here to avoid
    /// making worse.
    ///
    /// `nonisolated(unsafe)` because `NSCache` predates `Sendable` and has
    /// never been annotated, so the compiler assumes the worst. Apple
    /// documents it as safe to use from multiple threads without external
    /// locking, which is the whole reason it is the right container here: the
    /// decode runs off the main actor and the lookup runs on it.
    nonisolated(unsafe) private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 60
        return cache
    }()

    static func cached(for id: UUID, maxPixelSize: CGFloat) -> UIImage? {
        cache.object(forKey: key(id, maxPixelSize))
    }

    /// Decodes `data` down to `maxPixelSize` on its longest edge.
    ///
    /// Call this off the main actor. It is deliberately not `async` itself —
    /// the caller decides which executor it runs on, and every caller here
    /// hands it to a detached task.
    static func decode(_ data: Data, id: UUID, maxPixelSize: CGFloat) -> UIImage? {
        if let hit = cache.object(forKey: key(id, maxPixelSize)) { return hit }
        guard let image = downsample(data, maxPixelSize: maxPixelSize) else { return nil }
        cache.setObject(image, forKey: key(id, maxPixelSize))
        return image
    }

    /// The same decode without the cache, for images that have no recipe to be
    /// keyed by — a photo being reviewed on the way in, for instance.
    static func downsample(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
        // `kCGImageSourceShouldCache: false` on the source: the point is to
        // avoid holding the full-size representation anywhere, and caching it
        // here would put it straight back.
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            Log.data.error("Hero image could not be read as an image source")
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Honours the EXIF orientation, so a photo taken sideways is not
            // drawn sideways.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as [CFString: Any] as CFDictionary

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            Log.data.error("Hero image could not be decoded")
            return nil
        }

        return UIImage(cgImage: thumbnail)
    }

    private static func key(_ id: UUID, _ maxPixelSize: CGFloat) -> NSString {
        "\(id.uuidString)-\(Int(maxPixelSize))" as NSString
    }
}
