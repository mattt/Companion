import MCP
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Form row models

struct KeyValueRow: Identifiable, Equatable {
    var id = UUID()
    var key: String = ""
    var value: String = ""

    static func rows(from dictionary: [String: String]?) -> [KeyValueRow] {
        guard let dictionary, !dictionary.isEmpty else { return [] }
        return dictionary.keys.sorted().map { key in
            KeyValueRow(key: key, value: dictionary[key] ?? "")
        }
    }

    static func dictionary(from rows: [KeyValueRow]) -> [String: String]? {
        var result: [String: String] = [:]
        for row in rows {
            let key = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            result[key] = row.value
        }
        return result.isEmpty ? nil : result
    }
}

struct RootRow: Identifiable, Equatable {
    var id = UUID()
    var uri: String = ""
    var name: String = ""

    static func rows(from roots: [MCP.Root]) -> [RootRow] {
        roots.map { RootRow(uri: $0.uri, name: $0.name ?? "") }
    }

    static func roots(from rows: [RootRow]) -> [MCP.Root] {
        rows.compactMap { row in
            let uri = row.uri.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !uri.isEmpty else { return nil }
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return MCP.Root(uri: uri, name: name.isEmpty ? nil : name)
        }
    }
}

// MARK: - Key-value editor (environment variables and HTTP headers)

struct KeyValueEditorView: View {
    let title: String
    @Binding var rows: [KeyValueRow]
    var keyPlaceholder: String = "Key"
    var valuePlaceholder: String = "Value"
    var isDisabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button {
                    rows.append(KeyValueRow())
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .disabled(isDisabled)
            }

            if rows.isEmpty {
                Text("None")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach($rows) { $row in
                HStack(spacing: 8) {
                    TextField(keyPlaceholder, text: $row.key)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                    TextField(valuePlaceholder, text: $row.value)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                    Button(role: .destructive) {
                        rows.removeAll { $0.id == row.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
                .disabled(isDisabled)
            }
        }
    }
}

// MARK: - Roots editor

struct RootsEditorView: View {
    @Binding var rows: [RootRow]
    var isDisabled: Bool = false

    @State private var showingFolderPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Roots")
                    .font(.headline)
                Spacer()
                Button {
                    showingFolderPicker = true
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
                .disabled(isDisabled)
            }

            Text("Folders this server may work in. The server asks for them with roots/list.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if rows.isEmpty {
                Text("None")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach($rows) { $row in
                HStack(spacing: 8) {
                    TextField("Name (optional)", text: $row.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 160)
                    TextField("file:///path/to/folder", text: $row.uri)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                        .font(.system(.body, design: .monospaced))
                    Button(role: .destructive) {
                        rows.removeAll { $0.id == row.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
                .disabled(isDisabled)
            }
        }
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                rows.append(
                    RootRow(uri: url.absoluteString, name: url.lastPathComponent))
            }
        }
    }
}

// MARK: - HTTP authentication fields

struct HTTPAuthFields: View {
    @Binding var bearerToken: String
    @Binding var useOAuth: Bool
    @Binding var oauthClientID: String
    @Binding var oauthClientSecret: String
    var isDisabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Authentication")
                .font(.headline)

            SecureField("Bearer Token (optional)", text: $bearerToken)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)

            Toggle("Use OAuth 2.1 sign-in", isOn: $useOAuth)

            if useOAuth {
                TextField("OAuth Client ID (optional)", text: $oauthClientID)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                SecureField("OAuth Client Secret (optional)", text: $oauthClientSecret)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                Text(
                    "Leave the client ID empty to register automatically "
                        + "when the server supports dynamic client registration. "
                        + "Companion opens your browser to sign in. "
                        + "Tokens and secrets stay in your Keychain."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .disabled(isDisabled)
    }
}

// MARK: - Transport Type (View Model)

enum TransportType: String, CaseIterable, Codable {
    case stdio = "stdio"
    case http = "http"

    var displayName: String {
        switch self {
        case .stdio: return "STDIO"
        case .http: return "HTTP"
        }
    }

    var icon: String {
        switch self {
        case .stdio: return "terminal"
        case .http: return "globe"
        }
    }

    var description: String {
        switch self {
        case .stdio: return "Local command execution"
        case .http: return "Remote server connection"
        }
    }
}

// MARK: - Server Form Header
struct ServerFormHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(icon)
                .font(.largeTitle)
                .foregroundColor(.accentColor)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
        }
        .padding(.top, 20)
        .padding(.bottom, 20)
        .padding(.horizontal)
    }
}

