import ComposableArchitecture
import MCP
import SwiftUI

struct ServerDetailView: View {
    let store: StoreOf<ServerDetailFeature>

    @State private var showingActionSheet = false

    private var server: Server { store.server }
    private var isConnecting: Bool { store.isConnecting }
    private var isConnected: Bool { store.isConnected }

    var body: some View {
        #if os(iOS)
            ScrollView {
                ServerInformationView(
                    server: server,
                    serverStatus: server.status,
                    isConnecting: isConnecting
                )
            }
            .navigationTitle(server.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            store.send(.edit)
                        } label: {
                            Label("Edit Server", systemImage: "square.and.pencil")
                        }

                        Button {
                            copyServerInfo()
                        } label: {
                            Label("Copy Server Info", systemImage: "doc.on.doc")
                        }

                        if isConnected {
                            Button {
                                store.send(.restart)
                            } label: {
                                Label("Restart", systemImage: "arrow.clockwise")
                            }
                        }

                        Button {
                            if isConnecting {
                                store.send(.cancel)
                            } else if isConnected {
                                store.send(.disconnect)
                            } else {
                                store.send(.connect)
                            }
                        } label: {
                            Label(
                                isConnecting ? "Cancel" : (isConnected ? "Disconnect" : "Connect"),
                                systemImage: isConnected ? "bolt.fill" : "bolt")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Server Actions", isPresented: $showingActionSheet) {
                Button("Edit Server") {
                    store.send(.edit)
                }

                if isConnected {
                    Button("Restart") {
                        store.send(.restart)
                    }
                }

                Button(isConnected ? "Disconnect" : "Connect") {
                    if isConnected {
                        store.send(.disconnect)
                    } else {
                        store.send(.connect)
                    }
                }

                Button("Cancel", role: .cancel) {}
            }
        #else
            VStack(spacing: 0) {
                if isConnected {
                    ScrollView {
                        ServerInformationView(
                            server: server,
                            serverStatus: server.status,
                            isConnecting: isConnecting
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "bolt")
                            .font(.system(size: 48))
                            .foregroundColor(isConnecting ? .orange : .secondary)
                            .symbolEffect(
                                .pulse, options: isConnecting ? .repeat(.continuous) : .nonRepeating
                            )
                            .id("connecting-\(isConnecting)")

                        Text(isConnecting ? "Connecting..." : "Disconnected")
                            .font(.title2)
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            if isConnecting {
                                Button {
                                    store.send(.cancel)
                                } label: {
                                    Text("Cancel")
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Button {
                                    store.send(.connect)
                                } label: {
                                    Text("Connect")
                                }
                                .buttonStyle(.borderedProminent)

                                Button {
                                    store.send(.edit)
                                } label: {
                                    Text("Edit")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .toolbar {
                #if os(macOS)
//                    if #available(macOS 26.0, *) {
//                        ToolbarItemGroup(placement: .navigation) {
//                            ServerInfoToolbarContent(server: server)
//                                .padding(.horizontal, 8)
//                        }
//                        .sharedBackgroundVisibility(Visibility.hidden)
//                    } else {
                        ToolbarItemGroup(placement: .navigation) {
                            ServerInfoToolbarContent(server: server)
                            Spacer()
                        }
//                    }
                #else
                    ToolbarItemGroup(placement: .navigation) {
                        ServerInfoToolbarContent(server: server)
                        Spacer()
                    }
                #endif
                
                // Connection status as separate toolbar item
                ToolbarItem(placement: .automatic) {
                    ServerConnectionStatus(
                        isConnected: isConnected,
                        isConnecting: isConnecting
                    )
                }
                
                // Action menu as separate toolbar item
                ToolbarItem(placement: .primaryAction) {
                    ServerActionMenu(
                        isConnected: isConnected,
                        isConnecting: isConnecting,
                        onConnect: { store.send(.connect) },
                        onDisconnect: { store.send(.disconnect) },
                        onCancel: { store.send(.cancel) },
                        onEdit: { store.send(.edit) }
                    )
                }
            }
        #endif
    }

    private func copyServerInfo() {
        let serverInfo = "{}"

        #if os(iOS)
            UIPasteboard.general.string = serverInfo
        #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(serverInfo, forType: .string)
        #endif
    }
}

private struct ServerInfoToolbarContent: View {
    let server: Server

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(server.name)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(1)

            Text(server.configuration.displayValue)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(
                    server.configuration.displayValue.hasPrefix("http")
                        ? .tail : .middle)
        }
    }
}

private struct ServerConnectionStatus: View {
    let isConnected: Bool
    let isConnecting: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(
                systemName: isConnecting
                    ? "clock.circle.fill" : (isConnected ? "circle.fill" : "circle")
            )
            .foregroundColor(isConnecting ? .orange : (isConnected ? .green : .red))
            .font(.system(size: 10))
            Text(
                isConnecting
                    ? "Connecting..." : (isConnected ? "Connected" : "Disconnected")
            )
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }
}

private struct ServerActionMenu: View {
    let isConnected: Bool
    let isConnecting: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onCancel: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Menu {
            Button {
                onEdit()
            } label: {
                Label("Edit Server", systemImage: "square.and.pencil")
            }

            if isConnected {
                Divider()

                Button {
                    Task {
                        onDisconnect()
                        try await Task.sleep(for: .milliseconds(100))
                        onConnect()
                    }
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }

                Button {
                    onDisconnect()
                } label: {
                    Label("Disconnect", systemImage: "bolt.fill")
                }
            } else {
                Divider()

                Button {
                    if isConnecting {
                        onCancel()
                    } else {
                        onConnect()
                    }
                } label: {
                    Text(isConnecting ? "Cancel" : "Connect")
                }
                .buttonStyle(.borderedProminent)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}



struct ServerInformationView: View {
    let server: Server
    let serverStatus: Server.Status
    let isConnecting: Bool

    private var isConnected: Bool {
        serverStatus.isConnected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            #if os(iOS)
                // Connection Status Card
                VStack(alignment: .leading, spacing: 12) {
                    Label("Connection", systemImage: "network")
                        .font(.headline)

                    HStack {
                        Image(
                            systemName: isConnecting
                                ? "clock.circle.fill" : (isConnected ? "circle.fill" : "circle")
                        )
                        .foregroundColor(isConnecting ? .orange : (isConnected ? .green : .red))
                        .font(.system(size: 12))
                        Text(
                            isConnecting
                                ? "Connecting..." : (isConnected ? "Connected" : "Disconnected")
                        )
                        .fontWeight(.medium)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            server.configuration.displayValue.hasPrefix("http")
                                ? "URL" : "Command"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        Text(server.configuration.displayValue)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                #if os(visionOS)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                #else
                .background(.fill.secondary)
                .cornerRadius(10)
                #endif
            #endif

            // Server Info
            VStack(alignment: .leading, spacing: 12) {
                Label("Server Information", systemImage: "info.circle")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Name:")
                            .foregroundColor(.secondary)
                        if let name = server.serverInfo?.name,
                            !name.isEmpty
                        {
                            Text(name)
                                .fontWeight(.medium)
                                .textSelection(.enabled)
                        } else {
                            Text("Unknown")
                                .italic()
                        }
                    }

                    HStack {
                        Text("Version:")
                            .foregroundColor(.secondary)
                        if let version = server.serverInfo?.version,
                            !version.isEmpty
                        {
                            Text(version)
                                .fontWeight(.medium)
                                .monospacedDigit()
                                .textSelection(.enabled)
                        } else {
                            Text("Unspecified")
                                .italic()
                        }
                    }

                    HStack {
                        Text("Protocol:")
                            .foregroundColor(.secondary)
                        if let protocolVersion = server.protocolVersion {
                            Text(protocolVersion)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                                .monospacedDigit()
                                .textSelection(.enabled)
                        } else {
                            Text("Unspecified")
                                .italic()
                        }
                    }

                    #if !os(iOS)
                        HStack {
                            Text(
                                server.configuration.displayValue.hasPrefix("http")
                                    ? "URL:" : "Command:"
                            )
                            .foregroundColor(.secondary)
                            Text(server.configuration.displayValue)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .truncationMode(
                                    server.configuration.displayValue.hasPrefix("http")
                                        ? .tail : .middle
                                )
                                .textSelection(.enabled)
                        }
                    #endif
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            #if os(visionOS)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            #else
            .background(.fill.secondary)
            .cornerRadius(10)
            #endif

            // Capabilities
            VStack(alignment: .leading, spacing: 12) {
                Label("Capabilities", systemImage: "gear.badge")
                    .font(.headline)

                if let capabilities = server.capabilities {
                    ServerCapabilitiesView(capabilities: capabilities)
                } else {
                    Text("No capabilities information available")
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            #if os(visionOS)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            #else
            .background(.fill.secondary)
            .cornerRadius(10)
            #endif

            // Server Instructions
            VStack(alignment: .leading, spacing: 12) {
                Label("Instructions", systemImage: "doc.text")
                    .font(.headline)

                if let instructions = server.instructions {
                    Text(instructions)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                } else {
                    Text("No instructions provided by the server.")
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            #if os(visionOS)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            #else
            .background(.fill.secondary)
            .cornerRadius(10)
            #endif

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}
