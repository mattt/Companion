import SwiftUI

struct AddServerSheet: View {
    @Binding var isPresented: Bool
    let onAdd: (String, ConfigFile.Entry) -> Void
    let onCancel: (() -> Void)?

    @State private var serverName = ""
    #if os(macOS)
        @State private var transportType: TransportType = .stdio
    #else
        @State private var transportType: TransportType = .http
    #endif
    @State private var command = ""
    @State private var arguments = ""
    @State private var url = ""
    @State private var envRows: [KeyValueRow] = []
    @State private var headerRows: [KeyValueRow] = []
    @State private var bearerToken = ""
    @State private var useOAuth = false
    @State private var oauthClientID = ""
    @State private var oauthClientSecret = ""
    @State private var rootRows: [RootRow] = []
    @FocusState private var isNameFieldFocused: Bool

    @Environment(ServerStore.self) private var serverStore
    @State private var testModel = ConnectionTestModel()

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
                title: "Add Server",
                subtitle: "Enter the details of the MCP server you want to connect to"
            )

            // Form
            #if os(macOS)
                ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Server Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server Name")
                            .font(.headline)
                        TextField("Server Name", text: $serverName)
                            .focused($isNameFieldFocused)
                            .textFieldStyle(.roundedBorder)
                            .disabled(testModel.isTesting)
                            .onSubmit {
                                if isValid {
                                    addServer()
                                }
                            }
                            .onChange(of: serverName, initial: true) { _, _ in testModel.reset() }
                    }

                    // Transport Configuration
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
                                    addServer()
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

                    // Connection Test Section
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
                            .disabled(testModel.isTesting)
                            .onSubmit {
                                if isValid {
                                    addServer()
                                }
                            }
                            .onChange(of: serverName) { _, _ in testModel.reset() }
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
                        .disabled(testModel.isTesting)
                        .onSubmit {
                            if isValid {
                                addServer()
                            }
                        }
                        .onChange(of: url) { _, _ in testModel.reset() }
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
                saveAction: addServer,
                saveTitle: "Add Server",
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

    private func saveSidecar(forName name: String) {
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
            forServerNamed: name
        )
    }

    private func addServer() {
        let trimmedName = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let configuration = currentConfiguration() else { return }

        saveSidecar(forName: trimmedName)
        onAdd(trimmedName, configuration)
    }

    private func testConnection() {
        let trimmedName = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let configuration = currentConfiguration() else { return }

        let name = trimmedName.isEmpty ? "Test Server" : trimmedName
        saveSidecar(forName: name)

        let testServer = Server(name: name, configuration: configuration)

        testModel.test(testServer) { server in
            try await serverStore.testConnection(server)
        }
    }
}

#Preview {
    AddServerSheet(isPresented: .constant(true), onAdd: { _, _ in }, onCancel: {})
        .environment(ServerStore())
}
