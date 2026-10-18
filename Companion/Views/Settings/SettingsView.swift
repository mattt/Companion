import MCP
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// App settings: appearance, connections, sampling, safety, and data.
///
/// Choices live in `UserDefaults`. Secrets live in the Keychain.
struct SettingsView: View {
    @Environment(ServerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    // General
    @AppStorage(AppSettingsKey.appearance) private var appearanceRawValue: String =
        AppAppearance.system.rawValue
    @AppStorage(AppSettingsKey.autoConnectOnLaunch) private var autoConnectOnLaunch = false
    @AppStorage(AppSettingsKey.defaultLogLevel) private var defaultLogLevelRawValue: String =
        MCP.LogLevel.debug.rawValue

    // Sampling
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

    // Safety
    @AppStorage(AppSettingsKey.warnDestructiveToolCalls) private var warnDestructive = true
    @AppStorage(AppSettingsKey.requestTimeoutMinutes) private var requestTimeoutMinutes = 0

    // Data
    @State private var showingClearSecretsConfirmation = false
    @State private var didClearSecrets = false

    private let keychain = KeychainStore()

    private var provider: SamplingProvider {
        SamplingProvider(rawValue: providerRawValue) ?? .system
    }

    var body: some View {
        Form {
            generalSection
            samplingSection
            safetySection
            dataSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onEscapeKey {
            #if os(macOS)
                NSApp.keyWindow?.performClose(nil)
            #else
                dismiss()
            #endif
        }
        #if os(macOS)
            .frame(width: 480)
        #endif
        .onAppear(perform: loadAPIKeys)
        .confirmationDialog(
            "Clear saved secrets?",
            isPresented: $showingClearSecretsConfirmation
        ) {
            Button("Clear Secrets", role: .destructive) {
                store.clearAllSecrets()
                openAIAPIKey = ""
                anthropicAPIKey = ""
                geminiAPIKey = ""
                didClearSecrets = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This deletes sampling API keys, bearer tokens, "
                    + "and OAuth secrets and tokens from your Keychain. "
                    + "Servers stay in the list.")
        }
    }

    // MARK: - General

    private var generalSection: some View {
        Section("General") {
            Picker("Appearance", selection: $appearanceRawValue) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.displayName).tag(appearance.rawValue)
                }
            }

            Toggle("Connect to servers on launch", isOn: $autoConnectOnLaunch)

            Picker("Default server log level", selection: $defaultLogLevelRawValue) {
                ForEach(MCP.LogLevel.allCases, id: \.self) { level in
                    Text(level.displayName).tag(level.rawValue)
                }
            }
        }
    }

    // MARK: - Sampling

    private var samplingSection: some View {
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

    // MARK: - Safety

    private var safetySection: some View {
        Section {
            Toggle("Warn before destructive tool calls", isOn: $warnDestructive)

            Picker("Sampling and elicitation timeout", selection: $requestTimeoutMinutes) {
                Text("Never").tag(0)
                Text("1 minute").tag(1)
                Text("5 minutes").tag(5)
                Text("15 minutes").tag(15)
            }
        } header: {
            Text("Safety")
        } footer: {
            Text(
                "The warning appears for tools the server annotates as destructive. "
                    + "When a timeout is set, Companion declines sampling requests "
                    + "and cancels elicitation requests that go unanswered.")
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section("Data") {
            LabeledContent("Configuration file") {
                Text(FileServerConfigStore.defaultFileURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            #if os(macOS)
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [FileServerConfigStore.defaultFileURL])
                }
            #endif

            Button("Clear Saved Secrets…", role: .destructive) {
                showingClearSecretsConfirmation = true
            }

            if didClearSecrets {
                Label("Secrets cleared", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
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
        didClearSecrets = false
    }
}

private extension View {
    /// Runs an action when the user presses Escape.
    /// `onExitCommand` exists only on macOS, so other platforms keep
    /// their default dismissal behavior.
    @ViewBuilder
    func onEscapeKey(perform action: @escaping () -> Void) -> some View {
        #if os(macOS)
            onExitCommand(perform: action)
        #else
            self
        #endif
    }
}

#Preview {
    SettingsView()
        .environment(ServerStore())
}
