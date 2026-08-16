//
//  AIKeySettingsView.swift
//  Cozy Crumb
//
//  Bring-your-own-key setup. The key lives in the Keychain and never leaves
//  the device except as a header on a request to Google.
//

import Foundation
import SwiftUI

@Observable
@MainActor
final class AIKeySettingsViewModel {

    enum TestState: Equatable {
        case idle
        case testing
        case passed
        case failed(CozyError)
    }

    var draftKey = ""
    var testState: TestState = .idle
    var savedKeyPreview: String?

    private let keychain: KeychainStore
    private let client: GeminiClient

    init(keychain: KeychainStore = .shared, client: GeminiClient = GeminiClient()) {
        self.keychain = keychain
        self.client = client
        refresh()
    }

    var hasSavedKey: Bool {
        savedKeyPreview != nil
    }

    var canSave: Bool {
        draftKey.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20
    }

    func refresh() {
        savedKeyPreview = keychain.string(for: .geminiAPIKey).map { KeychainStore.masked($0) }
    }

    func save() {
        let trimmed = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        keychain.set(trimmed, for: .geminiAPIKey)
        draftKey = ""
        testState = .idle
        refresh()
    }

    func remove() {
        keychain.delete(.geminiAPIKey)
        draftKey = ""
        testState = .idle
        refresh()
    }

    /// Smallest possible round trip that proves the key works.
    func testConnection(model: GeminiModel) async {
        testState = .testing

        let outcome = await client.generate(
            model: model,
            systemInstruction: nil,
            parts: [.text("Reply with the single word: ready")],
            temperature: 0,
            maxOutputTokens: 16,
            timeout: 20
        )

        testState = switch outcome {
        case .success: .passed
        case .failure(let error): .failed(error)
        }
    }
}

struct AIKeySettingsView: View {
    @AppStorage(CozyDefaultsKey.geminiModel) private var modelRaw = GeminiModel.balanced.rawValue

    @State private var viewModel = AIKeySettingsViewModel()

    private var model: GeminiModel {
        GeminiModel(rawValue: modelRaw) ?? .balanced
    }

    var body: some View {
        ScrollView {
            VStack(spacing: CozySpacing.l) {
                intro
                keyCard
                if viewModel.hasSavedKey {
                    modelCard
                }
                privacyNote
            }
            .padding(CozySpacing.l)
        }
        .background { BlobBackground() }
        .navigationTitle("Sous Chef")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.refresh() }
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(spacing: CozySpacing.s) {
            MascotView(pose: viewModel.hasSavedKey ? .cooking : .sleeping, size: 92)
            Text(viewModel.hasSavedKey ? "The Sous Chef is awake." : "The Sous Chef is asleep.")
                .cozyText(CozyFont.title2)
            Text(viewModel.hasSavedKey
                 ? "Social imports, fridge photos and chat are all ready to go."
                 : "Add a Google AI Studio key and I can read social posts, watch cooking videos, and answer questions.")
                .cozyText(CozyFont.subheadline, color: CozyColor.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var keyCard: some View {
        CrumbCard {
            VStack(alignment: .leading, spacing: CozySpacing.m) {
                if let preview = viewModel.savedKeyPreview {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Key saved")
                                .cozyText(CozyFont.bodyEmphasis)
                            Text(preview)
                                .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                                .monospaced()
                        }
                        Spacer()
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(CozyColor.success)
                    }
                }

                CozyTextField(
                    placeholder: viewModel.hasSavedKey ? "Replace the key" : "Paste your key",
                    text: $viewModel.draftKey,
                    systemImage: "key",
                    isSecure: true
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                SquishyButton(title: viewModel.hasSavedKey ? "Replace key" : "Save key", systemImage: "checkmark") {
                    viewModel.save()
                }
                .disabled(!viewModel.canSave)

                if viewModel.hasSavedKey {
                    SquishyButton(title: "Test connection", systemImage: "bolt", emphasis: .secondary) {
                        Task { await viewModel.testConnection(model: model) }
                    }
                    .disabled(viewModel.testState == .testing)

                    testResult

                    Button("Remove key", role: .destructive) {
                        viewModel.remove()
                    }
                    .font(CozyFont.subheadline)
                    .frame(minHeight: CozyMetrics.minimumTouchTarget)
                }

                if let url = GeminiEndpoint.apiKeyPage {
                    Link(destination: url) {
                        HStack(spacing: CozySpacing.xs) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Get a free key at aistudio.google.com")
                        }
                        .font(CozyFont.caption)
                    }
                    .frame(minHeight: CozyMetrics.minimumTouchTarget)
                }

                Text("The free tier is generous enough for personal use.")
                    .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var testResult: some View {
        switch viewModel.testState {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: CozySpacing.s) {
                ProgressView()
                Text("Knocking…")
                    .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
            }
        case .passed:
            Label("All good — the Sous Chef says hello.", systemImage: "checkmark.circle.fill")
                .font(CozyFont.caption)
                .foregroundStyle(CozyColor.inkPrimary)
        case .failed(let error):
            Label(error.friendlyMessage, systemImage: "exclamationmark.circle.fill")
                .font(CozyFont.caption)
                .foregroundStyle(CozyColor.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modelCard: some View {
        CrumbCard {
            VStack(alignment: .leading, spacing: CozySpacing.s) {
                Text("Model")
                    .cozyText(CozyFont.bodyEmphasis)

                Picker("Model", selection: $modelRaw) {
                    ForEach(GeminiModel.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text(model.explanation)
                    .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)

                if !model.supportsVideo {
                    Text("Speedy can't watch videos — YouTube imports will fall back to the description.")
                        .cozyText(CozyFont.caption, color: CozyColor.inkPrimary)
                        .padding(CozySpacing.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CozyColor.warning.opacity(0.4),
                                    in: .rect(cornerRadius: CozyRadius.chip, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var privacyNote: some View {
        CrumbCard(fill: CozyColor.creamDeep) {
            VStack(alignment: .leading, spacing: CozySpacing.xs) {
                Label("Where your key lives", systemImage: "lock.fill")
                    .font(CozyFont.caption)
                    .foregroundStyle(CozyColor.inkPrimary)
                Text("In this device's Keychain, readable only while the phone is unlocked. It's never written to a file, never logged, and never sent anywhere except Google's API.")
                    .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("Sous Chef settings") {
    NavigationStack {
        AIKeySettingsView()
    }
}
