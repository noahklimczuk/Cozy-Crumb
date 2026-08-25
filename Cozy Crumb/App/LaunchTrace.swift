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
    /// Set on first use, which is the first line of `CozyCrumbApp.init()` —
    /// close enough to process start to be worth reading, and it costs nothing
    /// to be exact about what it measures rather than implying it is the
    /// process's own clock.
    private static let start = DispatchTime.now().uptimeNanoseconds

    private static var elapsedMilliseconds: Double {
        Double(DispatchTime.now().uptimeNanoseconds &- start) / 1_000_000
    }

    /// Names a launch stage that has been *reached*. Call it after the work,
    /// not before, so the last line printed is the last thing that finished.
    static func mark(_ stage: String) {
        let elapsed = String(format: "%.1fms", elapsedMilliseconds)
        Log.app.notice("launch: \(stage, privacy: .public) at \(elapsed, privacy: .public)")
    }
}
