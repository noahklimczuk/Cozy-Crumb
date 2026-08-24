//
//  SousChefViewModel.swift
//  Cozy Crumb
//
//  One conversation, and the loop that lets it do things.
//
//  A turn is not "send text, get text". The model can come back asking for a
//  function instead of an answer, so a turn is:
//
//      ask → maybe run what it asked for → tell it what happened → ask again
//
//  bounded at three rounds. The bound matters: without it, a model that keeps
//  calling `find_recipes` forever would spend the user's quota in a loop with
//  nothing to show. Three is enough for "search, then plan, then answer" and
//  short enough that a confused model gives up quickly.
//
//  The cookbook digest is rebuilt from the store on every send rather than
//  once per conversation, so a recipe added — or a meal planned by the last
//  tool call — is visible to the next question.
//

import Foundation
import SwiftData
import SwiftUI
import os

@Observable
@MainActor
final class SousChefViewModel {

    nonisolated struct Message: Identifiable, Sendable, Equatable {
        nonisolated enum Author: Sendable, Equatable {
            case user
            case sousChef
            /// A receipt for something the Sous Chef did to the user's data.
            case action
        }

        let id: UUID
        var author: Author
        var text: String
        /// Cards for saved recipes the Sous Chef picked, parsed out of the
        /// fenced block §7.1 asks for. The block itself never reaches `text`.
        var recommendations: [SousChefRecommendation]

        nonisolated init(
            id: UUID = UUID(),
            author: Author,
            text: String,
            recommendations: [SousChefRecommendation] = []
        ) {
            self.id = id
            self.author = author
            self.text = text
            self.recommendations = recommendations
        }
    }

    var messages: [Message] = []
    var draft = ""
    private(set) var isThinking = false
    private(set) var failure: CozyError?

    /// An allergy the extractor thinks it heard, waiting on a yes or no.
    ///
    /// §5: never applied silently in either direction. A false positive
    /// removes food they can eat; a false negative is a safety issue. So it
    /// sits here as a card until a person decides.
    private(set) var pendingAllergyConfirmation: CookFact?

    /// Everything the user has said this session, for the background
    /// extractor to read.
    private var userTurns: [String] = []

    /// §7.5. A short observation about the week, shown as a card on the empty
    /// screen. The cheapest way to make a fortnight of silent learning
    /// visible.
    private(set) var reflection: WeeklyReflectionText?

    /// How many times the model may ask for a function before we insist on an
    /// answer.
    private static let maximumToolRounds = 3

    private let client: GeminiClient
    private let keychain: KeychainStore

    /// The wire history, which is not the same as what's on screen: it also
    /// carries the function calls and their results.
    private var history: [GeminiContent] = []

    init(client: GeminiClient = GeminiClient(), keychain: KeychainStore = .shared) {
        self.client = client
        self.keychain = keychain
    }

    var isAwake: Bool {
        keychain.hasValue(for: .geminiAPIKey)
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking && isAwake
    }

    var isEmptyConversation: Bool {
        messages.isEmpty
    }

    // MARK: - Openers

    /// Shown on the empty screen. Deliberately the things only *this* assistant
    /// can answer — each one needs the user's own data to mean anything.
    nonisolated static let openers = [
        "What can I make with what I've got?",
        "Plan me three dinners this week",
        "What should I cook tonight?",
        "What's missing for this week's plan?"
    ]

    // MARK: - Sending

    func send(_ text: String? = nil, context modelContext: ModelContext) async {
        let question = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }

        guard isAwake else {
            failure = .missingAPIKey
            return
        }

        draft = ""
        failure = nil
        messages.append(Message(author: .user, text: question))
        history.append(GeminiContent(role: "user", parts: [.text(question)]))
        userTurns.append(question)
        isThinking = true
        defer { isThinking = false }

        await runTurn(in: modelContext, question: question)

