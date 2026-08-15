//
//  ImageProcessor.swift
//  Cozy Crumb
//
//  Downloads and downscales hero images. Stored images are capped at 1200px on
//  the long edge at JPEG 0.8 — a phone screen cannot show more, and a local-only
//  library has no cloud to offload to.
//
//  Uses ImageIO rather than UIImage: CGImageSource decodes straight to a
//  thumbnail at the target size, so a 4000px source never has to be fully
//  decoded into memory first.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import os

enum ImageProcessor {

    nonisolated static let maxDimension: CGFloat = 1200
    nonisolated static let jpegQuality: CGFloat = 0.8

    /// Downscales and re-encodes as JPEG. Returns nil if the data isn't a
    /// readable image.
    nonisolated static func downscaledJPEG(
        from data: Data,
        maxDimension: CGFloat = ImageProcessor.maxDimension,
        quality: CGFloat = ImageProcessor.jpegQuality
    ) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary

        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Honour EXIF orientation, or portrait photos come out sideways.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }

        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, thumbnail, properties)

        guard CGImageDestinationFinalize(destination) else { return nil }

        return output as Data
    }
}

/// Fetches remote images. Separate from the coordinator so a failed image never
/// fails an import — a recipe without a picture is still a recipe.
actor ImageFetcher {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Returns downscaled JPEG data, or nil on any failure.
    func downscaledImage(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(NetworkConstants.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)

            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                Log.importer.info("Hero image returned \(http.statusCode, privacy: .public)")
                return nil
            }

            return ImageProcessor.downscaledJPEG(from: data)
        } catch {
            Log.importer.info("Hero image fetch failed")
            return nil
        }
    }
}

enum NetworkConstants {
    /// Many recipe sites reject requests with no User-Agent outright. This
    /// identifies as a normal mobile browser so public pages load the same way
    /// they would if the user opened the link themselves.
    nonisolated static let userAgent = """
    Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 \
    (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1
    """
}
