//
//  GeminiConversation.swift
//  Cozy Crumb
//
//  The shapes a back-and-forth needs, on top of the one-shot extraction calls
//  in GeminiClient.
//
//  The important one is function calling. A Sous Chef that can only talk is a
//  search box with manners: it can tell you to put butter on the list, and you
//  still have to go and do it. Declaring functions lets the model ask the app
//  to do the thing, we run it against the real store, and the result goes back
//  so the reply can say what actually happened rather than what it hoped would.
//
//  Nothing here executes anything. Deciding what a call means and running it is
//  `SousChefToolRunner`'s job, on the main actor, where the store lives.
//

import Foundation

// MARK: - Arbitrary JSON

/// Function arguments arrive as whatever JSON the model felt like sending, so
/// they need a type that can hold any of it.
nonisolated enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Not a JSON value this app understands"
            )
        }
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

extension JSONValue {
    /// Numbers that arrive as strings are common enough from a language model
    /// that reading them leniently is worth more than being strict.
    nonisolated var stringValue: String? {
        switch self {
        case .string(let value): value
        case .number(let value): value == value.rounded() ? String(Int(value)) : String(value)
        case .bool(let value): String(value)
        default: nil
        }
    }

    nonisolated var doubleValue: Double? {
        switch self {
        case .number(let value): value
        case .string(let value): Double(value.replacingOccurrences(of: ",", with: "."))
        default: nil
        }
    }

    nonisolated var intValue: Int? {
        doubleValue.map { Int($0.rounded()) }
    }

    nonisolated var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    nonisolated var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    nonisolated subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }
}

// MARK: - Declaring what the app can do

nonisolated struct GeminiFunctionDeclaration: Encodable, Sendable {
    var name: String
    /// The model chooses a function from this sentence, so it is a prompt, not
    /// documentation. Say when *not* to call it too.
    var description: String
    var parameters: GeminiSchema

    nonisolated init(name: String, description: String, parameters: GeminiSchema) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

nonisolated struct GeminiTool: Encodable, Sendable {
    var functionDeclarations: [GeminiFunctionDeclaration]

    enum CodingKeys: String, CodingKey {
        case functionDeclarations = "function_declarations"
    }

    nonisolated init(functionDeclarations: [GeminiFunctionDeclaration]) {
        self.functionDeclarations = functionDeclarations
    }
}

// MARK: - What comes back

nonisolated struct GeminiFunctionCall: Sendable, Equatable {
    var name: String
    var arguments: [String: JSONValue]

    nonisolated init(name: String, arguments: [String: JSONValue] = [:]) {
        self.name = name
        self.arguments = arguments
    }

    nonisolated subscript(key: String) -> JSONValue? {
        arguments[key]
    }
}

/// One turn from the model: something to say, something to do, or both.
nonisolated struct GeminiReply: Sendable, Equatable {
    var text: String?
    var functionCalls: [GeminiFunctionCall]

    nonisolated init(text: String? = nil, functionCalls: [GeminiFunctionCall] = []) {
        self.text = text
        self.functionCalls = functionCalls
    }

    nonisolated var isEmpty: Bool {
        (text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) && functionCalls.isEmpty
    }
}

// MARK: - Wire shapes

nonisolated struct GeminiFunctionCallPayload: Codable, Sendable {
    var name: String
    var args: JSONValue?
}

nonisolated struct GeminiFunctionResponsePayload: Encodable, Sendable {
    var name: String
    /// Gemini wants an object here, so a plain string result is wrapped.
    var response: [String: String]
}
