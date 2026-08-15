//
//  Haptics.swift
//  Cozy Crumb
//
//  Haptics with the global toggle from §8.12. Every tappable element routes
//  through here rather than constructing feedback generators inline.
//

import Foundation
import SwiftUI
import UIKit

@MainActor
enum Haptics {
    /// Backing store for the Settings toggle. Defaults to on.
    static var isEnabled: Bool {
        get {
            // `object(forKey:)` so an unset value reads as true rather than false.
            UserDefaults.standard.object(forKey: CozyDefaultsKey.hapticsEnabled) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: CozyDefaultsKey.hapticsEnabled)
        }
    }

    /// The standard press feedback used by every squishy control.
    static func soft() {
        impact(.soft)
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

extension EnvironmentValues {
    @Entry var hapticsEnabled: Bool = true
}
