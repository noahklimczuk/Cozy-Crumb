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

        nonisolated init(id: UUID = UUID(), author: Author, text: String) {
            self.id = id
            self.author = author
            self.text = text
        }
    }

    var messages: [Message] = []
    var draft = ""
    private(set) var isThinking = false
    private(set) var failure: CozyError?

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
        isThinking = true
        defer { isThinking = false }

        await runTurn(in: modelContext)
    }

    func clear() {
        messages.removeAll()
        history.removeAll()
        failure = nil
    }

    // MARK: - The loop

    private func runTurn(in modelContext: ModelContext) async {
        let runner = SousChefToolRunner(context: modelContext)

        for round in 0..<Self.maximumToolRounds {
            // Rebuilt every round: a tool may have just changed the data the
            // digest describes.
            let systemInstruction = Prompts.sousChefSystem(
                context: buildContext(in: modelContext).promptText,
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
                if let text = reply.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    messages.append(Message(author: .sousChef, text: text))
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

    private func buildContext(in modelContext: ModelContext) -> SousChefContext {
        let recipes = (try? modelContext.fetch(FetchDescriptor<Recipe>())) ?? []
        let pantry = (try? modelContext.fetch(FetchDescriptor<PantryItem>())) ?? []
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
