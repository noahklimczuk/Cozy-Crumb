//
//  GeminiClient.swift
//  Cozy Crumb
//
//  The only place in the app that talks to Gemini.
//
//  Two rules that are not negotiable:
//    1. The key goes in the x-goog-api-key header, never the query string.
//    2. Request and response bodies are never logged, in any build. Status
//       codes and finish reasons are fine; content is not.
//

import Foundation
import os

// MARK: - Request shapes

// These are `nonisolated` because the target defaults actor isolation to
// MainActor, and Codable's synthesised members must be nonisolated to satisfy
// the protocol and to be usable from this actor.

nonisolated struct GeminiRequest: Encodable, Sendable {
    var systemInstruction: GeminiContent? = nil
    var contents: [GeminiContent]
    var generationConfig: GeminiGenerationConfig? = nil
    var safetySettings: [GeminiSafetySetting]? = nil

    enum CodingKeys: String, CodingKey {
        case systemInstruction = "system_instruction"
        case contents
        case generationConfig
        case safetySettings
    }
}

nonisolated struct GeminiContent: Encodable, Sendable {
    /// "user" or "model". Omitted for the system instruction.
    var role: String? = nil
    var parts: [GeminiPart]
}

nonisolated struct GeminiPart: Encodable, Sendable {
    var text: String? = nil
    var inlineData: GeminiInlineData? = nil
    var fileData: GeminiFileData? = nil

    enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inline_data"
        case fileData = "file_data"
    }

    nonisolated static func text(_ value: String) -> GeminiPart {
        GeminiPart(text: value)
    }

    /// Base64 image bytes. Put image parts *before* the text part — Gemini
    /// attends to them better that way.
    nonisolated static func image(jpeg data: Data) -> GeminiPart {
        GeminiPart(inlineData: GeminiInlineData(
            mimeType: "image/jpeg",
            data: data.base64EncodedString()
        ))
    }

    /// A YouTube URL that Gemini fetches and watches server-side. This is the
    /// only platform where the video itself can be analysed — there is no
    /// equivalent for TikTok, Instagram or Facebook.
    nonisolated static func youTube(_ url: URL) -> GeminiPart {
        GeminiPart(fileData: GeminiFileData(fileUri: url.absoluteString))
    }
}

