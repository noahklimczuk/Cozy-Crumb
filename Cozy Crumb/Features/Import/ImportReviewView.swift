//
//  ImportReviewView.swift
//  Cozy Crumb
//
//  The mandatory, non-skippable review step (§5.2). Everything the parser
//  produced is editable here, and nothing is written to the library until the
//  user presses save.
//
//  This screen is also the manual-entry form — a blank draft and a parsed one
//  are the same document, so there is only one editor to maintain.
//

import Foundation
import PhotosUI
import SwiftUI
import UIKit
import SwiftData
// This screen owns SwiftUI bindings and mutable view-model state. Keep its
// helper views on the UI actor rather than relying on inferred isolation.
@MainActor
struct ImportReviewView: View {
    @Bindable var viewModel: ImportViewModel

    let onSave: () -> Void
    let onUpdate: () -> Void

    @State private var pickedPhoto: PhotosPickerItem?

    @MainActor
    var body: some View {
        List {
            bannerSection
            heroSection
            detailsSection
            ingredientsSection
            stepsSection
            saveSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .onChange(of: pickedPhoto) { _, item in
            Task { await loadPhoto(item) }
        }
    }

    // MARK: - Banners

    @MainActor
    @ViewBuilder
    private var bannerSection: some View {
        if viewModel.duplicate != nil {
            Section {
                banner(
                    text: "You've already saved this one. Update it, or keep both?",
                    tint: CozyColor.sky
                )
            }
            .listRowBackground(Color.clear)
        }

        if viewModel.didFallBackToManual {
            Section {
                banner(
                    text: viewModel.isSocialSource
                        ? "This one's shy — social posts don't share their recipes. Type what you can and I'll keep it safe."
                        : "I couldn't find a recipe on that page. Here's what I did get — fill in the rest?",
                    tint: CozyColor.warning
                )
            }
            .listRowBackground(Color.clear)
        } else if viewModel.showsConfidenceBanner {
            Section {
                banner(text: "I did my best guess here — worth a quick look.", tint: CozyColor.warning)
            }
            .listRowBackground(Color.clear)
        }
    }

    @MainActor
    private func banner(text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: CozySpacing.s) {
            MascotView(pose: .idle, size: 34)
            Text(text)
                .cozyText(CozyFont.caption, color: CozyColor.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(CozySpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.45), in: .rect(cornerRadius: CozyRadius.chip, style: .continuous))
    }

    // MARK: - Hero

    @MainActor
    private var heroSection: some View {
        // PhotosPicker builds its label from a nonisolated closure. Take the
        // main-actor state snapshot before entering that closure.
        let heroImageData = viewModel.heroImageData

        Section {
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                ZStack {
                    if let data = heroImageData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [CozyColor.peach, CozyColor.blush],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        VStack(spacing: CozySpacing.xs) {
                            Image(systemName: "photo.badge.plus")
                                .font(.title)
                            Text("Add a photo")
                                .cozyText(CozyFont.caption)
                        }
                        .foregroundStyle(CozyColor.inkPrimary.opacity(0.6))
                    }
                }
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: CozyRadius.image, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(heroImageData == nil ? "Add a photo" : "Replace the photo")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: CozySpacing.s, leading: 0, bottom: CozySpacing.s, trailing: 0))
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self) else { return }

        viewModel.heroImageData = ImageProcessor.downscaledJPEG(from: data)
    }

    // MARK: - Details

    @MainActor
    private var detailsSection: some View {
        Section("The basics") {
            TextField("Recipe name", text: $viewModel.draft.title)
                .font(CozyFont.bodyEmphasis)

            TextField("A line about it (optional)", text: summaryBinding, axis: .vertical)
                .font(CozyFont.body)
                .lineLimit(1...3)

            Stepper(
                "Serves \(viewModel.draft.servings ?? 4)",
                value: servingsBinding,
                in: 1...99
            )
            .font(CozyFont.body)

            HStack {
                Text("Prep").font(CozyFont.body)
                Spacer()
                minutesField(binding: prepBinding)
            }

            HStack {
                Text("Cook").font(CozyFont.body)
                Spacer()
                minutesField(binding: cookBinding)
            }
        }
        .foregroundStyle(CozyColor.inkPrimary)
    }

    @MainActor
    private func minutesField(binding: Binding<String>) -> some View {
        HStack(spacing: 4) {
            TextField("–", text: binding)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
            Text("min")
                .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
        }
    }

    // MARK: - Ingredients

    @MainActor
    private var ingredientsSection: some View {
        Section {
            ForEach($viewModel.draft.ingredients) { $ingredient in
                TextField("2 cups flour", text: $ingredient.rawText, axis: .vertical)
                    .font(CozyFont.body)
                    .foregroundStyle(ingredient.isSectionHeader ? CozyColor.inkSecondary : CozyColor.inkPrimary)
            }
            .onDelete { offsets in
                viewModel.draft.ingredients.remove(atOffsets: offsets)
            }
            .onMove { source, destination in
                viewModel.draft.ingredients.move(fromOffsets: source, toOffset: destination)
            }

            Button {
                viewModel.addIngredient()
            } label: {
                Label("Add an ingredient", systemImage: "plus.circle")
                    .font(CozyFont.body)
            }
        } header: {
            Text("Ingredients")
        } footer: {
            Text("Write them however you like — I'll re-read the amounts when you save.")
        }
    }

    // MARK: - Steps

    @MainActor
    private var stepsSection: some View {
        Section {
            // Enumerating a binding collection does not give a usable id, so
            // the step number is looked up from the draft instead.
            ForEach($viewModel.draft.steps) { $step in
                let number = (viewModel.draft.steps.firstIndex(where: { $0.id == step.id }) ?? 0) + 1

                VStack(alignment: .leading, spacing: 4) {
                    Text("Step \(number)")
                        .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)

                    TextField("What happens here?", text: $step.text, axis: .vertical)
                        .font(CozyFont.body)
                        .lineLimit(1...8)

                    if let duration = DurationParser.display(seconds: step.durationSeconds) {
                        PillTag(text: duration, systemImage: "timer", tint: CozyColor.butter)
                    }
                }
                .padding(.vertical, 2)
            }
            .onDelete { offsets in
                viewModel.draft.steps.remove(atOffsets: offsets)
            }
            .onMove { source, destination in
                viewModel.draft.steps.move(fromOffsets: source, toOffset: destination)
            }

            Button {
                viewModel.addStep()
            } label: {
                Label("Add a step", systemImage: "plus.circle")
                    .font(CozyFont.body)
            }
        } header: {
            Text("Method")
        }
    }

    // MARK: - Save

    @MainActor
    private var saveSection: some View {
        Section {
            if viewModel.duplicate != nil {
                SquishyButton(title: "Update the saved one", systemImage: "arrow.triangle.2.circlepath") {
                    onUpdate()
                }
                .disabled(!viewModel.canSave)

                SquishyButton(title: "Keep both", emphasis: .secondary) {
                    onSave()
                }
                .disabled(!viewModel.canSave)
            } else {
                SquishyButton(title: "Save to my cookbook", systemImage: "checkmark") {
                    onSave()
                }
                .disabled(!viewModel.canSave)
            }

            if !viewModel.canSave {
                Text("Needs a name and at least one ingredient or step.")
                    .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
            }
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Bindings

    @MainActor
    private var summaryBinding: Binding<String> {
        Binding(
            get: { viewModel.draft.summary ?? "" },
            set: { viewModel.draft.summary = $0.isEmpty ? nil : $0 }
        )
    }

    @MainActor
    private var servingsBinding: Binding<Int> {
        Binding(
            get: { viewModel.draft.servings ?? 4 },
            set: { viewModel.draft.servings = $0 }
        )
    }

    @MainActor
    private var prepBinding: Binding<String> {
        minutesBinding(\.prepMinutes)
    }

    @MainActor
    private var cookBinding: Binding<String> {
        minutesBinding(\.cookMinutes)
    }

    @MainActor
    private func minutesBinding(_ keyPath: WritableKeyPath<ImportedRecipe, Int?>) -> Binding<String> {
        Binding(
            get: { viewModel.draft[keyPath: keyPath].map(String.init) ?? "" },
            set: { viewModel.draft[keyPath: keyPath] = Int($0) }
        )
    }
}

#Preview("Review") {
    @Previewable @State var viewModel: ImportViewModel = {
        let model = ImportViewModel()
        model.draft = ImportedRecipe(
            title: "Brown Butter Banana Bread",
            summary: "A loaf that makes the whole flat smell like a bakery.",
            servings: 8,
            prepMinutes: 20,
            cookMinutes: 55,
            ingredients: [
                IngredientLineParser.parse("115 g unsalted butter", order: 0),
                IngredientLineParser.parse("3 very ripe bananas", order: 1),
                IngredientLineParser.parse("150 g light brown sugar", order: 2)
            ],
            steps: [
                ImportedStep(text: "Brown the butter and let it cool for 10 minutes.", durationSeconds: 600),
                ImportedStep(text: "Mash the bananas into the butter.")
            ],
            confidence: 0.7
        )
        return model
    }()

    NavigationStack {
        ImportReviewView(viewModel: viewModel, onSave: {}, onUpdate: {})
            .background { BlobBackground() }
    }
    .modelContainer(PreviewData.container)
}
