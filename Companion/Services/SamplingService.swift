import AnyLanguageModel
import Foundation
import MCP

/// The language model provider Companion uses to answer sampling requests.
enum SamplingProvider: String, CaseIterable, Identifiable, Sendable {
    case system
    case openAI
    case anthropic
    case gemini
    case ollama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Apple Foundation Models"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        case .ollama: return "Ollama"
        }
    }

    var needsAPIKey: Bool {
        switch self {
        case .system, .ollama: return false
        case .openAI, .anthropic, .gemini: return true
        }
    }

    var defaultModel: String {
        switch self {
        case .system: return "system"
        case .openAI: return "gpt-6-luna"
        case .anthropic: return "claude-sonnet-5-5"
        case .gemini: return "gemini-3.8-flash"
        case .ollama: return "qwen3.5:4b"
        }
    }
}

/// UserDefaults keys for sampling settings. API keys live in the Keychain.
enum SamplingSettingsKey {
    static let provider = "sampling.provider"
    static let autoApprove = "sampling.autoApprove"
    static let openAIBaseURL = "sampling.openAI.baseURL"

    static func model(for provider: SamplingProvider) -> String {
        "sampling.model.\(provider.rawValue)"
    }
}

/// Answers MCP `sampling/createMessage` requests with a language model.
///
/// The provider and model come from Settings. API keys come from the
/// Keychain. Sampling messages are flattened into a single prompt,
/// so image and audio content appear as text placeholders.
struct SamplingService: Sendable {
    var keychain: KeychainStore = KeychainStore()

    private var defaults: UserDefaults { .standard }

    var provider: SamplingProvider {
        SamplingProvider(rawValue: defaults.string(forKey: SamplingSettingsKey.provider) ?? "")
            ?? .system
    }

    var autoApprove: Bool {
        defaults.bool(forKey: SamplingSettingsKey.autoApprove)
    }

    func modelName(for provider: SamplingProvider) -> String {
        let stored = defaults.string(forKey: SamplingSettingsKey.model(for: provider))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty {
            return stored
        }
        return provider.defaultModel
    }

    /// Whether sampling can run with the current settings.
    var isConfigured: Bool {
        let current = provider
        if current.needsAPIKey {
            return keychain.string(
                for: KeychainStore.apiKeyAccount(provider: current.rawValue)) != nil
        }
        return true
    }

    func generate(
        parameters: MCP.CreateSamplingMessage.Parameters
    ) async throws -> (text: String, model: String) {
        let currentProvider = provider
        let modelName = modelName(for: currentProvider)
        let model = try makeModel(provider: currentProvider, modelName: modelName)

        guard model.isAvailable else {
            throw SamplingError.modelUnavailable(currentProvider.displayName)
        }

        let instructions = parameters.systemPrompt.map { Instructions($0) }
        let session = LanguageModelSession(model: model, instructions: instructions)

        var options = GenerationOptions()
        options.temperature = parameters.temperature
        options.maximumResponseTokens = parameters.maxTokens

        let response = try await session.respond(
            to: Self.promptText(for: parameters.messages),
            options: options
        )
        return (text: response.content, model: modelName)
    }

    private func makeModel(
        provider: SamplingProvider, modelName: String
    ) throws -> any LanguageModel {
        switch provider {
        case .system:
            #if canImport(FoundationModels)
                if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
                    return SystemLanguageModel.default
                }
            #endif
            throw SamplingError.modelUnavailable(provider.displayName)
        case .openAI:
            let apiKey = try requiredAPIKey(for: provider)
            if let baseURLString = defaults.string(forKey: SamplingSettingsKey.openAIBaseURL)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !baseURLString.isEmpty,
                let baseURL = URL(string: baseURLString)
            {
                return OpenAILanguageModel(baseURL: baseURL, apiKey: apiKey, model: modelName)
            }
            return OpenAILanguageModel(apiKey: apiKey, model: modelName)
        case .anthropic:
            let apiKey = try requiredAPIKey(for: provider)
            return AnthropicLanguageModel(apiKey: apiKey, model: modelName)
        case .gemini:
            let apiKey = try requiredAPIKey(for: provider)
            return GeminiLanguageModel(apiKey: apiKey, model: modelName)
        case .ollama:
            return OllamaLanguageModel(model: modelName)
        }
    }

    private func requiredAPIKey(for provider: SamplingProvider) throws -> String {
        guard
            let key = keychain.string(
                for: KeychainStore.apiKeyAccount(provider: provider.rawValue)),
            !key.isEmpty
        else {
            throw SamplingError.missingAPIKey(provider.displayName)
        }
        return key
    }

    // MARK: - Prompt rendering

    static func promptText(for messages: [MCP.Sampling.Message]) -> String {
        if messages.count == 1, let only = messages.first {
            return text(for: only.content)
        }

        return messages.map { message in
            let role = message.role == .user ? "User" : "Assistant"
            return "\(role): \(text(for: message.content))"
        }.joined(separator: "\n\n")
    }

    private static func text(for content: MCP.Sampling.Message.Content) -> String {
        content.asArray.map { block in
            switch block {
            case .text(let text):
                return text
            case .image(_, let mimeType):
                return "[Image: \(mimeType)]"
            case .audio(_, let mimeType):
                return "[Audio: \(mimeType)]"
            case .toolUse(let toolUse):
                return "[Tool use: \(toolUse.name)]"
            case .toolResult(let toolResult):
                let inner = toolResult.content.map { innerBlock in
                    switch innerBlock {
                    case .text(let text):
                        return text
                    case .image(_, let mimeType):
                        return "[Image: \(mimeType)]"
                    case .audio(_, let mimeType):
                        return "[Audio: \(mimeType)]"
                    case .resource(let resource, _, _):
                        return resource.text ?? "[Resource: \(resource.uri)]"
                    case .resourceLink(let uri, let name, _, _, _, _):
                        return "[Resource link: \(name)] \(uri)"
                    }
                }.joined(separator: "\n")
                return "[Tool result]\n\(inner)"
            }
        }.joined(separator: "\n")
    }
}

enum SamplingError: Swift.Error, LocalizedError {
    case missingAPIKey(String)
    case modelUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "No API key is saved for \(provider). Add one in Settings."
        case .modelUnavailable(let provider):
            return "\(provider) is not available on this device."
        }
    }
}
