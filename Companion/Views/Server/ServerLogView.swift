import MCP
import SwiftUI

/// Shows log messages a server sends with `notifications/message`,
/// with a control for the minimum level the server should send.
struct ServerLogView: View {
    let server: Server

    @Environment(ServerStore.self) private var store
    @State private var levelError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Server Log", systemImage: "doc.text")
                    .font(.headline)

                Spacer()

                Picker(
                    "Level",
                    selection: Binding(
                        get: { server.logLevel },
                        set: { newLevel in setLevel(newLevel) }
                    )
                ) {
                    ForEach(MCP.LogLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .labelsHidden()
                .fixedSize()

                CopyButton(isDisabled: server.logMessages.isEmpty) {
                    ServerLogMessage.plainText(for: server.logMessages)
                }

                Button("Clear") {
                    store.clearLogMessages(serverID: server.id)
                }
                .disabled(server.logMessages.isEmpty)
            }

            if let levelError {
                Text(levelError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if server.logMessages.isEmpty {
                Text("No log messages yet.")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(server.logMessages) { message in
                            LogMessageRow(message: message)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
    }

    private func setLevel(_ level: MCP.LogLevel) {
        levelError = nil
        let serverID = server.id
        Task {
            do {
                try await store.setLoggingLevel(serverID: serverID, level: level)
            } catch {
                levelError = error.localizedDescription
            }
        }
    }
}

private struct LogMessageRow: View {
    let message: ServerLogMessage

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(message.level.displayName)
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(message.level.color.opacity(0.2), in: Capsule())
                .foregroundStyle(message.level.color)

            VStack(alignment: .leading, spacing: 1) {
                Text(message.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)

                HStack(spacing: 6) {
                    if let logger = message.logger {
                        Text(logger)
                    }
                    Text(message.date, format: .dateTime.hour().minute().second())
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

extension MCP.LogLevel {
    var displayName: String {
        switch self {
        case .debug: return "Debug"
        case .info: return "Info"
        case .notice: return "Notice"
        case .warning: return "Warning"
        case .error: return "Error"
        case .critical: return "Critical"
        case .alert: return "Alert"
        case .emergency: return "Emergency"
        }
    }

    var color: Color {
        switch self {
        case .debug: return .gray
        case .info: return .blue
        case .notice: return .teal
        case .warning: return .orange
        case .error: return .red
        case .critical, .alert, .emergency: return .purple
        }
    }
}
