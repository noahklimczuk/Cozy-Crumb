//
//  ShareViewController.swift
//  Cozy CrumbShare
//
//  The share sheet entry: send a link from Instagram, TikTok, Safari or
//  Messages into the importer.
//
//  This is the third attempt at the hand-off, and the first two both failed
//  the same way — invisibly. The extension found the link, asked the system to
//  open the app, the system declined, and the sheet dismissed without a word.
//  From the outside that is indistinguishable from the extension never having
//  run at all, which is why two rounds of fixing produced no information.
//
//  So the rule here is: something always comes up. The extension draws its own
//  page, in Cozy Crumb's colours, before it tries anything. If the app opens,
//  the page is never seen and the sheet tidies itself away. If the app does not
//  open, the page stays, says so, and offers the button again — with the link
//  already on the pasteboard, so the app's own paste button can finish the job
//  either way.
//
//  Why the extension cannot simply do the import itself: a free Apple ID has
//  no App Groups, so there is no container shared with the app to save a
//  recipe into. Opening the app is the only way a shared link becomes a saved
//  recipe, so the whole design hangs on that one call working.
//

import Foundation
import ObjectiveC
import UIKit
import UniformTypeIdentifiers
import os

/// `UIApplication.open(_:options:completionHandler:)`, redeclared.
///
/// Nothing conforms to this. It exists so the selector can be sent to the real
/// `UIApplication` without the extension's binary containing a symbol that app
/// extensions are not allowed to reference. The signature has to match the
/// Objective-C method exactly, or the message lands somewhere unpleasant.
/// The completion handler is declared `@MainActor` because that is where
/// UIKit calls it, and because it saves the closure below from having to cross
/// an isolation boundary to touch the page it is reporting on.
@objc private protocol ApplicationURLOpening {
    @objc(openURL:options:completionHandler:)
    func open(_ url: URL, options: [String: Any], completionHandler: (@MainActor (Bool) -> Void)?)
}

final class ShareViewController: UIViewController {

    private static let log = Logger(subsystem: "ca.klimczuk.cozycrumb", category: "share")

    private var sharedLink: URL?
    private var hasStarted = false

    private let titleLabel = UILabel()
    private let linkLabel = UILabel()
    private let statusLabel = UILabel()
    private let openButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        buildPage()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !hasStarted else { return }
        hasStarted = true

