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

    private static let streakKey = "launch.incompleteStreak"

    /// How many launches in a row have failed to finish.
    ///
    /// Read once, before this launch touches it, for the same reason
    /// `previousLaunchStage` is.
    static let incompleteStreak: Int = {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: completedKey) { return 0 }
        // The previous launch did not finish, so it counts as one on top of
        // whatever streak it inherited.
        return defaults.integer(forKey: streakKey) + 1
    }()

    /// Called once the app is properly up, so a launch that worked leaves
    /// nothing behind for the next one to report.
    ///
    /// "Properly up" means the tab shell is on screen and usable. It used to
    /// mean the seven launch maintenance passes had all finished, which is a
    /// different and much later thing — and getting that wrong is what made
    /// the app keep opening in simple mode. Backgrounding the app during the
    /// splash, or force-quitting it, or iOS reclaiming it while it sat behind
    /// something else, all left `completed` false; the next launch read that
    /// as a failed launch and latched. Those are not failed launches. They are
    /// Tuesday.
    ///
    /// The passes are maintenance, and maintenance not finishing is not a
    /// launch that did not happen. What this still catches is the case it was
    /// written for: a hang while the Cookbook's body is being evaluated, which
    /// happens before the shell can appear.
    static func markLaunchComplete() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: completedKey)
        defaults.set(0, forKey: streakKey)
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
        _ = armLaunch
        UserDefaults.standard.set(stage, forKey: lastStageKey)
    }

    /// Says "a launch is under way, and it has not finished" — exactly once
    /// per process.
    ///
    /// This used to be part of `mark`, which meant every stage cleared the
    /// finished flag. That was harmless while completion was recorded last,
    /// and wrong the moment it moved earlier: the shell would appear, mark the
    /// launch complete, and then the very next maintenance pass would call
    /// `mark` and unset it again. Every launch therefore still looked failed,
    /// the streak still climbed, and the app still opened in simple mode — the
    /// fix for that had been written and then immediately undone, one line
    /// later, by this.
    ///
    /// A lazy static runs once and is thread-safe, which is the whole
    /// requirement: arm at the first mark, and never touch it again.
    private static let armLaunch: Void = {
        // Both of these read the values the *previous* launch left behind, so
        // they have to be forced before anything below overwrites them.
        _ = previousLaunchStage
        let streak = incompleteStreak

        let defaults = UserDefaults.standard
        defaults.set(false, forKey: completedKey)
        defaults.set(streak, forKey: streakKey)
    }()

    /// Wipes what previous launches recorded about themselves.
    ///
    /// For when the rule that produced those records has changed and they no
    /// longer mean anything — see `CookbookSafeMode.clearIfSetUnderAnOlderRule`.
    /// Call before anything reads `incompleteStreak` or `previousLaunchStage`,
    /// which is why it happens at the very top of `openStore`.
    static func forgetPreviousLaunches() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: completedKey)
        defaults.set(0, forKey: streakKey)
        defaults.removeObject(forKey: lastStageKey)
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
    private static let ruleKey = "cookbook.safeModeRule"

    /// Bumped whenever the rule that latches this changes.
    ///
    /// A latched flag only means something under the rule that set it. This
    /// one was set by a rule that treated a single interrupted launch as a
    /// failure, which is a thing that happens to everybody — so the flag on
    /// disk right now says almost nothing, and anybody carrying it would go on
    /// seeing "the last launch didn't finish" forever unless they found the
    /// button. Clearing it once on upgrade is the only way the fix reaches the
    /// people it was written for. If the next launch really does fail twice,
    /// it latches again on its own.
    /// Rule 3, not 2, and for the same reason twice over: under rule 2 every
    /// stage mark still cleared the finished flag, so the streak went on
    /// climbing over launches that had in fact succeeded. Those counts are as
    /// meaningless as the flag, so the reset drops them too.
    private static let currentRule = 3

    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Drops a latch set under an older rule. Call before reading `isOn`.
    static func clearIfSetUnderAnOlderRule() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: ruleKey) < currentRule else { return }
        defaults.set(currentRule, forKey: ruleKey)

        // The streak goes with the flag: it was counted by the same broken
        // rule, and leaving it behind would re-latch on the very next launch.
        LaunchTrace.forgetPreviousLaunches()

        guard isOn else { return }
        isOn = false
        Log.app.notice("Cleared simple mode: it was latched under an older rule")
    }

    /// Two in a row, not one.
    ///
    /// One launch that did not finish is ordinary life: the app was
    /// backgrounded during the splash, or force-quit, or reclaimed by iOS
    /// while it sat behind something else. Latching on a single one meant the
    /// app kept greeting people with "the last launch didn't finish" and a
    /// stripped-back list, when nothing had gone wrong at all — and the only
    /// way out was a button most people would never think to press.
    ///
    /// Two consecutive failures is a pattern, and a pattern is what simple
    /// mode exists for.
    private static let threshold = 2

    /// Called once at launch, before anything can hang.
    static func latchIfPreviousLaunchFailed() {
        let streak = LaunchTrace.incompleteStreak
        guard streak >= threshold else { return }
        isOn = true
        Log.app.notice(
            "Cookbook opening in simple mode: \(streak, privacy: .public) launches in a row did not finish"
        )
    }
}

