//
//  CozyTextField.swift
//  Cozy Crumb
//
//  Text entry: the Library search field, manual grocery add, the Sous Chef
//  composer, and the secure API key field in Settings.
//

import SwiftUI

struct CozyTextField: View {
    @Environment(\.accentPalette) private var accent
    @FocusState private var isFocused: Bool

    let placeholder: String
    @Binding var text: String

    var systemImage: String?
    var isSecure: Bool = false
    var showsClearButton: Bool = true
    var submitLabel: SubmitLabel = .return
    /// White on a cream page; `surfaceOnAccent` for a field sitting on a
    /// header slab or one of the accent-ground screens.
    var fill: Color = CozyColor.card
    /// Explicitly main-actor: callers hand this closure work that touches
    /// the store, and a bare function type would strip the isolation.
    var onSubmit: (@MainActor () -> Void)?

    var body: some View {
        HStack(spacing: CozySpacing.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(CozyColor.inkSecondary)
            }

            field
                .font(CozyFont.body)
                .foregroundStyle(CozyColor.inkPrimary)
                .focused($isFocused)
                .submitLabel(submitLabel)
                .onSubmit { onSubmit?() }

            if showsClearButton, !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(CozyColor.inkSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear text")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, CozySpacing.l)
        .frame(minHeight: CozyMetrics.minimumTouchTarget + 6)
        .background(fill, in: .rect(cornerRadius: CozyRadius.field, style: .continuous))
        // Outlined only while focused. The resting hairline was doing the work
        // of separating a white field from a cream page; a field now sits on a
        // slab or a card that already separates it, and drawing the border
        // anyway put a box around every screen's first control.
        //
        // The focus ring stays — it is the only thing that says which field
        // the keyboard is talking to, and it is not decoration.
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: CozyRadius.field, style: .continuous)
                    .strokeBorder(accent.deep, lineWidth: CozyBorder.illustrative)
            }
        }
        .cozyAnimation(Motion.snappy, value: isFocused)
        .cozyAnimation(Motion.bouncy, value: text.isEmpty)
    }

    @ViewBuilder
    private var field: some View {
        if isSecure {
            SecureField(placeholder, text: $text)
        } else {
            TextField(placeholder, text: $text)
        }
    }
}

#Preview("Text fields") {
    @Previewable @State var search = ""
    @Previewable @State var filled = "tahini"
    @Previewable @State var key = "AIzaSyExample"

    VStack(spacing: CozySpacing.l) {
        CozyTextField(placeholder: "Search your cookbook", text: $search, systemImage: "magnifyingglass")
        CozyTextField(placeholder: "Search your cookbook", text: $filled, systemImage: "magnifyingglass")
        CozyTextField(placeholder: "Paste your API key", text: $key, systemImage: "key", isSecure: true)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CozyColor.cream)
}
