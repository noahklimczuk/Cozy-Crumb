//
//  SousChefView.swift
//  Cozy Crumb
//
//  Phase 8. The tab where you can just ask.
//
//  The empty state does the heavy lifting: nobody knows what an AI assistant
//  in a recipe app is for until they see a question worth asking, so the
//  openers are all things that need *their* data to answer — "what can I make
//  with what I've got?" is not a question you can type into a search engine.
//
//  Actions the Sous Chef takes appear in the transcript as their own receipts,
//  in the app's colour rather than as chat. Something writing to your shopping
//  list should look different from something talking to you.
//

import SwiftData
import SwiftUI

struct SousChefView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accentPalette) private var accent

    @State private var viewModel = SousChefViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isAwake {
                    conversation
                } else {
                    asleep
                }
            }
            .background { BlobBackground() }
            .navigationTitle("Sous Chef")
            .toolbar {
                if !viewModel.isEmptyConversation {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.clear()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundStyle(CozyColor.inkSecondary)
                        }
                        .accessibilityLabel("Start a new conversation")
                    }
                }
            }
        }
    }

    // MARK: - Asleep

    private var asleep: some View {
        VStack(spacing: CozySpacing.l) {
            EmptyStateView(
                title: "The Sous Chef is asleep.",
                message: "Add your Gemini key and I can answer from your own cookbook — what to cook tonight, what you can make with what's in, what's still missing for the week.",
                pose: .sleeping
            )

            NavigationLink {
                AIKeySettingsView()
            } label: {
                HStack(spacing: CozySpacing.s) {
                    Image(systemName: "sparkles")
                        .font(.body.weight(.semibold))
                    Text("Wake them up")
                        .font(CozyFont.bodyEmphasis)
                }
                .foregroundStyle(CozyColor.inkPrimary)
                .padding(.horizontal, CozySpacing.xl)
                .frame(minHeight: CozyMetrics.minimumTouchTarget + 6)
                .background(accent.color, in: .rect(cornerRadius: CozyRadius.button, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: CozyRadius.button, style: .continuous)
                        .strokeBorder(accent.deep, lineWidth: 1.5)
                }
                .cozyLiftShadow()
            }
            .buttonStyle(.squishy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(CozySpacing.l)
    }

    // MARK: - Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: CozySpacing.m) {
                    if viewModel.isEmptyConversation {
                        opener
                    }

                    ForEach(viewModel.messages) { message in
                        bubble(for: message)
                            .id(message.id)
                    }

                    if let pending = viewModel.pendingAllergyConfirmation {
                        AllergyConfirmationCard(
                            statement: pending.statement,
                            onConfirm: { viewModel.confirmPendingAllergy(in: modelContext) },
                            onReject: { viewModel.rejectPendingAllergy(in: modelContext) }
                        )
                    }

                    if viewModel.isThinking {
                        thinking
                            .id(Self.thinkingID)
                    }

                    if let failure = viewModel.failure {
                        failureNote(failure)
                    }
                }
                .padding(CozySpacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToEnd(proxy)
            }
            .onChange(of: viewModel.isThinking) { _, _ in
                scrollToEnd(proxy)
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
    }

    private static let thinkingID = "thinking"

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(Motion.gentle) {
            if viewModel.isThinking {
                proxy.scrollTo(Self.thinkingID, anchor: .bottom)
            } else if let last = viewModel.messages.last?.id {
                proxy.scrollTo(last, anchor: .bottom)
            }
        }
    }

    private var opener: some View {
        VStack(alignment: .leading, spacing: CozySpacing.m) {
            HStack(spacing: CozySpacing.m) {
                MascotView(pose: .cooking, size: 72)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask me anything")
                        .cozyText(CozyFont.title2)
                    Text("I know what's in your cookbook, your pantry and your week.")
                        .cozyText(CozyFont.subheadline, color: CozyColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ForEach(SousChefViewModel.openers, id: \.self) { opener in
                Button {
                    Task { await viewModel.send(opener, context: modelContext) }
                } label: {
                    HStack {
                        Text(opener)
                            .cozyText(CozyFont.body)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: CozySpacing.s)
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CozyColor.inkSecondary)
                    }
                    .padding(CozySpacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CozyColor.card, in: .rect(cornerRadius: CozyRadius.chip, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: CozyRadius.chip, style: .continuous)
                            .strokeBorder(CozyColor.outline, lineWidth: 1)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.squishy)
            }
        }
    }

    @ViewBuilder
    private func bubble(for message: SousChefViewModel.Message) -> some View {
        switch message.author {
        case .user:
            HStack {
                Spacer(minLength: CozySpacing.xl)
                Text(message.text)
                    .cozyText(CozyFont.body)
                    .padding(CozySpacing.m)
                    .background(accent.soft, in: .rect(cornerRadius: CozyRadius.chip, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: CozyRadius.chip, style: .continuous)
                            .strokeBorder(accent.deep.opacity(0.35), lineWidth: 1)
                    }
            }

        case .sousChef:
            VStack(alignment: .leading, spacing: CozySpacing.s) {
                HStack(alignment: .top, spacing: CozySpacing.s) {
                    MascotView(pose: .idle, size: 30)
                        .accessibilityHidden(true)

                    Text(message.text)
                        .cozyText(CozyFont.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(CozySpacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CozyColor.card, in: .rect(cornerRadius: CozyRadius.chip, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: CozyRadius.chip, style: .continuous)
                                .strokeBorder(CozyColor.outline, lineWidth: 1)
                        }
                        .textSelection(.enabled)
                }

                // The recipes it actually picked, as things you can tap
                // rather than titles you have to go and find.
                ForEach(message.recommendations) { recommendation in
                    RecommendedRecipeCard(recommendation: recommendation)
                        .padding(.leading, 38)
                }
            }

        case .action:
            Label(message.text, systemImage: "checkmark.circle.fill")
                .font(CozyFont.caption)
                .foregroundStyle(CozyColor.inkPrimary)
                .padding(.horizontal, CozySpacing.m)
                .padding(.vertical, CozySpacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CozyColor.success.opacity(0.4),
                            in: .rect(cornerRadius: CozyRadius.chip, style: .continuous))
                .accessibilityLabel("Done: \(message.text)")
        }
    }

    private var thinking: some View {
        HStack(spacing: CozySpacing.s) {
            MascotView(pose: .cooking, size: 30)
            Text("Having a think…")
                .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
            Spacer(minLength: 0)
        }
    }

    private func failureNote(_ error: CozyError) -> some View {
        Label(error.friendlyMessage, systemImage: "exclamationmark.circle.fill")
            .font(CozyFont.caption)
            .foregroundStyle(CozyColor.inkPrimary)
            .padding(CozySpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CozyColor.warning.opacity(0.45),
                        in: .rect(cornerRadius: CozyRadius.chip, style: .continuous))
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: CozySpacing.s) {
            CozyTextField(
                placeholder: "What's for dinner?",
                text: $viewModel.draft,
                systemImage: "sparkles",
                submitLabel: .send
            ) {
                Task { await viewModel.send(context: modelContext) }
            }

            Button {
                Task { await viewModel.send(context: modelContext) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(CozyColor.inkPrimary)
                    .frame(width: CozyMetrics.minimumTouchTarget + 6,
                           height: CozyMetrics.minimumTouchTarget + 6)
                    .background(accent.color, in: .circle)
                    .overlay { Circle().strokeBorder(accent.deep, lineWidth: 1.5) }
                    .cozyLiftShadow()
            }
            .buttonStyle(.squishy)
            .disabled(!viewModel.canSend)
            .opacity(viewModel.canSend ? 1 : 0.5)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, CozySpacing.l)
        .padding(.vertical, CozySpacing.m)
        .background(.ultraThinMaterial)
    }
}

#Preview("Sous Chef") {
    SousChefView()
        .modelContainer(PreviewData.container)
}

