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
    @State private var isShowingOnboarding = false

    @AppStorage(CozyDefaultsKey.hasSeenTasteOnboarding) private var hasSeenOnboarding = false

    var body: some View {

        NavigationStack {
            VStack(spacing: 0) {
                header

                if viewModel.isAwake {
                    conversation
                } else {
                    asleep
                }
            }
            // One painted ground, like Cook Mode. This screen has no header
            // slab to sit under — its hero *is* the top of it — so the colour
            // has to come from the page or the screen reads as a chat window
            // that wandered in from another app.
            .cozyAccentScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            // The bar is hidden, but the title is still what the screen is
            // called when anything asks.
            .navigationTitle("Sous Chef")
            // Registered for the value-based links on the recommendation
            // cards, so the recipe screen is built on tap rather than on
            // layout.
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            .task {
                await viewModel.loadReflection(in: modelContext)
            }
            .sheet(isPresented: $isShowingOnboarding) {
                TasteOnboardingView()
            }
        }
    }

    // MARK: - Header

    /// No strip under the title and nothing much beside it: the mascot is this
    /// screen's hero and it belongs in the conversation, at the size the empty
    /// state draws it, not shrunk into a badge in the corner.
    ///
    /// The one control is "start again", which used to be a toolbar button and
    /// has nowhere else to go now the bar is hidden. It appears only once
    /// there is a conversation to start again from.
    private var header: some View {
        HStack {
            Spacer()

            if !viewModel.isEmptyConversation {
                Button {
                    viewModel.clear()
                } label: {
                    HeaderGlyphLabel(systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.squishy)
                .accessibilityLabel("Start a new conversation")
            }
        }
        .frame(minHeight: CozyMetrics.minimumTouchTarget)
        .padding(.horizontal, CozySpacing.l)
    }

    // MARK: - Asleep

    /// Unchanged in what it says and does; it just needs a surface now.
    ///
    /// `EmptyStateView` sets its message in `inkSecondary`, which measures
    /// 3.22:1 on blush and fails AA. Rather than teach that component about
    /// coloured grounds for one screen, the panel gives it the white page it
    /// was designed against — and on a painted ground a card reads as the
    /// thing to look at anyway.
    private var asleep: some View {
        VStack(spacing: CozySpacing.l) {
            CrumbCard(cornerRadius: CozyRadius.sheet, block: accent.block) {
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
                                .font(.body.weight(.bold))
                            Text("Wake them up")
                                .font(CozyFont.cardTitle)
                        }
                        .foregroundStyle(CozyColor.inkOnAccent)
                        .padding(.horizontal, CozySpacing.xl)
                        .frame(minHeight: CozyMetrics.minimumTouchTarget + 6)
                        .background(accent.deep,
                                    in: .rect(cornerRadius: CozyRadius.button, style: .continuous))
                        .cozyBlockShadow(CozyDepth.block, color: accent.block)
                    }
                    .buttonStyle(.squishy)
                }
            }
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
            // §7.5. A week of silent learning, said out loud once.
            if let reflection = viewModel.reflection {
                WeeklyReflectionCard(
                    reflection: reflection,
                    onDismiss: { viewModel.dismissReflection() }
                )
            }

            // §9. Offered, never insisted on, and only before there is
            // anything real to go on.
            if !hasSeenOnboarding {
                Button {
                    isShowingOnboarding = true
                } label: {
                    Label("Tell me roughly what you like (45 seconds)", systemImage: "sparkles")
                        .cozyText(CozyFont.caption, color: CozyColor.inkOnAccent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(CozySpacing.m)
                        // On the accent ground, a soft tint of the accent is
                        // the same colour with a line round it.
                        .background(CozyColor.surfaceOnAccent,
                                    in: .rect(cornerRadius: CozyRadius.control, style: .continuous))
                }
                .buttonStyle(.squishy)
            }

            // Centred and much bigger. This is the top of the screen rather
            // than a line inside it — there is no header slab above it — so
            // the mascot is the hero at the size the mascot deserves.
            VStack(spacing: CozySpacing.m) {
                MascotView(pose: .cooking, size: 78)
                    .frame(width: 104, height: 104)
                    .background(CozyColor.card, in: .circle)
                    .overlay { Circle().strokeBorder(accent.deep, lineWidth: 5) }
                    .accessibilityHidden(true)

                VStack(spacing: CozySpacing.s) {
                    Text("Ask me anything")
                        .cozyText(CozyFont.title, color: CozyColor.inkOnAccent)
                        .cozyDisplayTracking(CozyTracking.title, relativeTo: .title)
                        .accessibilityAddTraits(.isHeader)

                    Text("I know what's in your cookbook, your pantry and your week.")
                        .cozyText(CozyFont.subheadline, color: CozyColor.inkOnAccent)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, CozySpacing.s)

            ForEach(SousChefViewModel.openers, id: \.self) { opener in
                Button {
                    Task { await viewModel.send(opener, context: modelContext) }
                } label: {
                    HStack {
                        Text(opener)
                            .cozyText(CozyFont.body, color: CozyColor.inkOnAccent)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: CozySpacing.s)
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(CozyColor.inkOnAccent)
                    }
                    .padding(CozySpacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CozyColor.surfaceOnAccent,
                                in: .rect(cornerRadius: CozyRadius.button, style: .continuous))
                    .contentShape(.rect)
                }
                .buttonStyle(.squishy)
            }
        }
    }

    @ViewBuilder
    private func bubble(for message: SousChefViewModel.Message) -> some View {
        switch message.author {
        // The two speakers are told apart by the corner that isn't round, the
        // way every chat anyone has used does it: the square corner points at
        // whoever said it. Colour alone would have had to survive five accents
        // and both appearances.
        case .user:
            HStack {
                Spacer(minLength: CozySpacing.xl)
                Text(message.text)
                    .cozyText(CozyFont.body, color: CozyColor.inkOnAccent)
                    .padding(CozySpacing.m)
                    .background(accent.deep, in: Self.bubbleShape(pointingLeft: false))
            }

        case .sousChef:
            VStack(alignment: .leading, spacing: CozySpacing.s) {
                HStack(alignment: .bottom, spacing: CozySpacing.s) {
                    MascotView(pose: .idle, size: 28)
                        .frame(width: 38, height: 38)
                        .background(CozyColor.card, in: .circle)
                        .overlay { Circle().strokeBorder(accent.deep, lineWidth: 2) }
                        .accessibilityHidden(true)

                    Text(message.text)
                        .cozyText(CozyFont.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(CozySpacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CozyColor.card, in: Self.bubbleShape(pointingLeft: true))
                        .textSelection(.enabled)
                }

                // The recipes it actually picked, as things you can tap
                // rather than titles you have to go and find.
                ForEach(message.recommendations) { recommendation in
                    RecommendedRecipeCard(recommendation: recommendation)
                        .padding(.leading, 46)
                }
            }

        case .action:
            // Indented to line up with the bubble above it: this is something
            // the Sous Chef did, not a third voice in the conversation.
            Label(message.text, systemImage: "checkmark.circle.fill")
                .font(CozyFont.caption.weight(.semibold))
                .foregroundStyle(CozyColor.inkOnAccent)
                .padding(.horizontal, CozySpacing.m)
                .padding(.vertical, CozySpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CozyColor.mint,
                            in: .rect(cornerRadius: CozyRadius.control, style: .continuous))
                .padding(.leading, 46)
                .accessibilityLabel("Done: \(message.text)")
        }
    }

    /// A bubble with one squared-off corner, pointing at whoever is speaking.
    private static func bubbleShape(pointingLeft: Bool) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: CozyRadius.sheet,
            bottomLeadingRadius: pointingLeft ? 4 : CozyRadius.sheet,
            bottomTrailingRadius: pointingLeft ? CozyRadius.sheet : 4,
            topTrailingRadius: CozyRadius.sheet,
            style: .continuous
        )
    }

    private var thinking: some View {
        HStack(spacing: CozySpacing.s) {
            MascotView(pose: .cooking, size: 30)
            Text("Having a think…")
                .cozyText(CozyFont.caption, color: CozyColor.inkOnAccent)
            Spacer(minLength: 0)
        }
    }

    private func failureNote(_ error: CozyError) -> some View {
        Label(error.friendlyMessage, systemImage: "exclamationmark.circle.fill")
            .font(CozyFont.caption)
            .foregroundStyle(CozyColor.inkPrimary)
            .padding(CozySpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CozyColor.warning.cozyPaled(0.55),
                        in: .rect(cornerRadius: CozyRadius.chip, style: .continuous))
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: CozySpacing.s) {
            CozyTextField(
                placeholder: "What's for dinner?",
                text: $viewModel.draft,
                systemImage: "sparkles",
                submitLabel: .send,
                fill: CozyColor.surfaceOnAccent
            ) {
                Task { await viewModel.send(context: modelContext) }
            }

            // Butter, and square. The send button is the only control on the
            // screen that isn't blush or white, which is the whole reason you
            // can find it without looking.
            Button {
                Task { await viewModel.send(context: modelContext) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(CozyColor.inkOnAccent)
                    .frame(width: 52, height: 52)
                    .background(CozyColor.butter,
                                in: .rect(cornerRadius: CozyRadius.button, style: .continuous))
            }
            .buttonStyle(.squishy)
            .disabled(!viewModel.canSend)
            .opacity(viewModel.canSend ? 1 : 0.5)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, CozySpacing.l)
        .padding(.vertical, CozySpacing.m)
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
    @State private var isShowingWhy = false

    var body: some View {
        Group {
            if let recipe {
                // Value-based: the closure form builds a whole recipe screen
                // per recommendation as the list is laid out.
                NavigationLink(value: recipe) {
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

                HStack(spacing: CozySpacing.s) {
                    if let time = recipe.totalTimeDisplay {
                        Text(time)
                            .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
                    }

                    // §8. The app's own reasoning, in plain language, on
                    // every recommendation — not the model's sentence, the
                    // actual score.
                    if !recommendation.reasoning.isEmpty {
                        Button {
                            isShowingWhy = true
                        } label: {
                            Text("Why this?")
                                .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
                                .underline()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(CozyFont.caption)
                .foregroundStyle(CozyColor.inkSecondary)
        }
        .popover(isPresented: $isShowingWhy) {
            WhyThisView(title: recipe.title, reasons: recommendation.reasoning)
                .presentationCompactAdaptation(.popover)
        }
        .padding(CozySpacing.m)
        // White with a block rather than a soft tint of the accent: the page
        // underneath is the accent now, and accent.soft on accent.color is two
        // shades of the same thing with a line between them.
        .background(CozyColor.card, in: .rect(cornerRadius: CozyRadius.button, style: .continuous))
        // The accent's block, not the beige one. A block is the edge the card
        // casts onto the page it is on, and this page is painted.
        .cozyBlockShadow(CozyDepth.small, color: accent.block)
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
        .background(CozyColor.warning.cozyPaled(0.65),
                    in: .rect(cornerRadius: CozyRadius.chip, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Why this?

/// §8. The score breakdown, in words.
///
/// Shown because a recommendation nobody can interrogate is a recommendation
/// nobody can correct. These lines come from the components that actually
/// carried the score, so this is the reasoning itself rather than a
/// plausible-sounding account of it.
private struct WhyThisView: View {
    let title: String
    let reasons: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: CozySpacing.s) {
            Text(title)
                .cozyText(CozyFont.bodyEmphasis)

            ForEach(reasons, id: \.self) { reason in
                Label(reason, systemImage: "circle.fill")
                    .labelStyle(BulletLabelStyle())
                    .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
            }
        }
        .padding(CozySpacing.l)
        .frame(maxWidth: 300, alignment: .leading)
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: CozySpacing.s) {
            configuration.icon
                .font(.system(size: 4))
                .foregroundStyle(CozyColor.inkSecondary)
            configuration.title
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Weekly reflection

/// §7.5. One observation about the week, as a card.
///
/// It exists because every other part of the learning system is invisible by
/// design — it improves a ranking whose internals nobody sees. This is the
/// one place a week of it becomes a sentence, which is most of where the
/// feeling of being noticed comes from.
private struct WeeklyReflectionCard: View {
    let reflection: WeeklyReflectionText
    let onDismiss: () -> Void

    var body: some View {
        CrumbCard {
            VStack(alignment: .leading, spacing: CozySpacing.s) {
                HStack(alignment: .top) {
                    Label("Your week", systemImage: "calendar")
                        .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(CozyFont.caption2)
                            .foregroundStyle(CozyColor.inkSecondary)
                    }
                    .accessibilityLabel("Dismiss this week's note")
                }

                Text(reflection.observation)
                    .cozyText(CozyFont.body)
                    .fixedSize(horizontal: false, vertical: true)

                if let offer = reflection.offer, !offer.isEmpty {
                    Text(offer)
                        .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
