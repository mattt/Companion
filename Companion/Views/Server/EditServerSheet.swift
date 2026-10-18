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
    @State private var envRows: [KeyValueRow]
    @State private var headerRows: [KeyValueRow]
    @State private var bearerToken: String
    @State private var useOAuth: Bool
    @State private var oauthClientID: String
    @State private var oauthClientSecret: String
    @State private var rootRows: [RootRow]
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
        self._envRows = State(initialValue: KeyValueRow.rows(from: config.env))
        self._headerRows = State(initialValue: KeyValueRow.rows(from: config.headers))

        let settingsStore = ServerSettingsStore()
        let keychain = KeychainStore()
        let sidecar = settingsStore.settings(forServerNamed: server.name)
        self._rootRows = State(initialValue: RootRow.rows(from: sidecar.roots))
        self._useOAuth = State(initialValue: sidecar.useOAuth)
        self._oauthClientID = State(initialValue: sidecar.oauthClientID ?? "")
        self._bearerToken = State(
            initialValue: keychain.string(
                for: KeychainStore.bearerTokenAccount(serverName: server.name)) ?? "")
        self._oauthClientSecret = State(
            initialValue: keychain.string(
                for: KeychainStore.oauthClientSecretAccount(serverName: server.name)) ?? "")
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
                ScrollView {
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

                    if transportType == .stdio {
                        KeyValueEditorView(
                            title: "Environment Variables",
                            rows: $envRows,
                            keyPlaceholder: "Variable",
                            isDisabled: testModel.isTesting
                        )
                    } else {
                        KeyValueEditorView(
                            title: "Headers",
                            rows: $headerRows,
                            keyPlaceholder: "Header",
                            isDisabled: testModel.isTesting
                        )

                        HTTPAuthFields(
                            bearerToken: $bearerToken,
                            useOAuth: $useOAuth,
                            oauthClientID: $oauthClientID,
                            oauthClientSecret: $oauthClientSecret,
                            isDisabled: testModel.isTesting
                        )
                    }

                    RootsEditorView(rows: $rootRows, isDisabled: testModel.isTesting)

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
                }

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

                    Section {
                        KeyValueEditorView(
                            title: "Headers", rows: $headerRows, keyPlaceholder: "Header")
                    }

                    Section {
                        HTTPAuthFields(
                            bearerToken: $bearerToken,
                            useOAuth: $useOAuth,
                            oauthClientID: $oauthClientID,
                            oauthClientSecret: $oauthClientSecret
                        )
                    }

                    Section {
                        RootsEditorView(rows: $rootRows)
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
            .frame(width: 540, height: 720)
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

    private func currentConfiguration() -> ConfigFile.Entry? {
        #if os(macOS)
            switch transportType {
            case .stdio:
                let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedCommand.isEmpty else { return nil }

                let trimmedArgs = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
                let argArray =
                    trimmedArgs.isEmpty ? [] : trimmedArgs.split(separator: " ").map(String.init)

                return .stdio(
                    .init(
                        command: trimmedCommand,
                        args: argArray,
                        env: KeyValueRow.dictionary(from: envRows)))

            case .http:
                let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedUrl.isEmpty else { return nil }

                return .streamableHTTP(
                    .init(url: trimmedUrl, headers: KeyValueRow.dictionary(from: headerRows)))
            }
        #else
            let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedUrl.isEmpty else { return nil }

            return .streamableHTTP(
                .init(url: trimmedUrl, headers: KeyValueRow.dictionary(from: headerRows)))
        #endif
    }

    /// Saves sidecar settings under the server's current name.
    /// `updateServer` migrates them if the user renames the server.
    private func saveSidecar() {
        let clientID = oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let settings = ServerSidecarSettings(
            roots: RootRow.roots(from: rootRows),
            useOAuth: useOAuth,
            oauthClientID: clientID.isEmpty ? nil : clientID
        )
        serverStore.saveSidecarSettings(
            settings,
            bearerToken: bearerToken.isEmpty ? nil : bearerToken,
            oauthClientSecret: oauthClientSecret.isEmpty ? nil : oauthClientSecret,
            forServerNamed: server.name
        )
    }

    private func testConnection() {
        guard let configuration = currentConfiguration() else { return }

        saveSidecar()
        let testServer = Server(name: server.name, configuration: configuration)

        testModel.test(testServer) { server in
            try await serverStore.testConnection(server)
        }
    }

    private func saveServer() {
        let trimmedName = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let configuration = currentConfiguration() else { return }

        saveSidecar()
        onSave(trimmedName, configuration)
    }


}
