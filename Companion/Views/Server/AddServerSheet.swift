import ComposableArchitecture
import Dependencies
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
    @FocusState private var isNameFieldFocused: Bool

    @State private var store = Store(initialState: ConnectionTestFeature.State()) {
        ConnectionTestFeature()
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
                title: "Add Server",
                subtitle: "Enter the details of the MCP server you want to connect to"
            )

            // Form
            #if os(macOS)
                VStack(alignment: .leading, spacing: 20) {
                    // Server Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server Name")
                            .font(.headline)
                        TextField("Server Name", text: $serverName)
                            .focused($isNameFieldFocused)
                            .textFieldStyle(.roundedBorder)
                            .disabled(store.isTesting)
                            .onSubmit {
                                if isValid {
                                    addServer()
                                }
                            }
                            .onChange(of: serverName, initial: true) { _, _ in store.send(.reset) }
                    }

                    // Transport Configuration
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Transport Type")
                            .font(.headline)

                        TransportTypeSelector(
                            transportType: $transportType,
                            isDisabled: store.isTesting
                        )
                        .onChange(of: transportType, initial: true) { _, _ in store.send(.reset) }

                        TransportConfigurationFields(
                            transportType: transportType,
                            command: $command,
                            arguments: $arguments,
                            url: $url,
                            isDisabled: store.isTesting,
                            onSubmit: {
                                if isValid {
                                    addServer()
                                }
                            },
                            onChange: { store.send(.reset) }
                        )
                    }

                    // Connection Test Section
                    TestConnectionSection(
                        isTesting: store.isTesting,
                        hasSucceeded: store.hasSucceeded,
                        errorMessage: store.errorMessage,
                        testAction: { testConnection() },
                        cancelAction: { store.send(.cancelTest) }
                    )
                    .disabled(!isValid && !store.isTesting)
                }
                .padding(.horizontal)
                .padding(.vertical, 20)

                Spacer(minLength: 20)
            #else
                Form {
                    Section {
                        TextField("Server Name", text: $serverName)
                            .focused($isNameFieldFocused)
                            .disabled(store.isTesting)
                            .onSubmit {
                                if isValid {
                                    addServer()
                                }
                            }
                            .onChange(of: serverName) { _, _ in store.send(.reset) }
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
                        .disabled(store.isTesting)
                        .onSubmit {
                            if isValid {
                                addServer()
                            }
                        }
                        .onChange(of: url) { _, _ in store.send(.reset) }
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
            .frame(width: 500, height: 600)
        #else
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
        .background(.background)
        .onAppear {
            isNameFieldFocused = true
        }
        .onDisappear {
            store.send(.reset)
        }
    }

    private func addServer() {
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

        onAdd(trimmedName, configuration)
    }

    private func testConnection() {
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

        let testServer = Server(
            name: trimmedName,
            configuration: configuration
        )

        store.send(.testConnection(testServer))
    }
}

#Preview {
    AddServerSheet(isPresented: .constant(true), onAdd: { _, _  in }, onCancel: {  })
}
