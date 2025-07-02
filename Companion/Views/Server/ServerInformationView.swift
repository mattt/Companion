import SwiftUI

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