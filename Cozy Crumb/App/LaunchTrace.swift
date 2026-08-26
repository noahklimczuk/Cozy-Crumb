//
//  LaunchTrace.swift
//  Cozy Crumb
//
//  Breadcrumbs across the one stretch of the app nobody can debug from a
//  screenshot: the gap between tapping the icon and the first frame.
//
//  A launch that hangs there is invisible from outside. The app is still
//  showing the *system* launch screen, and because the target sets
//  `INFOPLIST_KEY_UILaunchScreen_Generation = YES`, that screen is a bare
//  `systemBackground` — pure black after dark. So a stalled launch and a
//  black screen are the same photograph, nothing has crashed so there is no
//  crash report, and the splash everyone expects to see never appears because
//  SwiftUI has not committed a frame yet.
//
//  Each stage says its name and how long it has been since the process
//  started. Whatever the last line in the log is, the stall is in the step
//  after it. Read them with Console.app on a Mac with the phone attached, or
//  `log stream --predicate 'subsystem == "ca.klimczuk.cozycrumb"'`.
//
//  These stay at `.notice`, which os_log persists to disk — so the log can be
//  read *after* a hang, which is the only time anyone will want it.
//

import Foundation
import os

nonisolated enum LaunchTrace {
    private static let lastStageKey = "launch.lastStageReached"
    private static let completedKey = "launch.completed"

    /// How far the *previous* launch got, or nil if it finished.
    ///
    /// The on-screen stage cannot report the step it dies on. Updating that
    /// label means hopping back to the main actor, and a launch that hangs
    /// hangs the main actor — so the last thing shown is the step *before* the
    /// one that stalled, and the real answer never reaches the screen.
    ///
    /// So each stage is also written straight to `UserDefaults`, which is
    /// synchronous and survives the process being killed. Force-quit a hung
    /// launch, open the app again, and the splash can say where the last
    /// attempt actually stopped. Read once here, before this launch starts
    /// overwriting it.
    static let previousLaunchStage: String? = {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: completedKey) { return nil }
        return defaults.string(forKey: lastStageKey)
    }()

    /// Called once the app is properly up, so a launch that worked leaves
    /// nothing behind for the next one to report.
    static func markLaunchComplete() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }
    /// Set on first use, which is the first line of `CozyCrumbApp.init()` —
    /// close enough to process start to be worth reading, and it costs nothing
    /// to be exact about what it measures rather than implying it is the
    /// process's own clock.
    private static let start = DispatchTime.now().uptimeNanoseconds

    /// Names a launch stage that has been *reached*. Call it after the work,
    /// not before, so the last line printed is the last thing that finished.
    static func mark(_ stage: String) {
        // `start` is read before the clock, and the order matters. It is a
        // lazy static, so the very first `mark` is what initialises it —
        // reading the clock first meant capturing a `now` from *before* the
        // baseline existed, and the subtraction then went negative. The first
        // line of every trace printed "18446744073709.5ms", which is what an
        // unsigned wrap looks like when a masking `&-` swallows it.
        let begin = start
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = now > begin ? Double(now - begin) / 1_000_000 : 0

        Log.app.notice(
            "launch: \(stage, privacy: .public) at \(String(format: "%.1fms", elapsed), privacy: .public)"
        )

        // Written synchronously, before anything can block, so the next launch
        // can report where this one stopped even if it never draws again.
        _ = previousLaunchStage
        let defaults = UserDefaults.standard
        defaults.set(stage, forKey: lastStageKey)
        defaults.set(false, forKey: completedKey)

    }
}

/// Whether the Cookbook should draw itself the simple way.
///
/// Latched on by a launch that did not finish, and off only when someone asks
/// for the full cookbook back. It has to latch rather than be recomputed each
/// time: a simplified launch *does* reach the end, which would clear the signal
/// and send the next launch straight back into whatever it could not survive.
/// Alternating between working and not working is not a recovery.
nonisolated enum CookbookSafeMode {
    private static let key = "cookbook.safeMode"

    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Called once at launch, before anything can hang.
    static func latchIfPreviousLaunchFailed() {
        guard LaunchTrace.previousLaunchStage != nil else { return }
        isOn = true
        Log.app.notice("Cookbook opening in simple mode: the last launch did not finish")
    }
}