        Task { await start() }
    }

    private func start() async {
        guard let link = await sharedURL() else {
            Self.log.error("No link in the shared item")
            show(status: "There is no link in that to import.", canOpen: false)
            return
        }

        sharedLink = link
        linkLabel.text = Self.readable(link)

        // On the pasteboard before anything is attempted. The user just shared
        // a link, so finding it there is no surprise, and it means the app's
        // paste button can finish the job whatever the system does next.
        UIPasteboard.general.url = link

        guard let deepLink = CozyDeepLink.importing(link) else {
            Self.log.error("Could not build an import link")
            show(status: "That link can't be imported.", canOpen: false)
            return
        }

        show(status: "Opening Cozy Crumb…", canOpen: false)
        attemptOpen(deepLink)
    }

    // MARK: - Handing over

    /// Finds `UIApplication` up the responder chain and asks it to open the
    /// link, by selector rather than by name.
    ///
    /// The dance is forced. `UIApplication.open` is unavailable to app
    /// extensions at compile time, and the build system refuses to let an
    /// extension opt out — "Application extensions and any libraries they link
    /// to must be built with the APPLICATION_EXTENSION_API_ONLY build setting
    /// set to YES". Meanwhile the one call an extension *is* given,
    /// `extensionContext.open`, is documented for Today widgets and from a
    /// share sheet answers false or never answers at all. So the method is
    /// declared as a selector on a protocol nothing conforms to, and the real
    /// object is messaged through it — no `UIApplication` symbol in the binary,
    /// same method at the other end.
    private func attemptOpen(_ url: URL) {
        guard let responder = applicationResponder() else {
            // Nothing in the chain can open a URL. That is worth saying out
            // loud rather than failing into the same silence as before.
            Self.log.error("No UIApplication in the responder chain")
            extensionContext?.open(url, completionHandler: nil)
            show(status: "Tap to open Cozy Crumb and import this.", canOpen: true)
            return
        }

        let modern = NSSelectorFromString("openURL:options:completionHandler:")

        if responder.responds(to: modern) {
            // Our own declaration, so the completion handler is an ordinary
            // closure and can talk back to the page.
            let opener = unsafeBitCast(responder, to: (any ApplicationURLOpening).self)

            opener.open(url, options: [:]) { [weak self] opened in
                self?.openFinished(opened)
            }
            return
        }

        let legacy = NSSelectorFromString("openURL:")

        if responder.responds(to: legacy) {
            Self.log.info("Falling back to the deprecated openURL:")
            _ = responder.perform(legacy, with: url)
            // No answer to be had from this one, so leave the button up.
            show(status: "Asked iOS to open Cozy Crumb. Tap below if it didn't.", canOpen: true)
            return
        }

        Self.log.error("UIApplication answers to neither open selector")
        extensionContext?.open(url, completionHandler: nil)
        show(status: "Tap to open Cozy Crumb and import this.", canOpen: true)
    }

    private func openFinished(_ opened: Bool) {
        guard opened else {
            Self.log.error("The system would not open \(CozyDeepLink.scheme, privacy: .public)://")
            show(
                status: "Cozy Crumb wouldn't open on its own. The link is copied — tap below, or open the app and tap Paste.",
                canOpen: true
            )
            return
        }

        // The app is coming up. Tidy the sheet away behind it.
        finish()
    }

    /// `UIApplication` cannot be named in an extension, so it is found by class
    /// rather than by cast.
    private func applicationResponder() -> UIResponder? {
        guard let applicationClass = NSClassFromString("UIApplication") else { return nil }

        var responder: UIResponder? = self

        while let current = responder {
            if current.isKind(of: applicationClass) { return current }
            responder = current.next
        }

        return nil
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

    /// "instagram.com/reel/ABC" — enough to recognise what you shared, without
    /// a line of tracking parameters.
    private static func readable(_ url: URL) -> String {
        let host = (url.host() ?? "").replacingOccurrences(of: "www.", with: "")
        let path = url.path

        return path.isEmpty ? host : host + path
    }

    // MARK: - The page

    private func show(status: String, canOpen: Bool) {
        statusLabel.text = status
        openButton.isHidden = !canOpen
        closeButton.setTitle(canOpen ? "Not now" : "Close", for: .normal)
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func buildPage() {
        view.backgroundColor = CozyShare.cream

        let card = UIView()
        card.backgroundColor = CozyShare.card
        card.layer.cornerRadius = 24
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1.5
        card.layer.borderColor = CozyShare.outline.cgColor

        titleLabel.text = "Import to Cozy Crumb"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = CozyShare.inkPrimary
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        linkLabel.font = .systemFont(ofSize: 15, weight: .medium)
        linkLabel.textColor = CozyShare.inkSecondary
        linkLabel.textAlignment = .center
        linkLabel.numberOfLines = 2
        linkLabel.lineBreakMode = .byTruncatingMiddle

        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.textColor = CozyShare.inkSecondary
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.text = "Looking for a link…"

        openButton.setTitle("Open Cozy Crumb", for: .normal)
        openButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        openButton.setTitleColor(CozyShare.inkPrimary, for: .normal)
        openButton.backgroundColor = CozyShare.blush
        openButton.layer.cornerRadius = 20
        openButton.layer.cornerCurve = .continuous
        openButton.isHidden = true
        openButton.addAction(
            UIAction { [weak self] _ in self?.openAgain() },
            for: .touchUpInside
        )

        closeButton.setTitle("Close", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 16)
        closeButton.setTitleColor(CozyShare.inkSecondary, for: .normal)
        closeButton.addAction(
            UIAction { [weak self] _ in self?.finish() },
            for: .touchUpInside
        )

        let stack = UIStackView(arrangedSubviews: [titleLabel, linkLabel, statusLabel, openButton, closeButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        stack.setCustomSpacing(8, after: titleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        view.addSubview(card)

        NSLayoutConstraint.activate([
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),

            openButton.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    private func openAgain() {
        guard let link = sharedLink, let deepLink = CozyDeepLink.importing(link) else { return }

        show(status: "Opening Cozy Crumb…", canOpen: false)
        attemptOpen(deepLink)
    }
}

/// The handful of colours this page needs, written out rather than shared.
///
/// The app's design system is SwiftUI and reads its accent from the asset
/// catalog in the app target; dragging that into the extension to style one
/// card would be a poor trade. These are the same hex values as `CozyColor`.
private enum CozyShare {
    // Left on the target's default MainActor isolation on purpose: these are
    // only ever read while building the page, and a `nonisolated` static of a
    // class type is the sort of thing Swift 6 rightly objects to.
    static let cream = adaptive(light: 0xFFFBF7, dark: 0x2A2321)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x362D2A)
    static let blush = adaptive(light: 0xF8C8D4, dark: 0xE0A6B6)
    static let outline = adaptive(light: 0xE4D5CB, dark: 0x4A3E39)
    static let inkPrimary = adaptive(light: 0x6B5A52, dark: 0xF2E7E0)
    static let inkSecondary = adaptive(light: 0x826F64, dark: 0xC4B2A8)

    nonisolated static func adaptive(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            solid(traits.userInterfaceStyle == .dark ? dark : light)
        }
    }

    nonisolated static func solid(_ rgb: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
