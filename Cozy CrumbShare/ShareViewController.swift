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
//  Getting out of the way is the hard part, and the first version of this got
//  it wrong: iOS does not really want a share extension opening its containing
//  app. `extensionContext.open` is documented for Today widgets, and from a
//  share sheet it answers false — or never answers at all, which left the
//  sheet sitting there awaiting a callback that was never coming. That is what
//  "nothing happens when you share" looked like.
//
//  So nothing here waits on a callback. The responder chain goes first because
//  it is synchronous and it is what actually works; `extensionContext.open` is
//  the fallback, fire-and-forget; the link goes on the pasteboard before
//  either is tried; and if neither route exists the extension says so on
//  screen. Silence is the one outcome ruled out.
//

import Foundation
import ObjectiveC
import UIKit
import UniformTypeIdentifiers
import os

final class ShareViewController: UIViewController {

    private static let log = Logger(subsystem: "ca.klimczuk.cozycrumb", category: "share")

    private var hasStarted = false

    /// Deliberately `viewDidAppear` rather than `viewDidLoad`. Asking the
    /// system to open a URL before the extension is actually on screen is one
    /// of the ways this quietly fails.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !hasStarted else { return }
        hasStarted = true

        Task { await handOffSharedLink() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    // MARK: - The hand-off

    private func handOffSharedLink() async {
        guard let shared = await sharedURL() else {
            Self.log.error("No link in the shared item")
            await explain("Cozy Crumb couldn't find a link in that.")
            finish()
            return
        }

        guard let deepLink = CozyDeepLink.importing(shared) else {
            Self.log.error("Could not build an import link")
            await explain("Cozy Crumb couldn't read that link.")
            finish()
            return
        }

        // Always leave the link on the pasteboard, before trying anything. The
        // user just shared a link, so it is no surprise to find it there, and
        // it means the app's paste button can finish the job whatever the
        // system decides to do with the request below.
        UIPasteboard.general.url = shared

        guard open(deepLink) else {
            Self.log.error("Nothing would open \(CozyDeepLink.scheme, privacy: .public)://")
            await explain("Cozy Crumb wouldn't open. The link is copied — open the app and tap paste.")
            finish()
            return
        }

        // A beat before tearing the sheet down: completing the request the
        // instant after asking to launch can cancel the launch.
        try? await Task.sleep(for: .milliseconds(400))
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

    /// The responder chain goes first, and `extensionContext.open` is the
    /// fallback rather than the other way round. Two reasons: it is the one
    /// that actually works from a share sheet, and it is synchronous — waiting
    /// on `open`'s completion handler means waiting on a callback that, from a
    /// share extension, may never arrive at all. A sheet sitting there forever
    /// is indistinguishable from the extension doing nothing.
    private func open(_ url: URL) -> Bool {
        if openViaResponderChain(url) { return true }

        Self.log.info("No UIApplication in the responder chain; asking the extension context")

        guard let context = extensionContext else { return false }

        // Deliberately no completion handler: nothing here waits on it.
        context.open(url, completionHandler: nil)

        return true
    }

    /// The long-standing route out of a share extension. Officially only a
    /// Today widget may open a URL, so this finds the `UIApplication` up the
    /// responder chain and asks it directly.
    ///
    /// It goes through the ObjC selector rather than calling `UIApplication.open`,
    /// which is the point: the symbol never appears in the binary, so the
    /// extension still builds with `APPLICATION_EXTENSION_API_ONLY` on.
    private func openViaResponderChain(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self

        while let current = responder {
            if current.responds(to: selector) {
                _ = current.perform(selector, with: url)
                return true
            }
            responder = current.next
        }

        return false
    }

    // MARK: - When it doesn't work

    /// The only UI in here, and it only ever appears on a failure. A share
    /// extension that dismisses itself without a word leaves the user with no
    /// idea whether anything happened.
    private func explain(_ message: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)

            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                continuation.resume()
            })

            present(alert, animated: true)
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
