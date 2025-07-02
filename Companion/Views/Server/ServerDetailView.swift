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
                    ServerConnectionStateView(
                        isConnecting: isConnecting,
                        onConnect: { store.send(.connect) },
                        onCancel: { store.send(.cancel) },
                        onEdit: { store.send(.edit) }
                    )
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
        .buttonStyle(.bordered)
        .controlSize(.small)
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
