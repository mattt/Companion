import SwiftUI

/// App settings, currently the sampling language model.
///
/// Provider, model names, and the auto-approve choice live in
/// `UserDefaults`. API keys live in the Keychain.
struct SettingsView: View {
    @AppStorage(SamplingSettingsKey.provider) private var providerRawValue: String =
        SamplingProvider.system.rawValue
    @AppStorage(SamplingSettingsKey.autoApprove) private var autoApprove = false
    @AppStorage(SamplingSettingsKey.openAIBaseURL) private var openAIBaseURL = ""

    @AppStorage(SamplingSettingsKey.model(for: .openAI)) private var openAIModel = ""
    @AppStorage(SamplingSettingsKey.model(for: .anthropic)) private var anthropicModel = ""
    @AppStorage(SamplingSettingsKey.model(for: .gemini)) private var geminiModel = ""
    @AppStorage(SamplingSettingsKey.model(for: .ollama)) private var ollamaModel = ""

    @State private var openAIAPIKey = ""
    @State private var anthropicAPIKey = ""
    @State private var geminiAPIKey = ""

    private let keychain = KeychainStore()

    private var provider: SamplingProvider {
        SamplingProvider(rawValue: providerRawValue) ?? .system
    }

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $providerRawValue) {
                    ForEach(SamplingProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }

                providerFields

                Toggle("Approve sampling requests automatically", isOn: $autoApprove)
            } header: {
                Text("Sampling")
            } footer: {
                Text(
                    "Servers can ask Companion for a language model completion. "
                        + "By default, each request appears for your review before "
                        + "Companion generates and sends a response. API keys are "
                        + "stored in your Keychain."
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        #if os(macOS)
            .frame(width: 480)
        #endif
        .onAppear(perform: loadAPIKeys)
    }

    @ViewBuilder
    private var providerFields: some View {
        switch provider {
        case .system:
            if !Self.systemModelSupported {
                Label(
                    "Apple Foundation Models requires a device with Apple Intelligence.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            } else {
                Text("Uses the on-device model. No API key needed.")
                    .foregroundStyle(.secondary)
            }
        case .openAI:
            TextField("Model", text: $openAIModel, prompt: Text(SamplingProvider.openAI.defaultModel))
            SecureField("API Key", text: $openAIAPIKey)
                .onChange(of: openAIAPIKey) { _, newValue in
                    saveAPIKey(newValue, for: .openAI)
                }
            TextField(
                "Base URL (optional)", text: $openAIBaseURL,
                prompt: Text(verbatim: "https://api.openai.com/v1"))
        case .anthropic:
            TextField(
                "Model", text: $anthropicModel,
                prompt: Text(SamplingProvider.anthropic.defaultModel))
            SecureField("API Key", text: $anthropicAPIKey)
                .onChange(of: anthropicAPIKey) { _, newValue in
                    saveAPIKey(newValue, for: .anthropic)
                }
        case .gemini:
            TextField("Model", text: $geminiModel, prompt: Text(SamplingProvider.gemini.defaultModel))
            SecureField("API Key", text: $geminiAPIKey)
                .onChange(of: geminiAPIKey) { _, newValue in
                    saveAPIKey(newValue, for: .gemini)
                }
        case .ollama:
            TextField("Model", text: $ollamaModel, prompt: Text(SamplingProvider.ollama.defaultModel))
            Text("Connects to Ollama on this device. No API key needed.")
                .foregroundStyle(.secondary)
        }
    }

    private static var systemModelSupported: Bool {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
                return true
            }
        #endif
        return false
    }

    private func loadAPIKeys() {
        openAIAPIKey =
            keychain.string(for: KeychainStore.apiKeyAccount(provider: SamplingProvider.openAI.rawValue))
            ?? ""
        anthropicAPIKey =
            keychain.string(
                for: KeychainStore.apiKeyAccount(provider: SamplingProvider.anthropic.rawValue))
            ?? ""
        geminiAPIKey =
            keychain.string(for: KeychainStore.apiKeyAccount(provider: SamplingProvider.gemini.rawValue))
            ?? ""
    }

    private func saveAPIKey(_ value: String, for provider: SamplingProvider) {
        keychain.setString(value, for: KeychainStore.apiKeyAccount(provider: provider.rawValue))
    }
}

#Preview {
    SettingsView()
}