// MARK: - Transport Type Selector
struct TransportTypeSelector: View {
    @Binding var transportType: TransportType
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            ForEach(TransportType.allCases, id: \.self) { type in
                TransportTypeCard(
                    type: type,
                    isSelected: transportType == type,
                    isDisabled: isDisabled
                ) {
                    transportType = type
                }
            }
        }
    }
}

// MARK: - Transport Type Card
struct TransportTypeCard: View {
    let type: TransportType
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(type.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(type.description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 120)

            Spacer()

            Image(
                systemName: isSelected
                    ? "checkmark.circle.fill" : "circle"
            )
            .font(.system(size: 16))
            .foregroundColor(
                isSelected
                    ? .accentColor : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.1)
                        : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isSelected
                        ? Color.accentColor
                        : Color.secondary.opacity(0.3),
                    lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isDisabled {
                action()
            }
        }
        .opacity(isDisabled ? 0.6 : 1)
    }
}

// MARK: - Transport Configuration Fields
struct TransportConfigurationFields: View {
    let transportType: TransportType
    @Binding var command: String
    @Binding var arguments: String
    @Binding var url: String
    let isDisabled: Bool
    let onSubmit: () -> Void
    let onChange: (() -> Void)?

    var body: some View {
        ZStack(alignment: .top) {
            // STDIO fields
            VStack(alignment: .leading, spacing: 8) {
                TextField("Command", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isDisabled)
                    .help("e.g., python, node, /usr/local/bin/my-server")
                    .onSubmit(onSubmit)
                    .onChange(of: command, initial: true) { _, _ in onChange?() }

                TextField("Arguments (optional)", text: $arguments)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isDisabled)
                    .help("Space-separated arguments, e.g., --port 3000 --verbose")
                    .onSubmit(onSubmit)
                    .onChange(of: arguments, initial: true) { _, _ in onChange?() }
            }
            .opacity(transportType == .stdio ? 1 : 0)
            .allowsHitTesting(transportType == .stdio)

            // HTTP fields
            VStack(alignment: .leading, spacing: 8) {
                TextField("URL", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isDisabled)
                    .help(Text(verbatim: "e.g., http://localhost:3000 or https://api.example.com"))
                    .onSubmit(onSubmit)
                    .onChange(of: url, initial: true) { _, _ in onChange?() }

                // Add spacer to match STDIO height (2 fields)
                Color.clear
                    .frame(height: 28)
            }
            .opacity(transportType == .http ? 1 : 0)
            .allowsHitTesting(transportType == .http)
        }
    }
}

// MARK: - Server Form Buttons
struct ServerFormButtons: View {
    let cancelAction: () -> Void
    let saveAction: () -> Void
    let saveTitle: String
    let isValid: Bool

    var body: some View {
        HStack {
            Button("Cancel", action: cancelAction)
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button(saveTitle, action: saveAction)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
        }
        .padding()
        #if os(macOS)
            .background(Color(NSColor.controlBackgroundColor))
        #else
            .background(Color(UIColor.secondarySystemBackground))
        #endif
    }
}

// MARK: - ConfigFile.Entry Extensions for UI

extension ConfigFile.Entry {
    var transportType: TransportType {
        switch self {
        case .stdio:
            return .stdio
        case .sse, .streamableHTTP:
            return .http
        }
    }
}

// MARK: - Test Connection Section
struct TestConnectionSection: View {
    let isTesting: Bool
    let hasSucceeded: Bool
    let errorMessage: String?
    let testAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Test button and status
            HStack {
                if isTesting {
                    Button("Cancel Test", action: cancelAction)
                        .foregroundColor(.red)
                } else {
                    Button(action: testAction) {
                        HStack {
                            Image(systemName: "bolt.circle")
                            Text("Test Connection")
                        }
                    }
                }

                Spacer()

                if isTesting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(width: 16, height: 16)
                        Text("Testing connection...")
                            .foregroundColor(.secondary)
                    }
                } else if hasSucceeded {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .frame(width: 16, height: 16)
                        Text("Connection successful")
                            .foregroundColor(.secondary)
                    }
                } else if errorMessage != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .frame(width: 16, height: 16)
                        Text("Connection failed")
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Error details (if any)
            if let error = errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Error Details")
                        .font(.caption)
                        .foregroundColor(.primary)
                    
                    ScrollView {
                        Text(error)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.red)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
            }

            // Help text
            if hasSucceeded {
                Text("The server responded successfully and is ready to use.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        #if os(macOS)
            .background(Color(NSColor.controlBackgroundColor))
        #else
            .background(Color(UIColor.secondarySystemBackground))
        #endif
        .cornerRadius(8)
    }
}
