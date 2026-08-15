//
//  ImportFlowView.swift
//  Cozy Crumb
//
//  The sheet the paste button opens: link entry, the wait, then review.
//

import Foundation
import SwiftData
import SwiftUI

struct ImportFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var existingRecipes: [Recipe]

    @State private var viewModel = ImportViewModel()

    /// Pre-filled when opened from a share or the pasteboard.
    var initialURL: URL?
    /// Skips straight to a blank draft.
    var startsInManualEntry = false

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.stage {
                case .entry: entry
                case .working: working
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
            if startsInManualEntry {
                viewModel.startManualEntry()
            } else if let initialURL {
                await viewModel.runImport(from: initialURL, existingRecipes: existingRecipes)
            }
        }
    }

    private var navigationTitle: String {
        switch viewModel.stage {
        case .entry: "Add a recipe"
        case .working: "Reading…"
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

                SquishyButton(title: "Get the recipe", systemImage: "sparkles") {
                    Task { await viewModel.importFromPastedText() }
                }
                .disabled(viewModel.urlText.trimmingCharacters(in: .whitespaces).isEmpty)

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
