//
//  FridgePhotoReader.swift
//  Cozy Crumb
//
//  "Snap a photo of your fridge and I'll take a look" (§5.8).
//
//  Reading a photo is the easy half. The hard half is that a model looking at
//  a fridge is being asked to say what *isn't* there as much as what is, and
//  it would much rather list eggs. So:
//
//    - the prompt tells it to name only what it can see, and the schema makes
//      it commit to a confidence for each thing
//    - anything under a half is kept but flagged, not silently dropped: "is
//      that mustard?" is a useful question, and a wrong guess the user can
//      untick costs nothing
//    - nothing reaches the pantry without passing through the review sheet,
//      the same rule imported recipes follow
//
//  Multiple photos are sent in one call rather than one call each: a fridge
//  door and its shelves are one kitchen, and separate calls would list the
//  same milk twice.
//

import Foundation
import os

/// Something the model saw, before the user has confirmed it.
nonisolated struct SpottedPantryItem: Identifiable, Sendable, Equatable {
    let id: UUID
    var name: String
    var quantity: Double?
    var unit: String?
    var category: GroceryCategory
    var confidence: Double

    nonisolated init(
        id: UUID = UUID(),
        name: String,
        quantity: Double? = nil,
        unit: String? = nil,
        category: GroceryCategory = .other,
        confidence: Double
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.confidence = confidence
    }

    /// Below this, the app asks rather than assumes: the row still appears but
    /// starts unticked, under a heading that says it isn't sure.
    nonisolated static let confidenceFloor = 0.5

    nonisolated var isConfident: Bool {
        confidence >= Self.confidenceFloor
    }
}

struct FridgePhotoReader: Sendable {

    private let client: GeminiClient
    private let model: GeminiModel

    /// Vision needs the fuller model — Flash-Lite is text-first, and a photo
    /// of a fridge is exactly the case it's worst at.
    init(client: GeminiClient = GeminiClient(), model: GeminiModel = .balanced) {
        self.client = client
        self.model = model
    }

    func read(photos: [Data]) async -> Result<[SpottedPantryItem], CozyError> {
        let usable = photos.filter { !$0.isEmpty }.prefix(4)
        guard !usable.isEmpty else { return .failure(.imageUnavailable) }

        // Images first, prompt last — Gemini attends to them better that way.
        var parts: [GeminiPart] = usable.map { .image(jpeg: $0) }
        parts.append(.text(Prompts.pantryPhotoPrompt))

        let outcome = await client.generate(
            model: model,
            systemInstruction: Prompts.pantryPhotoSystem,
            parts: parts,
            schema: PantrySchemas.fridgePhoto,
            temperature: 0.1,
            maxOutputTokens: 8_192,
            timeout: GeminiClient.visionTimeout
        )

        switch outcome {
        case .failure(let error):
            return .failure(error)

        case .success(let raw):
            let cleaned = GeminiClient.stripJSONFences(raw)

            guard let data = cleaned.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(AISpottedPantry.self, from: data) else {
                Log.ai.error("Could not decode a fridge photo response")
                return .failure(.decodingFailed)
            }

            let items = Self.convert(decoded)
            Log.ai.info("Fridge photo yielded \(items.count, privacy: .public) items")

            return .success(items)
        }
    }

    /// Cleans up what came back: drops the empties, folds duplicate names, and
    /// works out the aisle ourselves rather than asking the model for it.
    nonisolated static func convert(_ decoded: AISpottedPantry) -> [SpottedPantryItem] {
        var seen: [String: Int] = [:]
        var items: [SpottedPantryItem] = []

        for spotted in decoded.items {
            let name = spotted.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            let key = GroceryMerge.normalizedName(name)

            // The prompt asks for one row per thing, but a model looking at a
            // full fridge door will still list "milk" twice often enough to
            // handle here.
            if let index = seen[key] {
                items[index].quantity = Self.combined(items[index].quantity, spotted.quantity)
                items[index].confidence = max(items[index].confidence, spotted.confidence)
                continue
            }

            seen[key] = items.count
            items.append(
                SpottedPantryItem(
                    name: name,
                    quantity: spotted.quantity,
                    unit: spotted.unit?.trimmingCharacters(in: .whitespacesAndNewlines),
                    category: GroceryCategoryGuesser.category(for: name),
                    confidence: min(max(spotted.confidence, 0), 1)
                )
            )
        }

        // Surest first: the things worth ticking are at the top, the "is that
        // mustard?" rows at the bottom.
        return items.sorted { $0.confidence > $1.confidence }
    }

    private nonisolated static func combined(_ existing: Double?, _ incoming: Double?) -> Double? {
        switch (existing, incoming) {
        case (nil, nil): nil
        case (let have?, nil): have
        case (nil, let added?): added
        case (let have?, let added?): have + added
        }
    }
}
