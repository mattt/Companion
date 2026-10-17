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

    @Environment(ServerStore.self) private var serverStore
    @State private var testModel = ConnectionTestModel()

    init(
        isPresented: Binding<Bool>, server: Server,
        onSave: @escaping (String, ConfigFile.Entry) -> Void,
        onCancel: (() -> Void)?
    ) {
        self._isPresented = isPresented
        self.server = server
        self.onSave = onSave
        self.onCancel = onCancel

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
    
    private var canTestConnection: Bool {
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
                            .disabled(testModel.isTesting)
                            .onSubmit {
                                if isValid {
                                    saveServer()
                                }
                            }
                            .onChange(of: serverName, initial: true) { _, _ in testModel.reset() }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Transport Type")
                            .font(.headline)

                        TransportTypeSelector(
                            transportType: $transportType,
                            isDisabled: testModel.isTesting
                        )
                        .onChange(of: transportType, initial: true) { _, _ in testModel.reset() }

                        TransportConfigurationFields(
                            transportType: transportType,
                            command: $command,
                            arguments: $arguments,
                            url: $url,
                            isDisabled: testModel.isTesting,
                            onSubmit: {
                                if isValid {
                                    saveServer()
                                }
                            },
                            onChange: { testModel.reset() }
                        )
                    }

                    TestConnectionSection(
                        isTesting: testModel.isTesting,
                        hasSucceeded: testModel.hasSucceeded,
                        errorMessage: testModel.errorMessage,
                        testAction: { testConnection() },
                        cancelAction: { testModel.cancel() }
                    )
                    .disabled(!canTestConnection && !testModel.isTesting)
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
            testModel.reset()
        }
    }

    private func testConnection() {
        let trimmedName = serverName.trimmingCharacters(in: .whitespacesAndNewlines)

        let configuration: ConfigFile.Entry

        #if os(macOS)
            switch transportType {
            case .stdio:
                let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)

                let trimmedArgs = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
                let argArray =
                    trimmedArgs.isEmpty ? [] : trimmedArgs.split(separator: " ").map(String.init)

                configuration = ConfigFile.Entry(stdio: trimmedCommand, arguments: argArray)

            case .http:
                let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)

                configuration = ConfigFile.Entry(http: trimmedUrl)
            }
        #else
            let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedUrl.isEmpty else { return }

            configuration = ConfigFile.Entry(http: trimmedUrl)
        #endif

        let testServer = Server(
            name: trimmedName.isEmpty ? "Test Server" : trimmedName,
            configuration: configuration
        )

        testModel.test(testServer) { server in
            try await serverStore.testConnection(server)
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
