import JSONSchema
import MCP
import SwiftUI

struct ToolCallView: View {
    let tool: Tool
    let serverId: String?

    @Environment(ServerStore.self) private var serverStore
    @State private var isCallingTool = false
    @State private var toolCallResult: MCP.CallTool.Result?
    @State private var errorMessage: String?
    @State private var formValue: FormValue = .object([])
    @State private var callTask: Task<Void, Never>?
    @State private var progress: ToolProgress?
    @AppStorage(AppSettingsKey.warnDestructiveToolCalls) private var warnDestructive = true
    @State private var showingDestructiveWarning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Call Tool", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Show form fields if tool has input schema
                if let schema = tool.jsonSchema {
                    ToolFormView(schema: schema, value: $formValue)
                }
                
                if isCallingTool {
                    Button(action: { cancelToolCall() }) {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                } else {
                    Button(action: { submitToolCall() }) {
                        Text("Submit")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(serverId == nil)
                    .confirmationDialog(
                        "Call destructive tool?",
                        isPresented: $showingDestructiveWarning
                    ) {
                        Button("Call Tool", role: .destructive) {
                            callTool()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(
                            "The server marks \(tool.name) as destructive. "
                                + "It may change or delete data.")
                    }
                }
                
                // Show progress indicator when calling tool
                if isCallingTool {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ProgressView()
                                .progressViewStyle(
                                    CircularProgressViewStyle(tint: .secondary)
                                )
                                .scaleEffect(0.8)
                            Text(progress?.message ?? "Calling...")
                                .foregroundColor(.secondary)
                        }
                        if let fraction = progress?.fraction {
                            ProgressView(value: fraction)
                        } else if let progress {
                            Text(progressText(progress))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
#if os(visionOS)
                    .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8))
#else
                    .background(.fill.quaternary)
                    .cornerRadius(8)
#endif
                }
                
                // Tool call result
                else if let result = toolCallResult {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(
                                result.isError != true ? "Success" : "Error",
                                systemImage: result.isError != true
                                ? "checkmark.circle.fill"
                                : "exclamationmark.triangle.fill"
                            )
                            .foregroundColor(result.isError != true ? .green : .red)
                            .font(.headline)
                            
                            Spacer()
                            
                            Button("Clear") {
                                toolCallResult = nil
                            }
                            .font(.caption)
                        }
                        
                        if !result.content.isEmpty {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(result.content.enumerated()), id: \.offset) {
                                    index, content in
                                    switch content {
                                    case .text(let text, _, _):
                                        ContentDisplayHelpers.textContentView(text)
                                    case .image(let data, let mimeType, _, _):
                                        ContentDisplayHelpers.imageContentView(
                                            data: data, mimeType: mimeType, metadata: nil)
                                    case .audio(let data, let mimeType, _, _):
                                        ContentDisplayHelpers.audioContentView(
                                            data: data, mimeType: mimeType)
                                    case .resource(let resource, _, _):
                                        ContentDisplayHelpers.resourceContentView(
                                            uri: resource.uri,
                                            mimeType: resource.mimeType ?? "",
                                            text: resource.text)
                                    case .resourceLink(let uri, let name, _, _, let mimeType, _):
                                        ContentDisplayHelpers.resourceContentView(
                                            uri: uri, mimeType: mimeType ?? "", text: name)
                                    }
                                }
                            }
                        }
                        
                        if let structuredContent = result.structuredContent {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Structured Content")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                ContentDisplayHelpers.textContentView(
                                    Self.prettyJSON(structuredContent))
                            }
                        }

                        if result.isError == true {
                            Text("Tool execution returned an error")
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.top, 4)
                        }
                    }
                    .padding()
#if os(visionOS)
                    .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8))
#else
                    .background(.fill.quaternary)
                    .cornerRadius(8)
#endif
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.fill.quaternary)
                        .cornerRadius(8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
#if os(visionOS)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
#else
            .background(.fill.secondary)
            .cornerRadius(10)
#endif
        }
        .task(id: tool.name) {
            formValue = tool.jsonSchema.map { FormValue.initial(for: $0) } ?? .object([])
        }
    }
    
    // MARK: - Actions

    private func submitToolCall() {
        if warnDestructive, tool.annotations.destructiveHint == true {
            showingDestructiveWarning = true
        } else {
            callTool()
        }
    }

    private func callTool() {
        guard let serverId else {
            errorMessage = "No server ID provided"
            return
        }

        isCallingTool = true
        toolCallResult = nil
        errorMessage = nil
        progress = nil

        let arguments: [String: MCP.Value]
        if let schema = tool.jsonSchema {
            let problems = FormValue.validationProblems(schema: schema, value: formValue)
            guard problems.isEmpty else {
                errorMessage = problems.joined(separator: " ")
                isCallingTool = false
                return
            }
            arguments = formValue.arguments(for: schema)
        } else {
            arguments = [:]
        }
        let toolName = tool.name

        callTask = Task {
            do {
                let result = try await serverStore.callTool(
                    serverID: serverId, name: toolName, arguments: arguments,
                    progressHandler: { newProgress in
                        Task { @MainActor in
                            progress = newProgress
                        }
                    })
                guard !Task.isCancelled else { return }
                toolCallResult = result
            } catch is CancellationError {
                // Call was cancelled.
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isCallingTool = false
            progress = nil
        }
    }

    private func cancelToolCall() {
        callTask?.cancel()
        callTask = nil
        isCallingTool = false
        progress = nil
    }

    private func progressText(_ progress: ToolProgress) -> String {
        if let total = progress.total {
            return "\(progress.progress.formatted()) of \(total.formatted())"
        }
        return progress.progress.formatted()
    }

    private static func prettyJSON(_ value: MCP.Value) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
            let string = String(data: data, encoding: .utf8)
        else {
            return "\(value)"
        }
        return string
    }

}
