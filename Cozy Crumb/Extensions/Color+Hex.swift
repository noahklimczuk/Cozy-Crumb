//
//  Color+Hex.swift
//  Cozy Crumb
//
//  Hex parsing and light/dark pairing. Colors are defined in code rather than
//  an asset catalog so the accent picker can re-tint the app at runtime.
//
//  Both initialisers are `nonisolated`. The target sets
//  SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, which would otherwise isolate
//  them — and every token in Theme.swift is a nonisolated static let whose
//  default value calls them, which is illegal from a nonisolated context.
//  They are pure value construction with no shared state, so isolation was
//  never meaningful here.
//

import Foundation
import SwiftUI
import UIKit

extension Color {
    /// Accepts "RRGGBB" or "AARRGGBB", with or without a leading "#".
    /// Falls back to clear on malformed input rather than trapping — a wrong
    /// colour is a visible bug, a crashed app is a worse one.
    nonisolated init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else {
            self = .clear
            return
        }

        let a, r, g, b: Double
        switch cleaned.count {
        case 6:
            a = 1
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
        case 8:
            a = Double((value & 0xFF00_0000) >> 24) / 255
            r = Double((value & 0x00FF_0000) >> 16) / 255
            g = Double((value & 0x0000_FF00) >> 8) / 255
            b = Double(value & 0x0000_00FF) / 255
        default:
            self = .clear
            return
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Pairs two colours into one that resolves against the active interface
    /// style. SwiftUI has no native equivalent outside an asset catalog.
    nonisolated init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
