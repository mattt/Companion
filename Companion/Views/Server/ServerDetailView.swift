import MCP
import SwiftUI

struct ServerDetailView: View {
    @Environment(ServerStore.self) private var store
    let serverID: String

    @State private var showingActionSheet = false

    private var server: Server {
        store.server(id: serverID)
            ?? Server(id: serverID, name: "", configuration: .init(stdio: ""))
    }
    private var isConnecting: Bool { server.isConnecting }
    private var isConnected: Bool { server.status.isConnected }

    var body: some View {
        #if os(iOS)
            ScrollView {
                ServerInformationView(
                    server: server,
                    serverStatus: server.status,
                    isConnecting: isConnecting
                )
            }
            .softTopScrollEdgeEffect()
            .navigationTitle(server.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            store.presentEditServer(server)
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
                                store.restart(serverID: serverID)
                            } label: {
                                Label("Restart", systemImage: "arrow.clockwise")
                            }
                        }

                        Button {
                            if isConnecting {
                                store.cancelConnect(serverID: serverID)
                            } else if isConnected {
                                store.disconnect(serverID: serverID)
                            } else {
                                store.connect(serverID: serverID)
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
                    store.presentEditServer(server)
                }

                if isConnected {
                    Button("Restart") {
                        store.restart(serverID: serverID)
                    }
                }

                Button(isConnected ? "Disconnect" : "Connect") {
                    if isConnected {
                        store.disconnect(serverID: serverID)
                    } else {
                        store.connect(serverID: serverID)
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
                    .softTopScrollEdgeEffect()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ServerConnectionStateView(
                        isConnecting: isConnecting,
                        onConnect: { store.connect(serverID: serverID) },
                        onCancel: { store.cancelConnect(serverID: serverID) },
                        onEdit: { store.presentEditServer(server) }
                    )
                }
            }
            .toolbar {
                #if os(macOS)
                    ToolbarItem(id: "server-info", placement: .navigation) {
                        ServerInfoToolbarContent(server: server)
                    }
                    .hiddenSharedBackgroundIfAvailable()
                #else
                    ToolbarItem(placement: .navigation) {
                        ServerInfoToolbarContent(server: server)
                    }
                #endif

                // Connection status at the trailing edge, next to the action menu.
                // It is not interactive, so hide the Liquid Glass capsule
                // that toolbar items get by default.
                #if os(macOS)
                    ToolbarItem(id: "connection-status", placement: .primaryAction) {
                        ServerConnectionStatus(
                            isConnected: isConnected,
                            isConnecting: isConnecting
                        )
                    }
                    .hiddenSharedBackgroundIfAvailable()
                #else
                    ToolbarItem(placement: .primaryAction) {
                        ServerConnectionStatus(
                            isConnected: isConnected,
                            isConnecting: isConnecting
                        )
                    }
                #endif

                // Action menu as separate toolbar item
                ToolbarItem(placement: .primaryAction) {
                    ServerActionMenu(
                        isConnected: isConnected,
                        isConnecting: isConnecting,
                        onConnect: { store.connect(serverID: serverID) },
                        onDisconnect: { store.disconnect(serverID: serverID) },
                        onCancel: { store.cancelConnect(serverID: serverID) },
                        onEdit: { store.presentEditServer(server) }
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
        VStack(alignment: .leading, spacing: 1) {
            Text(server.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)

            Text(server.configuration.displayValue)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(
                    server.configuration.displayValue.hasPrefix("http")
                        ? .tail : .middle)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: 420, alignment: .leading)
    }
}

#if os(macOS)
    private extension CustomizableToolbarContent {
        /// Hides the Liquid Glass toolbar background where the API exists,
        /// so text content sits directly on the toolbar instead of in a pill.
        @ToolbarContentBuilder
        func hiddenSharedBackgroundIfAvailable() -> some CustomizableToolbarContent {
            if #available(macOS 26.0, *) {
                sharedBackgroundVisibility(.hidden)
            } else {
                self
            }
        }
    }
#endif

private struct ServerConnectionStatus: View {
    let isConnected: Bool
    let isConnecting: Bool

    var body: some View {
        HStack(spacing: 5) {
            if isConnecting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "circle.fill")
                    .foregroundColor(isConnected ? .green : .red)
                    .font(.system(size: 9))
            }
            Text(
                isConnecting
                    ? "Connecting…" : (isConnected ? "Connected" : "Disconnected")
            )
            .font(.callout)
            .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
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
                    Label("Disconnect", systemImage: "bolt.slash")
                }
            } else {
                Divider()

                if isConnecting {
                    Button {
                        onCancel()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        onConnect()
                    } label: {
                        Label("Connect", systemImage: "bolt")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}

private struct ServerConnectionStateView: View {
    let isConnecting: Bool
    let onConnect: () -> Void
    let onCancel: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: 48) {
            VStack(spacing: 16) {
                if isConnecting {
                    Image(systemName: "bolt.badge.clock.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                        .symbolEffect(.pulse, options: .repeat(.continuous))

                    Text("Connecting...")
                        .font(.title2)
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "bolt")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("Disconnected")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                if isConnecting {
                    Button {
                        onCancel()
                    } label: {
                        Text("Cancel")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        onConnect()
                    } label: {
                        Text("Connect")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        onEdit()
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
