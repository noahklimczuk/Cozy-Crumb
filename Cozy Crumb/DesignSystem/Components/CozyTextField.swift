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
        .background(CozyColor.card, in: .rect(cornerRadius: CozyRadius.button, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CozyRadius.button, style: .continuous)
                .strokeBorder(
                    isFocused ? accent.deep : CozyColor.outline,
                    lineWidth: isFocused ? CozyBorder.illustrative : CozyBorder.card
                )
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