// MARK: - Recommendation card

/// A recipe the Sous Chef picked, with the one line it gave for why.
///
/// The card is looked up by id rather than rendered from what the model said
/// about it. That is deliberate: the title, time and photo come from the
/// store, so a reply that misremembers a recipe cannot put wrong information
/// on screen — and if the id matches nothing, the card simply doesn't appear
/// and the prose stands on its own.
private struct RecommendedRecipeCard: View {
    let recommendation: SousChefRecommendation

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accentPalette) private var accent

    @State private var recipe: Recipe?

    var body: some View {
        Group {
            if let recipe {
                NavigationLink {
                    RecipeDetailView(recipe: recipe)
                } label: {
                    card(for: recipe)
                }
                .buttonStyle(.squishy)
            }
        }
        .task(id: recommendation.recipeID) {
            recipe = lookUp(recommendation.recipeID)
        }
    }

    private func card(for recipe: Recipe) -> some View {
        HStack(spacing: CozySpacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.title)
                    .cozyText(CozyFont.bodyEmphasis)
                    .multilineTextAlignment(.leading)

                if !recommendation.why.isEmpty {
                    Text(recommendation.why)
                        .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let time = recipe.totalTimeDisplay {
                    Text(time)
                        .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(CozyFont.caption)
                .foregroundStyle(CozyColor.inkSecondary)
        }
        .padding(CozySpacing.m)
        .background(accent.soft.opacity(0.5), in: .rect(cornerRadius: CozyRadius.chip, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CozyRadius.chip, style: .continuous)
                .strokeBorder(accent.deep.opacity(0.3), lineWidth: 1)
        }
    }

    private func lookUp(_ id: UUID) -> Recipe? {
        var descriptor = FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}

// MARK: - Allergy confirmation

/// §5. An allergy heard in conversation is never applied on its own.
///
/// Both mistakes are bad in different ways — a false positive silently takes
/// away food someone can eat, a false negative is a safety issue — so neither
/// is left to a background inference. The card asks, plainly, once.
struct AllergyConfirmationCard: View {
    let statement: String
    let onConfirm: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CozySpacing.s) {
            Label(statement, systemImage: "exclamationmark.triangle.fill")
                .font(CozyFont.bodyEmphasis)
                .foregroundStyle(CozyColor.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Want me to keep that out of everything I suggest?")
                .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: CozySpacing.s) {
                Button("Yes, filter it out", action: onConfirm)
                    .buttonStyle(.squishy)

                Button("No, I'm fine with it", action: onReject)
                    .buttonStyle(.squishy)
            }
            .font(CozyFont.caption)
        }
        .padding(CozySpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CozyColor.warning.opacity(0.35),
                    in: .rect(cornerRadius: CozyRadius.chip, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
