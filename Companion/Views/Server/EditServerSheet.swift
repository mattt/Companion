import ComposableArchitecture
import SwiftUI

struct EditServerSheet: View {
    @Binding var isPresented: Bool
    let server: Server
    let onSave: (String, ConfigFile.Entry) -> Void
    let onCancel: (() -> Void)?

    @State private var serverName: String
    @State private var transportType: TransportType
    @State private var command: String
    @State private var arguments: String
    @State private var url: String
    @FocusState private var isNameFieldFocused: Bool

    let store: StoreOf<EditServerFeature>

    init(
        isPresented: Binding<Bool>, server: Server,
        onSave: @escaping (String, ConfigFile.Entry) -> Void,
        onCancel: (() -> Void)?,
        store: StoreOf<EditServerFeature>
    ) {
        self._isPresented = isPresented
        self.server = server
        self.onSave = onSave
        self.onCancel = onCancel
        self.store = store

        // Initialize state from server
        let config = server.configuration
        self._serverName = State(initialValue: server.name)
        
        // Convert ConfigFile.Entry to TransportType
        let transportType: TransportType = {
            switch config {
            case .stdio: return .stdio
            case .sse, .streamableHTTP: return .http
            }
        }()
        
        self._transportType = State(initialValue: transportType)
        self._command = State(initialValue: config.command ?? "")
        self._arguments = State(
            initialValue: config.arguments?.joined(separator: " ") ?? "")
        self._url = State(initialValue: config.url ?? "")
    }

    private var isValid: Bool {
        let trimmedName = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        #if os(macOS)
            switch transportType {
            case .stdio:
                return !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .http:
                return !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        #else
            return !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ServerFormHeader(
                icon: "mcp.fill",
                title: "Edit Server",
                subtitle: "Update the details of your MCP server"
            )

            // Form
            #if os(macOS)
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server Name")
                            .font(.headline)
                        TextField("Server Name", text: $serverName)
                            .focused($isNameFieldFocused)
                            .textFieldStyle(.roundedBorder)
                            .disabled(store.connectionTest.isTesting)
                            .onSubmit {
                                if isValid {
                                    saveServer()
                                }
                            }
                            .onChange(of: serverName, initial: true) { _, _ in store.send(.connectionTest(.reset)) }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Transport Type")
                            .font(.headline)

                        TransportTypeSelector(
                            transportType: $transportType,
                            isDisabled: store.connectionTest.isTesting
                        )
                        .onChange(of: transportType, initial: true) { _, _ in store.send(.connectionTest(.reset)) }

                        TransportConfigurationFields(
                            transportType: transportType,
                            command: $command,
                            arguments: $arguments,
                            url: $url,
                            isDisabled: store.connectionTest.isTesting,
                            onSubmit: {
                                if isValid {
                                    saveServer()
                                }
                            },
                            onChange: { store.send(.connectionTest(.reset)) }
                        )
                    }

                    TestConnectionSection(
                        isTesting: store.connectionTest.isTesting,
                        hasSucceeded: store.connectionTest.hasSucceeded,
                        errorMessage: store.connectionTest.errorMessage,
                        testAction: { 
                            // Update store state and trigger test
                            store.send(.testConnection)
                        },
                        cancelAction: { store.send(.connectionTest(.cancelTest)) }
                    )
                    .disabled(!isValid && !store.connectionTest.isTesting)
                }
                .padding(.horizontal)
                .padding(.vertical, 20)

                Spacer(minLength: 20)
            #else
                Form {
                    Section {
                        TextField("Server Name", text: $serverName)
                            .focused($isNameFieldFocused)
                            .onSubmit {
                                if isValid {
                                    saveServer()
                                }
                            }
                    }

                    Section(
                        header: Text("Server URL"),
                        footer: Text(
                            "STDIO transport (local command execution) is only supported on macOS. On iOS, use HTTP transport to connect to remote MCP servers."
                        )
                        .font(.caption)
                    ) {
                        TextField(
                            "Server URL", text: $url,
                            prompt: Text(verbatim: "https://example.com/mcp")
                        )
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .onSubmit {
                            if isValid {
                                saveServer()
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            #endif

            // Buttons
            ServerFormButtons(
                cancelAction: { onCancel?() ?? { isPresented = false }() },
                saveAction: saveServer,
                saveTitle: "Save Changes",
                isValid: isValid
            )
        }
        #if os(macOS)
            .frame(width: 500, height: 600)
        #else
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
        .background(.background)
        .onAppear {
            isNameFieldFocused = true
        }
        .onDisappear {
            store.send(.connectionTest(.reset))
        }
    }

    private func saveServer() {
        let trimmedName = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let configuration: ConfigFile.Entry

        #if os(macOS)
            switch transportType {
            case .stdio:
                let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedCommand.isEmpty else { return }

                let trimmedArgs = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
                let argArray =
                    trimmedArgs.isEmpty ? [] : trimmedArgs.split(separator: " ").map(String.init)

                configuration = ConfigFile.Entry(stdio: trimmedCommand, arguments: argArray)

            case .http:
                let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedUrl.isEmpty else { return }

                configuration = ConfigFile.Entry(http: trimmedUrl)
            }
        #else
            let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedUrl.isEmpty else { return }

            configuration = ConfigFile.Entry(http: trimmedUrl)
        #endif

        onSave(trimmedName, configuration)
    }


}