        // After the answer, not before it: the user is waiting on dinner
        // advice, not on bookkeeping.
        await learn(from: question, in: modelContext)
    }

    /// Looks for a weekly observation, at most once a week. Silent when
    /// there is nothing worth saying.
    func loadReflection(in modelContext: ModelContext) async {
        guard isAwake, reflection == nil else { return }
        reflection = await WeeklyReflection.run(in: modelContext, client: client)
    }

    func dismissReflection() {
        reflection = nil
    }

    func clear() {
        messages.removeAll()
        history.removeAll()
        userTurns.removeAll()
        pendingAllergyConfirmation = nil
        failure = nil
    }

    // MARK: - The loop

    private func runTurn(in modelContext: ModelContext, question: String) async {
        let runner = SousChefToolRunner(context: modelContext)

        for round in 0..<Self.maximumToolRounds {
            // Rebuilt every round: a tool may have just changed the data the
            // brief describes, and the ranking is cheap enough to redo.
            let brief = SousChefBrief.assemble(query: question, in: modelContext)

            let systemInstruction = Prompts.sousChefSystem(
                digest: brief.digest.text,
                appState: brief.appState,
                candidates: brief.candidatesBlock,
                today: Date.now
            )

            let outcome = await client.converse(
                model: .preferred,
                systemInstruction: systemInstruction,
                contents: history,
                // The last round is answer-only: something has to end the
                // conversation, and it should be words rather than a fourth
                // lookup.
                tools: round == Self.maximumToolRounds - 1 ? [] : [SousChefTools.tool]
            )

            switch outcome {
            case .failure(let error):
                Log.ai.info("Sous Chef turn failed: \(String(describing: error), privacy: .public)")
                failure = error
                return

            case .success(let reply):
                if let raw = reply.text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                    // The fenced block is an instruction to the app, not a
                    // sentence, so it is taken out before anything is shown.
                    let parsed = RecommendationBlockParser.parse(
                        raw,
                        knownRecipeIDs: brief.offeredRecipeIDs,
                        reasoning: brief.reasoning
                    )

                    if !parsed.prose.isEmpty || !parsed.recommendations.isEmpty {
                        messages.append(Message(
                            author: .sousChef,
                            text: parsed.prose,
                            recommendations: parsed.recommendations
                        ))
                    }
                }

                guard !reply.functionCalls.isEmpty else {
                    history.append(GeminiContent(
                        role: "model",
                        parts: [.text(reply.text ?? "")]
                    ))
                    return
                }

                // Echo the request, then answer it. Gemini needs both halves in
                // the history or the next turn has no idea what it asked for.
                history.append(GeminiContent(
                    role: "model",
                    parts: reply.functionCalls.map { .functionCall($0) }
                ))

                var responses: [GeminiPart] = []

                for call in reply.functionCalls {
                    let result = runner.run(call)

                    if let receipt = result.receipt {
                        messages.append(Message(author: .action, text: receipt))
                    }

                    responses.append(.functionResponse(name: call.name, result: result.forModel))
                }

                history.append(GeminiContent(role: "user", parts: responses))
            }
        }
    }

    // MARK: - Learning from the conversation

    /// Reads the session for durable facts, in the background, and only when
    /// something in it looks like a durable fact. See FactExtractor.
    private func learn(from question: String, in modelContext: ModelContext) async {
        guard FactExtractor.isWorthExtracting(from: question) else { return }

        let known = CookFactStore.active(in: modelContext).map(\.statement)

        let extracted = await FactExtractor.extract(
            exchange: Array(userTurns.suffix(4)),
            existingFacts: known,
            client: client
        )

        guard !extracted.isEmpty else { return }

        for fact in extracted {
            let category = fact.factCategory

            // Something that disagrees with what we had. The Sous Chef asks
            // rather than deciding — this single behaviour does more to make
            // the app feel like it is learning than any amount of scoring.
            if let existing = CookFactStore.contradiction(
                of: fact.statement,
                category: category,
                in: modelContext
            ), !existing.isUserEdited {
                messages.append(Message(
                    author: .action,
                    text: "I had you down as: \(existing.statement). Has that changed?"
                ))
                continue
            }

            let stored = CookFactStore.add(
                statement: fact.statement,
                category: category,
                confidence: fact.confidence,
                source: .extractedFromChat,
                excerpt: fact.sourceExcerpt,
                in: modelContext
            )

            if let stored, stored.needsConfirmation, pendingAllergyConfirmation == nil {
                pendingAllergyConfirmation = stored
            }
        }
    }

    // MARK: - Confirmation cards

    func confirmPendingAllergy(in modelContext: ModelContext) {
        guard let fact = pendingAllergyConfirmation else { return }
        CookFactStore.confirm(fact, in: modelContext)
        messages.append(Message(author: .action, text: "Noted — I'll keep that out from now on."))
        pendingAllergyConfirmation = nil
    }

    func rejectPendingAllergy(in modelContext: ModelContext) {
        guard let fact = pendingAllergyConfirmation else { return }
        CookFactStore.reject(fact, in: modelContext)
        pendingAllergyConfirmation = nil
    }

    private func buildContext(in modelContext: ModelContext) -> SousChefContext {
        let recipes = (try? modelContext.fetch(FetchDescriptor<Recipe>())) ?? []
        let pantry = PantryDecay.activeItems(in: modelContext)
        let groceries = (try? modelContext.fetch(FetchDescriptor<GroceryItem>())) ?? []
        let plannedMeals = (try? modelContext.fetch(FetchDescriptor<PlannedMeal>())) ?? []

        let unitsRaw = UserDefaults.standard.string(forKey: CozyDefaultsKey.measurementSystem)

        return SousChefContext.build(
            recipes: recipes,
            pantry: pantry,
            groceries: groceries,
            plannedMeals: plannedMeals,
            units: unitsRaw.flatMap(MeasurementSystem.init(rawValue:)) ?? .asWritten
        )
    }
}
