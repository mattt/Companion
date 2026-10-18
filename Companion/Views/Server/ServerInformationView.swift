import SwiftUI

struct ServerInformationView: View {
    let server: Server
    let serverStatus: Server.Status
    let isConnecting: Bool

    @Environment(ServerStore.self) private var store
    @State private var pingState: PingState = .idle

    private enum PingState: Equatable {
        case idle
        case pinging
        case succeeded
        case failed(String)
    }

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
                HStack {
                    Label("Server Information", systemImage: "info.circle")
                        .font(.headline)
                    Spacer()
                    pingButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if server.serverInfo?.icons != nil {
                            IconView(
                                icons: server.serverInfo?.icons, size: 32,
                                fallbackSystemImage: "server.rack")
                        }
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

                    if let title = server.serverInfo?.title, !title.isEmpty {
                        HStack {
                            Text("Title:")
                                .foregroundColor(.secondary)
                            Text(title)
                                .fontWeight(.medium)
                                .textSelection(.enabled)
                        }
                    }

                    if let description = server.serverInfo?.description,
                        !description.isEmpty
                    {
                        HStack(alignment: .top) {
                            Text("Description:")
                                .foregroundColor(.secondary)
                            Text(description)
                                .textSelection(.enabled)
                        }
                    }

                    if let websiteUrl = server.serverInfo?.websiteUrl,
                        let url = URL(string: websiteUrl)
                    {
                        HStack {
                            Text("Website:")
                                .foregroundColor(.secondary)
                            Link(websiteUrl, destination: url)
                                .lineLimit(1)
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

            // Server Log
            if server.capabilities?.logging != nil {
                ServerLogView(server: server)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    #if os(visionOS)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    #else
                        .background(.fill.secondary)
                        .cornerRadius(10)
                    #endif
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    @ViewBuilder
    private var pingButton: some View {
        HStack(spacing: 8) {
            switch pingState {
            case .succeeded:
                Label("Reachable", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .lineLimit(1)
            case .idle, .pinging:
                EmptyView()
            }

            Button {
                ping()
            } label: {
                if pingState == .pinging {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Ping")
                }
            }
            .disabled(!isConnected || pingState == .pinging)
        }
    }

    private func ping() {
        pingState = .pinging
        let serverID = server.id
        Task {
            do {
                try await store.ping(serverID: serverID)
                pingState = .succeeded
            } catch {
                pingState = .failed(error.localizedDescription)
            }
        }
    }
}