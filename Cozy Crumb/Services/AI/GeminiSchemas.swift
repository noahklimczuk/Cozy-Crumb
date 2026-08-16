//
//  GeminiSchemas.swift
//  Cozy Crumb
//
//  Response schemas for the structured-output calls. Setting
//  responseMimeType to application/json together with a responseSchema
//  constrains the model to valid JSON of the right shape, which is a real
//  advantage over asking nicely in the prompt.
//
//  The parser still defends against markdown fences anyway — belt and braces.
//

import Foundation

/// A minimal OpenAPI-subset schema, which is what Gemini accepts.
///
/// Cases carry no default values — associated-value defaults are shaky ground
/// in Swift, so the convenience lives in the builders below instead.
indirect enum GeminiSchema: Sendable {
    case string(description: String?, nullable: Bool)
    case number(description: String?, nullable: Bool)
    case integer(description: String?, nullable: Bool)
    case boolean(description: String?)
    case array(of: GeminiSchema, description: String?)
    case object(properties: [(String, GeminiSchema)], required: [String], description: String?)
}

extension GeminiSchema {
    nonisolated static func text(_ description: String? = nil, nullable: Bool = false) -> GeminiSchema {
        .string(description: description, nullable: nullable)
    }

    nonisolated static func decimal(_ description: String? = nil, nullable: Bool = false) -> GeminiSchema {
        .number(description: description, nullable: nullable)
    }

    nonisolated static func whole(_ description: String? = nil, nullable: Bool = false) -> GeminiSchema {
        .integer(description: description, nullable: nullable)
    }

    nonisolated static func flag(_ description: String? = nil) -> GeminiSchema {
        .boolean(description: description)
    }

    nonisolated static func list(of element: GeminiSchema) -> GeminiSchema {
        .array(of: element, description: nil)
    }

    nonisolated static func record(
        _ properties: [(String, GeminiSchema)],
        required: [String]
    ) -> GeminiSchema {
        .object(properties: properties, required: required, description: nil)
    }
}

extension GeminiSchema: Encodable {
    private enum CodingKeys: String, CodingKey {
        case type, description, nullable, items, properties, required
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .string(description, nullable):
            try container.encode("STRING", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
            if nullable { try container.encode(true, forKey: .nullable) }

        case let .number(description, nullable):
            try container.encode("NUMBER", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
            if nullable { try container.encode(true, forKey: .nullable) }

        case let .integer(description, nullable):
            try container.encode("INTEGER", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
            if nullable { try container.encode(true, forKey: .nullable) }

        case let .boolean(description):
            try container.encode("BOOLEAN", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)

        case let .array(items, description):
            try container.encode("ARRAY", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encode(items, forKey: .items)

        case let .object(properties, required, description):
            try container.encode("OBJECT", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)

            // Encoded through an ordered array of pairs rather than a
            // dictionary so property order in the request is stable.
            var propertiesContainer = container.nestedContainer(
                keyedBy: DynamicKey.self,
                forKey: .properties
            )
            for (name, schema) in properties {
                guard let key = DynamicKey(stringValue: name) else { continue }
                try propertiesContainer.encode(schema, forKey: key)
            }

            try container.encode(required, forKey: .required)
        }
    }

    private struct DynamicKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

// MARK: - Recipe extraction

enum RecipeSchemas {

    /// Matches the §6.2 target shape.
    nonisolated static let extraction = GeminiSchema.record(
        [
            ("found", .flag("False when the text contains no recipe at all.")),
            ("confidence", .decimal("0 to 1. Below 0.6 means you guessed at structure.")),
            ("title", .text()),
            ("summary", .text(nil, nullable: true)),
            ("servings", .whole(nil, nullable: true)),
            ("prepMinutes", .whole(nil, nullable: true)),
            ("cookMinutes", .whole(nil, nullable: true)),
            ("ingredients", .list(of: .record(
                [
                    ("rawText", .text("The original line, verbatim.")),
                    ("quantity", .decimal(nil, nullable: true)),
                    ("unit", .text(nil, nullable: true)),
                    ("name", .text("The food item alone.")),
                    ("note", .text(nil, nullable: true)),
                    ("isSectionHeader", .flag())
                ],
                required: ["rawText", "name", "isSectionHeader"]
            ))),
            ("steps", .list(of: .record(
                [
                    ("text", .text()),
                    ("durationSeconds", .whole(nil, nullable: true))
                ],
                required: ["text"]
            ))),
            ("tags", .list(of: .text()))
        ],
        required: ["found", "confidence", "title", "ingredients", "steps", "tags"]
    )
}

// MARK: - Pantry

enum PantrySchemas {

    /// What a photo of a fridge or a cupboard shelf yields (§5.8).
    ///
    /// Deliberately shallow: a name, a rough amount, and how sure the model is
    /// that it's really there. Everything else — expiry dates, aisles — is
    /// guesswork from a photograph, and a pantry that quietly invents a
    /// use-by date is worse than one that leaves it blank.
    nonisolated static let fridgePhoto = GeminiSchema.record(
        [
            ("items", .list(of: .record(
                [
                    ("name", .text("What it is, as a shopper would say it: \"milk\", \"red peppers\"")),
                    ("quantity", .decimal("How many, when they can be counted", nullable: true)),
                    ("unit", .text("Only if it is written on the packaging", nullable: true)),
                    ("confidence", .decimal("0 to 1. Below 0.5 means you are guessing at what it is."))
                ],
                required: ["name", "confidence"]
            )))
        ],
        required: ["items"]
    )
}

/// What comes back from a fridge photo.
nonisolated struct AISpottedPantry: Decodable, Sendable {
    var items: [AISpottedItem]
}

nonisolated struct AISpottedItem: Decodable, Sendable {
    var name: String
    var quantity: Double?
    var unit: String?
    var confidence: Double
}

// MARK: - Decoded shape

/// What comes back from an extraction call.
nonisolated struct AIExtractedRecipe: Decodable, Sendable {
    var found: Bool
    var confidence: Double
    var title: String
    var summary: String?
    var servings: Int?
    var prepMinutes: Int?
    var cookMinutes: Int?
    var ingredients: [AIIngredient]
    var steps: [AIStep]
    var tags: [String]
}

nonisolated struct AIIngredient: Decodable, Sendable {
    var rawText: String
    var quantity: Double?
    var unit: String?
    var name: String
    var note: String?
    var isSectionHeader: Bool
}

nonisolated struct AIStep: Decodable, Sendable {
    var text: String
    var durationSeconds: Int?
}
