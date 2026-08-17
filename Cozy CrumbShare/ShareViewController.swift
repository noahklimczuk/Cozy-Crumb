//
//  ShareViewController.swift
//  Cozy CrumbShare
//
//  The share sheet entry: send a link from Instagram, TikTok, Safari or
//  Messages straight into the importer.
//
//  It does as little as possible on purpose. A free Apple ID cannot use App
//  Groups, so the extension has no shared container to write a recipe into,
//  and it has no business running an import inside a share sheet anyway —
//  that would mean a network call, an API key, and a review screen inside a
//  process iOS is happy to kill. So the whole job is:
//
//      find the link → open cozycrumb://import?url=… → get out of the way
//
//  There is deliberately no UI. A share extension that flashes a screen to say
//  "opening…" is slower to use than one that just opens.
//

import Foundation
import UIKit
import UniformTypeIdentifiers
import os

final class ShareViewController: UIViewController {

    private static let log = Logger(subsystem: "ca.klimczuk.cozycrumb", category: "share")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        Task { await handOffSharedLink() }
    }

    // MARK: - The hand-off

    private func handOffSharedLink() async {
        guard let shared = await sharedURL() else {
            Self.log.info("Nothing shareable in that item")
            finish()
            return
        }

        guard let deepLink = CozyDeepLink.importing(shared) else {
            finish()
            return
        }

        let opened = await open(deepLink)

        if !opened {
            // Nothing useful left to do — the sheet is the wrong place to
            // explain it, and the link is still on the user's clipboard route.
            Self.log.error("The system declined to open \(CozyDeepLink.scheme, privacy: .public)://")
        }

        finish()
    }

    // MARK: - Finding the link

    /// A shared item can carry the link as a URL, or as text with the link
    /// somewhere inside it — Instagram and TikTok both hand over a sentence
    /// with the URL buried in it, so both are worth reading.
    private func sharedURL() async -> URL? {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []

        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = await Self.loadURL(from: provider) {
                    return url
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = await Self.loadText(from: provider),
                   let url = Self.firstURL(in: text) {
                    return url
                }
            }
        }

        return nil
    }

    /// Loaded through the completion-handler form rather than the `async` one
    /// so that only the `URL` crosses back — `NSSecureCoding` isn't `Sendable`,
    /// and unwrapping it on this side of the boundary keeps the compiler happy
    /// without an `@unchecked` anywhere.
    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? URL)
            }
        }
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? String)
            }
        }
    }

    /// Deliberately a copy of the app's own rule rather than a shared file:
    /// one small duplicated function is cheaper than making the whole import
    /// stack build twice.
    static func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)

        return detector.firstMatch(in: text, range: range)?.url
    }

    // MARK: - Handing over

    /// `extensionContext.open` is the only sanctioned way out of a share
    /// extension. The old trick of walking the responder chain to find
    /// `UIApplication` is not used here: it needs extension-unsafe API, and a
    /// share extension that links against it is the wrong trade for a fallback
    /// that Apple has been closing off for years.
    private func open(_ url: URL) async -> Bool {
        guard let context = extensionContext else { return false }

        return await withCheckedContinuation { continuation in
            context.open(url) { opened in
                continuation.resume(returning: opened)
            }
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
