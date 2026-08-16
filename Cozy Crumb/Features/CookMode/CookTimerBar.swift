//
//  CookTimerBar.swift
//  Cozy Crumb
//
//  Every running timer, in one strip that follows you around: across Cook
//  Mode's steps and along the bottom of Recipe Detail.
//
//  A timer you can't see is a timer you'll forget, so the bar shows all of
//  them rather than only the soonest — a roast, a pan of rice and a proving
//  loaf are a normal Sunday. Finished ones turn warm and say so until they're
//  dismissed, because a countdown that quietly reaches zero and vanishes is
//  worse than no timer at all.
//

import SwiftUI

struct CookTimerBar: View {
    @Environment(KitchenTimers.self) private var timers

    var body: some View {
        if timers.hasTimers {
            VStack(spacing: CozySpacing.s) {
                ForEach(timers.sortedTimers) { timer in
                    CookTimerRow(timer: timer)
                }
            }
            .padding(CozySpacing.m)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: CozyRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CozyRadius.card, style: .continuous)
                    .strokeBorder(CozyColor.outline, lineWidth: CozyBorder.card)
            }
            .cozyLiftShadow()
            .cozyAnimation(Motion.gentle, value: timers.timers.count)
        }
    }
}

/// One countdown, with the two controls a cook actually reaches for: pause,
/// and another minute.
struct CookTimerRow: View {
    @Environment(KitchenTimers.self) private var timers

    let timer: KitchenTimer

    private var isFinished: Bool { timer.hasFinished(at: timers.now) }

    var body: some View {
        HStack(spacing: CozySpacing.m) {
            countdown

            VStack(alignment: .leading, spacing: 1) {
                Text(timer.label)
                    .cozyText(CozyFont.caption)
                    .lineLimit(1)
                Text(isFinished ? "Time's up!" : timer.recipeTitle)
                    .cozyText(
                        CozyFont.caption2,
                        color: isFinished ? CozyColor.inkPrimary : CozyColor.inkSecondary
                    )
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isFinished {
                SquishyIconButton(systemImage: "checkmark", accessibilityLabel: "Dismiss this timer") {
                    timers.cancel(timer.id)
                }
            } else {
                SquishyIconButton(
                    systemImage: timer.isPaused ? "play.fill" : "pause.fill",
                    accessibilityLabel: timer.isPaused ? "Resume this timer" : "Pause this timer"
                ) {
                    if timer.isPaused {
                        timers.resume(timer.id)
                    } else {
                        timers.pause(timer.id)
                    }
                }
            }

            SquishyIconButton(
                systemImage: isFinished ? "arrow.clockwise" : "goforward.plus",
                accessibilityLabel: isFinished ? "Give it another minute" : "Add a minute"
            ) {
                timers.addMinutes(1, to: timer.id)
            }

            if !isFinished {
                SquishyIconButton(systemImage: "xmark", accessibilityLabel: "Stop this timer") {
                    timers.cancel(timer.id)
                }
            }
        }
        .padding(.vertical, CozySpacing.xs)
        .padding(.horizontal, CozySpacing.s)
        .background(
            isFinished ? CozyColor.warning.opacity(0.45) : Color.clear,
            in: .rect(cornerRadius: CozyRadius.chip, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(timer.label), \(accessibilitySummary)")
    }

    private var countdown: some View {
        ZStack {
            Circle()
                .strokeBorder(CozyColor.outline, lineWidth: 3)

            Circle()
                .trim(from: 0, to: timer.progress(at: timers.now))
                .stroke(
                    isFinished ? CozyColor.warning : CozyColor.blushDeep,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text(timer.display(at: timers.now))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(CozyColor.inkPrimary)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .padding(3)
        }
        .frame(width: 46, height: 46)
        .accessibilityHidden(true)
    }

    private var accessibilitySummary: String {
        if isFinished { return "time's up" }
        if timer.isPaused { return "paused with \(timer.display(at: timers.now)) left" }
        return "\(timer.display(at: timers.now)) left"
    }
}

/// The control on a step that has a stated time: starts the countdown, then
/// becomes the countdown.
struct CookTimerChip: View {
    @Environment(KitchenTimers.self) private var timers

    let step: RecipeStep
    let recipeTitle: String
    /// Which step this is, for the timer's label — "Step 3" reads better on a
    /// notification than the first few words of the instruction.
    let number: Int

    private var running: KitchenTimer? {
        timers.timer(forStep: step.id)
    }

    var body: some View {
        if let duration = step.durationDisplay, let seconds = step.durationSeconds {
            Button {
                if let running {
                    timers.cancel(running.id)
                } else {
                    timers.start(
                        seconds: seconds,
                        label: "Step \(number)",
                        recipeTitle: recipeTitle,
                        stepID: step.id
                    )
                }
            } label: {
                HStack(spacing: CozySpacing.xs) {
                    Image(systemName: running == nil ? "timer" : "stop.circle")
                        .font(.caption.weight(.semibold))

                    Text(label(duration: duration))
                        .font(CozyFont.caption)
                        .monospacedDigit()
                }
                .foregroundStyle(CozyColor.inkPrimary)
                .padding(.horizontal, CozySpacing.m)
                .frame(minHeight: CozyMetrics.minimumTouchTarget)
                .background(chipFill, in: .capsule)
                .overlay { Capsule().strokeBorder(CozyColor.outline, lineWidth: 1) }
                .contentShape(.capsule)
            }
            .buttonStyle(.squishy)
            .accessibilityLabel(accessibilityLabel(duration: duration))
        }
    }

    private var chipFill: Color {
        guard let running else { return CozyColor.butter }
        return running.hasFinished(at: timers.now) ? CozyColor.warning : CozyColor.blushSoft
    }

    private func label(duration: String) -> String {
        guard let running else { return duration }
        return running.hasFinished(at: timers.now)
            ? "Time's up!"
            : running.display(at: timers.now)
    }

    private func accessibilityLabel(duration: String) -> String {
        guard let running else { return "Start a \(duration) timer" }
        return running.hasFinished(at: timers.now)
            ? "Time's up. Tap to clear this timer"
            : "\(running.display(at: timers.now)) left. Tap to stop this timer"
    }
}

#Preview("Timer bar") {
    let timers = KitchenTimers(usesNotifications: false)

    return VStack {
        Spacer()
        CookTimerBar()
            .padding(CozySpacing.l)
    }
    .background { BlobBackground() }
    .environment(timers)
    .task {
        timers.start(seconds: 12 * 60, label: "Step 2", recipeTitle: "Banana Bread")
        timers.start(seconds: 3, label: "Step 5", recipeTitle: "Banana Bread")
    }
}