nonisolated struct GeminiInlineData: Encodable, Sendable {
    var mimeType: String
    var data: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

nonisolated struct GeminiFileData: Encodable, Sendable {
    var fileUri: String
    var mimeType: String? = nil

    enum CodingKeys: String, CodingKey {
        case fileUri = "file_uri"
        case mimeType = "mime_type"
    }
}

nonisolated struct GeminiGenerationConfig: Encodable, Sendable {
    var temperature: Double? = nil
    var maxOutputTokens: Int? = nil
    var responseMimeType: String? = nil
    var responseSchema: GeminiSchema? = nil
    var thinkingConfig: GeminiThinkingConfig? = nil
}

/// Gemini 3 models think before they answer, and — this is the part that
/// bites — thinking tokens come out of the same maxOutputTokens budget as the
/// visible answer. At the default HIGH level, reasoning expands to fill
/// whatever budget it is given, so a small cap returns MAX_TOKENS and no text
/// at all.
///
/// Recipe extraction is a mechanical task, so LOW keeps it fast and leaves the
/// budget for the actual output.
nonisolated struct GeminiThinkingConfig: Encodable, Sendable {
    var thinkingLevel: String

    nonisolated static let low = GeminiThinkingConfig(thinkingLevel: "LOW")
}

nonisolated struct GeminiSafetySetting: Encodable, Sendable {
    var category: String
    var threshold: String

    /// Cooking text trips default safety filters more often than you would
    /// think — knives, raw meat, alcohol, "kill the heat". Loosened to
    /// BLOCK_ONLY_HIGH so ordinary recipes get through.
    nonisolated static let cookingDefaults: [GeminiSafetySetting] = [
        "HARM_CATEGORY_HARASSMENT",
        "HARM_CATEGORY_HATE_SPEECH",
        "HARM_CATEGORY_SEXUALLY_EXPLICIT",
        "HARM_CATEGORY_DANGEROUS_CONTENT"
    ].map { GeminiSafetySetting(category: $0, threshold: "BLOCK_ONLY_HIGH") }
}

// MARK: - Response shapes

nonisolated struct GeminiResponse: Decodable, Sendable {
    var candidates: [GeminiCandidate]?
    var promptFeedback: GeminiPromptFeedback?
}

nonisolated struct GeminiCandidate: Decodable, Sendable {
    var content: GeminiResponseContent?
    var finishReason: String?
}

nonisolated struct GeminiResponseContent: Decodable, Sendable {
    var parts: [GeminiResponsePart]?
}

nonisolated struct GeminiResponsePart: Decodable, Sendable {
    var text: String?
}

nonisolated struct GeminiPromptFeedback: Decodable, Sendable {
    var blockReason: String?
}

nonisolated struct GeminiErrorEnvelope: Decodable, Sendable {
    var error: GeminiErrorBody
}

nonisolated struct GeminiErrorBody: Decodable, Sendable {
    var code: Int?
    var status: String?
}

// MARK: - Client

actor GeminiClient {

    private let session: URLSession
    private let keychain: KeychainStore

    /// Vision and video calls are slow; text is not.
    static let textTimeout: TimeInterval = 30
    static let visionTimeout: TimeInterval = 90

    init(session: URLSession? = nil, keychain: KeychainStore = .shared) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = Self.visionTimeout
            configuration.timeoutIntervalForResource = Self.visionTimeout + 30
            self.session = URLSession(configuration: configuration)
        }
        self.keychain = keychain
    }

    nonisolated var hasAPIKey: Bool {
        keychain.hasValue(for: .geminiAPIKey)
    }

    // MARK: - Generate

    /// One-shot generation. Returns the concatenated text of the first
    /// candidate, or a typed error with copy already written for the user.
    func generate(
        model: GeminiModel,
        systemInstruction: String?,
        parts: [GeminiPart],
        schema: GeminiSchema? = nil,
        temperature: Double = 0.4,
        maxOutputTokens: Int = 8192,
        thinking: GeminiThinkingConfig? = .low,
        timeout: TimeInterval = GeminiClient.textTimeout
    ) async -> Result<String, CozyError> {
        guard let apiKey = keychain.string(for: .geminiAPIKey) else {
            return .failure(.missingAPIKey)
        }

        guard let url = GeminiEndpoint.generateContent(model: model) else {
            return .failure(.badURL)
        }

        func makeBody(includingThinking: Bool) -> Data? {
            let request = GeminiRequest(
                systemInstruction: systemInstruction.map {
                    GeminiContent(role: nil, parts: [.text($0)])
                },
                contents: [GeminiContent(role: "user", parts: parts)],
                generationConfig: GeminiGenerationConfig(
                    temperature: temperature,
                    maxOutputTokens: maxOutputTokens,
                    responseMimeType: schema == nil ? nil : "application/json",
                    responseSchema: schema,
                    thinkingConfig: includingThinking ? thinking : nil
                ),
                safetySettings: GeminiSafetySetting.cookingDefaults
            )
            return try? JSONEncoder().encode(request)
        }

        guard let body = makeBody(includingThinking: true) else {
            return .failure(.decodingFailed)
        }

        let result = await send(body: body, to: url, apiKey: apiKey, timeout: timeout)

        // The thinking parameter has changed shape across model generations.
        // If the request was rejected as malformed, try once more without it
        // rather than making the user debug Google's schema. If the plain
        // request is rejected too, the request shape was never the problem and
        // the key is the likely culprit.
        if case .failure(.aiRequestRejected) = result, thinking != nil {
            Log.ai.info("Request rejected; retrying without thinkingConfig")

            guard let plainBody = makeBody(includingThinking: false) else {
                return .failure(.decodingFailed)
            }

            let retry = await send(body: plainBody, to: url, apiKey: apiKey, timeout: timeout)

            if case .failure(.aiRequestRejected) = retry {
                return .failure(.invalidAPIKey)
            }
            return retry
        }

        return result
    }

    // MARK: - Transport

    private func send(
        body: Data,
        to url: URL,
        apiKey: String,
        timeout: TimeInterval,
        attempt: Int = 1
    ) async -> Result<String, CozyError> {
        let maxAttempts = 3

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.unknown("response"))
            }

            // 429 is routine on the free tier, not exceptional. Retry quietly
            // before ever showing the user an error.
            if http.statusCode == 429 || (500..<600).contains(http.statusCode) {
                guard attempt < maxAttempts else {
                    return .failure(http.statusCode == 429 ? .rateLimited : .httpStatus(http.statusCode))
                }

                Log.ai.info("Gemini \(http.statusCode, privacy: .public), retry \(attempt, privacy: .public)")
                try? await Task.sleep(for: .seconds(backoffSeconds(for: attempt)))

                return await send(
                    body: body,
                    to: url,
                    apiKey: apiKey,
                    timeout: timeout,
                    attempt: attempt + 1
                )
            }

            guard (200..<300).contains(http.statusCode) else {
                return .failure(mapHTTPError(status: http.statusCode, data: data))
            }

            return decode(data)
        } catch let error as URLError {
            return .failure(.from(urlError: error))
        } catch {
            return .failure(.unknown("network"))
        }
    }

    /// Exponential with jitter, so a burst of requests does not retry in step.
    private func backoffSeconds(for attempt: Int) -> Double {
        let base = pow(2.0, Double(attempt))
        return base + Double.random(in: 0...0.75)
    }

    // MARK: - Decoding

    private func decode(_ data: Data) -> Result<String, CozyError> {
        guard let response = try? JSONDecoder().decode(GeminiResponse.self, from: data) else {
            return .failure(.decodingFailed)
        }

        if let blockReason = response.promptFeedback?.blockReason, !blockReason.isEmpty {
            Log.ai.info("Prompt blocked: \(blockReason, privacy: .public)")
            return .failure(.blockedBySafety)
        }

        guard let candidate = response.candidates?.first else {
            return .failure(.emptyResponse)
        }

        switch candidate.finishReason?.uppercased() {
        case "SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST":
            return .failure(.blockedBySafety)
        case "MAX_TOKENS":
            // Partial output is worse than none for structured extraction —
            // the JSON will be truncated and unparseable.
            return .failure(.responseTruncated)
        case "RECITATION":
            return .failure(.blockedBySafety)
        default:
            break
        }

        let text = (candidate.content?.parts ?? [])
            .compactMap(\.text)
            .joined()

        guard !text.isEmpty else {
            return .failure(.emptyResponse)
        }

        return .success(text)
    }

    private func mapHTTPError(status: Int, data: Data) -> CozyError {
        let apiStatus = (try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: data))?
            .error.status?.uppercased()

        // Status string only — the message can echo request content.
        Log.ai.error("Gemini HTTP \(status, privacy: .public) \(apiStatus ?? "-", privacy: .public)")

        switch status {
        case 400:
            // A bad key and a malformed request both come back as
            // INVALID_ARGUMENT, and the message that would distinguish them is
            // exactly the thing we refuse to log. generate() disambiguates by
            // retrying with a simpler body.
            return .aiRequestRejected
        case 401, 403:
            return .modelUnavailable
        case 404:
            return .modelUnavailable
        default:
            return .httpStatus(status)
        }
    }
}

// MARK: - JSON helpers

extension GeminiClient {
    /// Strips markdown fences the model sometimes adds even under a schema.
    nonisolated static func stripJSONFences(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("```") else { return trimmed }

        // Drop the opening fence and any language tag on that line.
        if let firstNewline = trimmed.firstIndex(of: "\n") {
            trimmed = String(trimmed[trimmed.index(after: firstNewline)...])
        }
        if let fenceRange = trimmed.range(of: "```", options: .backwards) {
            trimmed = String(trimmed[trimmed.startIndex..<fenceRange.lowerBound])
        }

        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
