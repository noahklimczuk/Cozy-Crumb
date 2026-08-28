//
//  AIKeySettingsView.swift
//  Cozy Crumb
//
//  Key setup. The app can carry its own key (see GeminiAPIKey), in which
//  case there is nothing to do here; a key pasted in anyway takes precedence
//  and lives in the Keychain, never leaving the device except as a header on
//  a request to Google.
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

    /// A key the owner pasted in. Not the same question as `isAwake`: a
    /// build that carries its own key is awake with nothing saved here.
    var hasSavedKey: Bool {
        savedKeyPreview != nil
    }

    /// Running on the key built into the app, with none of their own.
    var isUsingBuiltInKey: Bool {
        savedKeyPreview == nil && GeminiAPIKey.builtInKey != nil
    }

    /// Whether the Sous Chef can reach Gemini at all, on whichever key.
    var isAwake: Bool {
        hasSavedKey || isUsingBuiltInKey
    }

    var builtInKeyPreview: String? {
        GeminiAPIKey.builtInKey.map { KeychainStore.masked($0) }
    }

    var keyFieldPlaceholder: String {
        if hasSavedKey { return "Replace the key" }
        return isUsingBuiltInKey ? "Use your own key instead" : "Paste your key"
    }

    var saveButtonTitle: String {
        if hasSavedKey { return "Replace key" }
        return isUsingBuiltInKey ? "Use my key" : "Save key"
    }

    /// Removing a saved key falls back to the built-in one rather than
    /// switching the Sous Chef off, so say so on the button.
    var removeButtonTitle: String {
        GeminiAPIKey.builtInKey == nil ? "Remove key" : "Go back to the built-in key"
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

    /// Round trip that proves the key works.
    ///
    /// The budget is deliberately generous: on Gemini 3 models, thinking
    /// tokens are drawn from maxOutputTokens, so a tight cap gets spent on
    /// reasoning and returns MAX_TOKENS with no text — which looks like a
    /// broken key but is not one.
    func testConnection(model: GeminiModel) async {
        testState = .testing

        let outcome = await client.generate(
            model: model,
            systemInstruction: nil,
            parts: [.text("Reply with the single word: ready")],
            temperature: 0,
            maxOutputTokens: 512,
            timeout: 25
        )

        switch outcome {
        case .success:
            testState = .passed

        case .failure(let error):
            // These three only happen *after* the request was accepted and
            // authenticated, so as a credential test they are a pass. Failing
            // here would tell the user their key is broken when it is fine.
            switch error {
            case .responseTruncated, .emptyResponse, .blockedBySafety:
                testState = .passed
            default:
                testState = .failed(error)
            }
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
                if viewModel.isAwake {
                    modelCard
                }
                privacyNote
            }
            .padding(CozySpacing.l)
        }
        .cozyScreenBackground()
        .navigationTitle("Sous Chef")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.refresh() }
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(spacing: CozySpacing.s) {
            MascotView(pose: viewModel.isAwake ? .cooking : .sleeping, size: 92)
            Text(viewModel.isAwake ? "The Sous Chef is awake." : "The Sous Chef is asleep.")
                .cozyText(CozyFont.title2)
            Text(viewModel.isAwake
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
                    keyStatus(title: "Key saved", preview: preview)
                } else if let preview = viewModel.builtInKeyPreview {
                    keyStatus(
                        title: "Using the key built into the app",
                        preview: preview,
                        note: "Nothing to set up. Paste your own below if you'd rather spend your own quota."
                    )
                }

                CozyTextField(
                    placeholder: viewModel.keyFieldPlaceholder,
                    text: $viewModel.draftKey,
                    systemImage: "key",
                    isSecure: true
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                SquishyButton(title: viewModel.saveButtonTitle, systemImage: "checkmark") {
                    viewModel.save()
                }
                .disabled(!viewModel.canSave)

                if viewModel.isAwake {
                    SquishyButton(title: "Test connection", systemImage: "bolt", emphasis: .secondary) {
                        Task { await viewModel.testConnection(model: model) }
                    }
                    .disabled(viewModel.testState == .testing)

                    testResult
                }

                if viewModel.hasSavedKey {
                    Button(viewModel.removeButtonTitle, role: .destructive) {
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

                Text(viewModel.isUsingBuiltInKey
                     ? "You don't need a key of your own — this is only if you want one."
                     : "The free tier is generous enough for personal use.")
                    .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func keyStatus(title: String, preview: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: CozySpacing.xs) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .cozyText(CozyFont.bodyEmphasis)
                    Text(preview)
                        .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                        .monospaced()
                }
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(CozyColor.success)
            }

            if let note {
                Text(note)
                    .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        .background(CozyColor.warning.cozyPaled(0.6),
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
                Text(viewModel.isUsingBuiltInKey
                     ? "This build carries its own key, so there's nothing of yours to store. Add one of your own and it goes into this device's Keychain, readable only while the phone is unlocked — never written to a file, never logged, and never sent anywhere except Google's API."
                     : "In this device's Keychain, readable only while the phone is unlocked. It's never written to a file, never logged, and never sent anywhere except Google's API.")
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
