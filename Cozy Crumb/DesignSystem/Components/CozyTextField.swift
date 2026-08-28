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
    /// The ground this field is standing on, which decides both its fill and
    /// its ink. It used to take a `fill` colour while hard-coding the ink, and
    /// a field on an accent slab therefore drew `inkPrimary` — a colour that
    /// goes light after dark — on a near-white surface that does not. The
    /// Groceries add field was, on a dark phone, an empty white box.
    var surface: CozyColor.Surface = .page
    /// Explicitly main-actor: callers hand this closure work that touches
    /// the store, and a bare function type would strip the isolation.
    var onSubmit: (@MainActor () -> Void)?

    var body: some View {
        HStack(spacing: CozySpacing.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(surface.inkQuiet)
            }

            field
                .font(CozyFont.body)
                .foregroundStyle(surface.ink)
                .focused($isFocused)
                .submitLabel(submitLabel)
                .onSubmit { onSubmit?() }
                // The label moved into `prompt`, which VoiceOver does not read
                // as the field's name, so it is said here instead.
                .accessibilityLabel(placeholder)

            if showsClearButton, !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(surface.inkQuiet)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear text")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, CozySpacing.l)
        .frame(minHeight: CozyMetrics.minimumTouchTarget + 6)
        .background(surface.field, in: .rect(cornerRadius: CozyRadius.field, style: .continuous))
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

    /// The placeholder is styled explicitly rather than left to SwiftUI.
    ///
    /// A bare `TextField("…", text:)` draws its placeholder in the system's
    /// secondary colour, which follows the *appearance* — so on a surface that
    /// does not follow the appearance it goes light on near-white and the
    /// field reads as empty. `prompt:` is the only way to say what colour it
    /// actually is.
    @ViewBuilder
    private var field: some View {
        let prompt = Text(placeholder).foregroundStyle(surface.inkQuiet)

        if isSecure {
            SecureField("", text: $text, prompt: prompt)
        } else {
            TextField("", text: $text, prompt: prompt)
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
