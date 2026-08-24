//
//  ImportFlowView.swift
//  Cozy Crumb
//
//  The sheet the paste button opens: link entry, the wait, then review.
//

import Foundation
import PhotosUI
import SwiftData
import SwiftUI

struct ImportFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accentPalette) private var accent

    @Query private var existingRecipes: [Recipe]

    @State private var viewModel = ImportViewModel()
    @State private var pickedMedia: [PhotosPickerItem] = []
    @State private var mediaProblem: String?

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
            .cozyScreenBackground()
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

    /// The system paste control, not a button that reads the pasteboard itself.
    ///
    /// Reading `UIPasteboard` in code is what puts up "Allow Paste?" — iOS asks
    /// every time, because the app is helping itself. A `PasteButton` *is* the
    /// permission: the tap that asks for the link is the tap that hands it
    /// over, so the link lands in the field and nothing interrupts.
    ///
    /// The trade is that the control belongs to the system. The word "Paste"
    /// and the clipboard glyph are fixed; the shape and tint are ours. iOS also
    /// greys it out by itself when there's nothing to paste, which is why
    /// there's no empty-clipboard case to handle any more.
    private var quickPasteButton: some View {
        PasteButton(payloadType: String.self) { items in
            paste(items.first)
        }
        .labelStyle(.titleAndIcon)
        .buttonBorderShape(.roundedRectangle(radius: CozyRadius.button))
        .tint(accent.color)
        .frame(minHeight: CozyMetrics.minimumTouchTarget + 6)
        .accessibilityLabel("Paste a link from the clipboard")
    }

    private func paste(_ text: String?) {
        let pasted = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pasted.isEmpty else {
            Haptics.notify(.warning)
            return
        }

        viewModel.urlText = pasted
        pasteLinkText?.wrappedValue = pasted
        Haptics.soft()
    }

    // MARK: - Working

    private var working: some View {
        CozyLoadingView(
            messages: [
                "Opening the page…",
                "Looking for the actual recipe…",
                "Skipping past the life story…",
                "Watching the video, if there is one…",
                "Reading what's written on screen…",
                "Tidying up the ingredients…"
            ],
            pose: .peeking
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Caption paste

    /// The always-works path, for the posts where the recipe was never written
    /// down: the video itself, screenshots of it, or the caption by hand.
    private var captionPaste: some View {
        ScrollView {
            VStack(spacing: CozySpacing.l) {
                MascotView(pose: .peeking, size: 96)
                    .padding(.top, CozySpacing.m)

                VStack(spacing: CozySpacing.s) {
                    Text("This one's shy.")
                        .cozyText(CozyFont.title2)
                    Text(viewModel.captionPromptReason ?? captionExplanation)
                        .cozyText(CozyFont.subheadline, color: CozyColor.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                mediaCard

                CrumbCard {
                    VStack(alignment: .leading, spacing: CozySpacing.s) {
                        Text("Or paste the caption")
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
        .onChange(of: pickedMedia) { _, items in
            guard !items.isEmpty else { return }
            Task { await handlePickedMedia(items) }
        }
    }

    /// The route that works when the platform gives us nothing at all: the user
    /// saves the reel (or screenshots it) and hands it over. The Sous Chef
    /// reads on-screen text and, for a video, listens to the narration too.
    private var mediaCard: some View {
        // `PhotosPicker` takes its label as a Sendable closure, so the accent
        // has to be read out here — inside the closure it's a main-actor
        // reference from a nonisolated context.
        let buttonFill = accent.color
        let buttonEdge = accent.deep

        return CrumbCard(fill: accent.soft) {
            VStack(alignment: .leading, spacing: CozySpacing.s) {
                Text("Give me the video")
                    .cozyText(CozyFont.headline)

                Text("Most reels keep the recipe in the video rather than the caption. Save it to your camera roll — or screenshot the ingredients and method — and I'll read it off that.")
                    .cozyText(CozyFont.subheadline, color: CozyColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let mediaProblem {
                    Text(mediaProblem)
                        .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                PhotosPicker(
                    selection: $pickedMedia,
                    maxSelectionCount: 6,
                    matching: .any(of: [.videos, .images])
                ) {
                    HStack(spacing: CozySpacing.s) {
                        Image(systemName: "photo.badge.plus")
                            .font(.body.weight(.semibold))
                        Text("Choose video or screenshots")
                            .font(CozyFont.headline)
                    }
                    .foregroundStyle(CozyColor.inkPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: CozyMetrics.minimumTouchTarget + 6)
                    .background(buttonFill, in: .rect(cornerRadius: CozyRadius.button, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: CozyRadius.button, style: .continuous)
                            .strokeBorder(buttonEdge, lineWidth: 1.5)
                    }
                }
                .disabled(!viewModel.isAIAvailable)

                if !viewModel.isAIAvailable {
                    Text("Add your Gemini key in Settings to use this.")
                        .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A video beats stills every time — it carries the audio, and the recipe
    /// is often only ever spoken. So if the user picked one, that's what we
    /// send, whatever else came with it.
    private func handlePickedMedia(_ items: [PhotosPickerItem]) async {
        mediaProblem = nil
        pickedMedia = []

        for item in items {
            if let movie = try? await item.loadTransferable(type: PickedMovie.self) {
                await viewModel.importPickedVideo(at: movie.url)
                return
            }
        }

        var images: [Data] = []

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let jpeg = ImageProcessor.downscaledJPEG(from: data) else { continue }
            images.append(jpeg)
        }

        guard !images.isEmpty else {
            mediaProblem = "I couldn't open that one. A screenshot or a saved video works best."
            return
        }

        await viewModel.importPickedImages(images)
    }

    private var captionExplanation: String {
        guard let platform = viewModel.socialPost?.platform else {
            return "Give me the video or the caption, and I'll pull the recipe out of it."
        }

        return switch platform {
        case .instagram, .facebook, .pinterest, .x, .threads, .reddit, .vimeo:
            "\(platform.displayName) keeps posts behind a login, and the caption didn't have the recipe in it. Hand me the video or a screenshot instead."
        case .tiktok:
            "TikTok didn't give me a recipe for that one — the caption's just the hook. Hand me the video or a screenshot instead."
        case .youtube:
            "I couldn't get enough from that video. Paste the description, or send me the video itself."
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
