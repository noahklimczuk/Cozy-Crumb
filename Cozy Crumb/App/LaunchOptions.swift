//
//  LaunchOptions.swift
//  Cozy Crumb
//
//  Lets a launch say which screen to open on and whether to fill the store
//  with sample recipes. It exists so CI can photograph the app.
//
//  The problem it solves is that nobody working on this can see it. A layout
//  bug on the Groceries tab is invisible from a Linux checkout and invisible
//  in a build log, so it gets diagnosed by reading code and guessing at pixel
//  positions — which is how the tab bar ended up eating the bottom of every
//  scroll view, and how a hunt for a drop shadow on text spent a day looking
//  at the wrong gradient. A screenshot of every screen on every push turns all
//  of that from an argument into a photograph.
//
//  `UserDefaults` reads `-key value` launch arguments into its argument domain
//  automatically, so `simctl launch … -cozyStartTab groceries` needs no
//  parsing here and leaves nothing behind: the argument domain is per-process,
//  never written to disk, and empty in every launch that did not pass one.
//  A build with no arguments therefore behaves exactly as if this file did not
//  exist, which is the only way a debugging affordance is allowed to ship.
//

import Foundation

nonisolated enum LaunchOptions {

    /// The tab to open on, or nil to open where the app normally would.
    static var startTab: CozyTab? {
        guard let raw = UserDefaults.standard.string(forKey: "cozyStartTab") else { return nil }
        return CozyTab(rawValue: raw)
    }

    /// Whether to fill an empty store with the sample recipes.
    ///
    /// A fresh install opens empty, which is right for a person and useless
    /// for a screenshot: an empty Cookbook cannot show a card layout bug. This
    /// only ever adds to a store that has no recipes at all, so it can never
    /// interfere with somebody's actual cookbook even if the argument is
    /// passed by accident.
    static var wantsSampleData: Bool {
        UserDefaults.standard.bool(forKey: "cozySampleData")
    }

    /// Cuts the cupcake greeting short, so a screenshot taken two seconds in
    /// is of the app rather than of the splash.
    static var skipsSplash: Bool {
        UserDefaults.standard.bool(forKey: "cozySkipSplash")
    }

    /// Draws a red edge where a tab's content ends, with the insets behind it.
    ///
    /// See `TabClearanceRuler`. "The scrolling is cut off" has been reported
    /// three times and answered wrong twice, both times from reasoning about
    /// modifiers rather than from a measurement — and the ordinary captures
    /// cannot settle it, because a screen photographed at rest at the top
    /// looks identical whether its bottom inset is right or twice too big.
    static var showsLayoutRuler: Bool {
        UserDefaults.standard.bool(forKey: "cozyLayoutRuler")
    }
}
