//
//  CozySegmentedControl.swift
//  Cozy Crumb
//
//  The app's segmented control. Two or three choices, side by side, one of
//  them filled in the accent.
//
//  It exists because `.pickerStyle(.segmented)` brings iOS's grey capsule with
//  it, which is the only grey thing in a warm app and the last piece of system
//  chrome on screens made entirely of stamped cards. Settings grew a private
//  copy of this control for exactly that reason; Groceries kept the system one
//  and looked like a different app at the top of the screen.
//
//  On the painted header slab the system control was worse than merely grey.
//  It styles itself from the *appearance*, so after dark it drew light-on-dark
//  chrome onto a slab that is pink in both — and neither the selected half nor
//  the unselected half could be read.
//
//  Which is why this takes a `Surface` rather than a set of colours: a control
//  that can stand on the page or on a slab has to be told which, and then it
//  cannot get the pairing wrong.
//

import SwiftUI

/// One choice in a `CozySegmentedControl`.
///
/// `nonisolated` on the type rather than on the init: the target defaults
/// types to MainActor, so the stored properties are isolated too, and a
/// nonisolated init cannot assign to them. Marking the whole struct is the
/// pattern the rest of the app already uses for plain value types — see
/// `ShoppingAmount`.
nonisolated struct CozySegment<Value: Hashable>: Identifiable {
    let value: Value
    let title: String

    var id: Value { value }

    init(value: Value, title: String) {
        self.value = value
        self.title = title
    }
}

struct CozySegmentedControl<Value: Hashable>: View {
    @Environment(\.accentPalette) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize

    /// What the whole control is called, for VoiceOver.
    let label: String
    /// The ground this is standing on. See `CozyColor.Surface`.
    var surface: CozyColor.Surface = .page
    let options: [CozySegment<Value>]
    @Binding var selection: Value

    var body: some View {
        // Side by side normally, stacked at an accessibility size.
        //
        // Two segments splitting a phone's width give each about 195pt, and
        // "Shopping" in bold caption at AX5 wants more than that. The AX5
        // capture of the Groceries header had the two titles touching with
        // "Shopping" running off the right edge of the screen — a control you
        // cannot read half of is worse than a tall one.
        //
        // `AnyLayout` rather than an `if`, so the segments keep their identity
        // across the switch: the selection stays put and the fill animates
        // instead of the whole control being rebuilt.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 6))
            : AnyLayout(HStackLayout(spacing: 6))

        return layout {
            ForEach(options) { option in
                segment(option)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func segment(_ option: CozySegment<Value>) -> some View {
        let isSelected = option.value == selection

        return Button {
            guard !isSelected else { return }
            selection = option.value
            Haptics.selection()
        } label: {
            Text(option.title)
                .font(CozyFont.caption.weight(.bold))
                // Selected is the accent with the ink that never moves;
                // unselected is the surface's own ink on the surface's own
                // well. Both pairs come from one place.
                .foregroundStyle(isSelected ? CozyColor.inkOnAccent : surface.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(minHeight: CozyMetrics.minimumTouchTarget)
                .background(isSelected ? accent.color : surface.well,
                            in: .rect(cornerRadius: 11, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.squishy)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview("Segmented") {
    @Previewable @State var units = MeasurementSystem.asWritten
    @Previewable @State var onSlab = MeasurementSystem.metric

    VStack(spacing: CozySpacing.xl) {
        CozySegmentedControl(
            label: "Units",
            options: MeasurementSystem.allCases.map {
                CozySegment(value: $0, title: $0.displayName)
            },
            selection: $units
        )

        CozySegmentedControl(
            label: "Units",
            surface: .onAccent,
            options: MeasurementSystem.allCases.map {
                CozySegment(value: $0, title: $0.displayName)
            },
            selection: $onSlab
        )
        .padding(CozySpacing.l)
        .background(AccentPalette.blush.color)
    }
    .padding()
    .background(CozyColor.cream)
}
