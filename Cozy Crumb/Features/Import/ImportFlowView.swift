//
//  ImportFlowView.swift
//  Cozy Crumb
//
//  The sheet the paste button opens: link entry, the wait, then review.
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

struct ImportFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accentPalette) private var accent

    @Query private var existingRecipes: [Recipe]

    @State private var viewModel = ImportViewModel()

    /// Pre-filled when opened from a share or the pasteboard.
    var initialURL: URL?
    /// Skips straight to a blank draft.
    var startsInManualEntry = false
    /// Opens an already-saved recipe in the editor instead of importing.
    var editingRecipe: Recipe?
    /// External binding for paste link text from LibraryView
    var pasteLinkText: Binding<String>?

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.stage {
                case .entry: entry
                case .working: working
                case .needsCaption: captionPaste
                case .review: review
                case .failed(let error): failure(error)
                }
            }
            .background { BlobBackground() }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            if let editingRecipe {
                viewModel.startEditing(editingRecipe)
            } else if startsInManualEntry {
                viewModel.startManualEntry()
            } else if let initialURL {
                await viewModel.runImport(from: initialURL, existingRecipes: existingRecipes)
            } else if let pasteLinkText {
                // Copy pasteLinkText to viewModel.urlText when starting entry
                if !pasteLinkText.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    viewModel.urlText = pasteLinkText.wrappedValue
                }
            }
        }
    }

    private var navigationTitle: String {
        switch viewModel.stage {
        case .entry: "Add a recipe"
        case .working: "Reading…"
        case .needsCaption: "One more thing"
        case .review where viewModel.isEditingExisting: "Edit recipe"
        case .review: viewModel.duplicate == nil ? "Check it over" : "Already saved"
        case .failed: "Hmm"
        }
    }

    // MARK: - Entry

    private var entry: some View {
        ScrollView {
            VStack(spacing: CozySpacing.xl) {
                MascotView(pose: .idle, size: 104)
                    .padding(.top, CozySpacing.l)

                VStack(spacing: CozySpacing.s) {
                    Text("Paste a link")
                        .cozyText(CozyFont.title2)
                    Text("From a recipe site, a blog, anywhere. I'll pull out the ingredients and steps.")
                        .cozyText(CozyFont.subheadline, color: CozyColor.inkSecondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: CozySpacing.s) {
                    if let pasteLinkText {
                        CozyTextField(
                            placeholder: "https://…",
                            text: pasteLinkText,
                            systemImage: "link",
                            submitLabel: .go
                        ) {
                            Task { await viewModel.importFromPastedText(overrideText: pasteLinkText.wrappedValue) }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    } else {
                        CozyTextField(
                            placeholder: "https://…",
                            text: $viewModel.urlText,
                            systemImage: "link",
                            submitLabel: .go
                        ) {
                            Task { await viewModel.importFromPastedText() }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }

                    quickPasteButton
                }

                SquishyButton(title: "Get the recipe", systemImage: "sparkles") {
                    Task {
                        let targetText = pasteLinkText?.wrappedValue.isEmpty == false ? pasteLinkText!.wrappedValue : viewModel.urlText
                        await viewModel.importFromPastedText(overrideText: targetText)
                    }
                }
                .disabled(pasteLinkText?.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty ?? viewModel.urlText.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("Or type one in by hand") {
                    viewModel.startManualEntry()
                }
                .font(CozyFont.subheadline)
                .foregroundStyle(CozyColor.inkSecondary)
                .frame(minHeight: CozyMetrics.minimumTouchTarget)
            }
            .padding(CozySpacing.l)
        }
    }

    private var quickPasteButton: some View {
        Button {
            quickPaste()
        } label: {
            HStack(spacing: CozySpacing.xs) {
                Image(systemName: "doc.on.clipboard")
                    .font(.body.weight(.semibold))
                Text("Paste")
                    .font(CozyFont.callout.weight(.semibold))
            }
            .foregroundStyle(CozyColor.inkPrimary)
            .padding(.horizontal, CozySpacing.m)
            .frame(minHeight: CozyMetrics.minimumTouchTarget + 6)
            .background(accent.color, in: .rect(cornerRadius: CozyRadius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CozyRadius.button, style: .continuous)
                    .strokeBorder(accent.deep, lineWidth: 1.5)
            }
            .cozyLiftShadow()
        }
        .buttonStyle(.squishy)
        .accessibilityLabel("Quick paste from clipboard")
    }

    private func quickPaste() {
        let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? UIPasteboard.general.url?.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)

        if let pasted, !pasted.isEmpty {
            viewModel.urlText = pasted
            pasteLinkText?.wrappedValue = pasted
            Haptics.soft()
        } else {
            Haptics.notify(.warning)
        }
    }

    // MARK: - Working

    private var working: some View {
        CozyLoadingView(
            messages: [
                "Opening the page…",
                "Looking for the actual recipe…",
                "Skipping past the life story…",
                "Tidying up the ingredients…"
            ],
            pose: .peeking
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Caption paste

    /// The always-works path. Instagram and Facebook hide most posts behind a
    /// login, so when they give us nothing we ask rather than fail.
    private var captionPaste: some View {
        ScrollView {
            VStack(spacing: CozySpacing.l) {
                MascotView(pose: .peeking, size: 96)
                    .padding(.top, CozySpacing.m)

                VStack(spacing: CozySpacing.s) {
                    Text("This one's shy.")
                        .cozyText(CozyFont.title2)
                    Text(captionExplanation)
                        .cozyText(CozyFont.subheadline, color: CozyColor.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                CrumbCard {
                    VStack(alignment: .leading, spacing: CozySpacing.s) {
                        Text("Paste the caption")
                            .cozyText(CozyFont.headline)
                        TextField(
                            "Tap the post, copy the caption, paste it here…",
                            text: $viewModel.pastedCaption,
                            axis: .vertical
                        )
                        .font(CozyFont.body)
                        .foregroundStyle(CozyColor.inkPrimary)
                        .lineLimit(6...16)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SquishyButton(title: "Sort it out", systemImage: "sparkles") {
                    Task { await viewModel.parsePastedCaption() }
                }
                .disabled(viewModel.pastedCaption.trimmingCharacters(in: .whitespaces).count < 40)

                Button("Skip and type it in myself") {
                    viewModel.stage = .review
                }
                .font(CozyFont.subheadline)
                .foregroundStyle(CozyColor.inkSecondary)
                .frame(minHeight: CozyMetrics.minimumTouchTarget)
            }
            .padding(CozySpacing.l)
        }
    }

    private var captionExplanation: String {
        guard let platform = viewModel.socialPost?.platform else {
            return "Paste the caption and I'll pull the recipe out of it."
        }

        return switch platform {
        case .instagram, .facebook, .pinterest, .x, .threads, .reddit, .vimeo:
            "\(platform.displayName) keeps posts behind a login, so I can't read that one myself. Paste the caption and I'll do the rest."
        case .tiktok:
            "TikTok didn't share the caption for that one. Paste it and I'll do the rest."
        case .youtube:
            "I couldn't get enough from that video. Paste the description and I'll do the rest."
        }
    }

    // MARK: - Review

    private var review: some View {
        ImportReviewView(viewModel: viewModel) {
            viewModel.save(into: modelContext, updatingExisting: false)
            dismiss()
        } onUpdate: {
            viewModel.save(into: modelContext, updatingExisting: true)
            dismiss()
        }
    }

    // MARK: - Failure

    private func failure(_ error: CozyError) -> some View {
        VStack(spacing: CozySpacing.l) {
            EmptyStateView(
                title: "That didn't work.",
                message: error.friendlyMessage,
                pose: .idle
            )

            VStack(spacing: CozySpacing.m) {
                if error.isRetryable {
                    SquishyButton(title: "Try again", systemImage: "arrow.clockwise") {
                        Task { await viewModel.importFromPastedText() }
                    }
                }

                SquishyButton(title: "Type it in instead", emphasis: .secondary) {
                    viewModel.startManualEntry()
                }

                Button("Back") { viewModel.stage = .entry }
                    .font(CozyFont.subheadline)
                    .foregroundStyle(CozyColor.inkSecondary)
                    .frame(minHeight: CozyMetrics.minimumTouchTarget)
            }
            .padding(.horizontal, CozySpacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Import — entry") {
    ImportFlowView()
        .modelContainer(PreviewData.container)
}

#Preview("Import — manual") {
    ImportFlowView(startsInManualEntry: true)
        .modelContainer(PreviewData.container)
}
