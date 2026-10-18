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
    @State private var formInputs: [String: String] = [:]
    @State private var callTask: Task<Void, Never>?
    @State private var progress: ToolProgress?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Call Tool", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Show form fields if tool has input schema
                if let schema = tool.jsonSchema {
                    formFieldsView(for: schema)
                }
                
                if isCallingTool {
                    Button(action: { cancelToolCall() }) {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                } else {
                    Button(action: { callTool() }) {
                        Text("Submit")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(serverId == nil)
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
    }
    
    // MARK: - Form Fields
    
    @ViewBuilder
    private func formFieldsView(for schema: JSONSchema) -> some View {
        switch schema {
        case .object(_, _, _, _, _, _, let properties, let required, _)
            where !properties.isEmpty:
            VStack(alignment: .leading, spacing: 12) {
                ForEach(properties.keys, id: \.self) { key in
                    let fieldSchema = properties[key]!
                    let isRequired = required.contains(key)
                    formFieldView(key: key, schema: fieldSchema, isRequired: isRequired)
                }
            }
            .padding()
#if os(visionOS)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8))
#else
            .background(.fill.quaternary)
            .cornerRadius(8)
#endif
        default:
            EmptyView()
        }
    }
    
    @ViewBuilder
    private func formFieldView(key: String, schema: JSONSchema, isRequired: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(key)
                    .font(.caption)
                    .fontWeight(.medium)
                if isRequired {
                    Text("*")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                Spacer()
            }
            
            if let description = schema.description {
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Check for enum values first (applies to any type)
            if let enumValues = schema.enum, !enumValues.isEmpty {
                enumFieldView(key: key, enumValues: enumValues)
            } else {
                switch schema {
                case .boolean:
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { Bool(formInputs[key] ?? "false") ?? false },
                            set: { formInputs[key] = String($0) }
                        )
                    )
                    .labelsHidden()

                case .number(_, _, _, _, _, _, let minimum, let maximum, let exclusiveMinimum, let exclusiveMaximum, let multipleOf):
                    VStack(alignment: .leading, spacing: 8) {
                        // Show slider only when bounds are defined AND multipleOf is specified
                        let hasBounds = (minimum != nil && maximum != nil) || (exclusiveMinimum != nil && exclusiveMaximum != nil)
                        let minValue = minimum ?? exclusiveMinimum
                        let maxValue = maximum ?? exclusiveMaximum

                        if hasBounds, let min = minValue, let max = maxValue, let step = multipleOf, max - min <= 1000 {
                            // Show slider for bounded ranges with defined step
                            HStack {
                                Slider(
                                    value: Binding(
                                        get: {
                                            Double(formInputs[key] ?? String(min)) ?? min
                                        },
                                        set: { formInputs[key] = String($0) }
                                    ),
                                    in: min...max,
                                    step: step
                                )
                                Text(formInputs[key] ?? String(min))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(minWidth: 40)
                            }
                        }

                        // Always provide text field option
                        TextField(
                            "Enter number",
                            text: Binding(
                                get: { formInputs[key] ?? "" },
                                set: { formInputs[key] = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                    }

                case .integer(_, _, _, _, _, _, let minimum, let maximum, let exclusiveMinimum, let exclusiveMaximum, let multipleOf):
                    // Show stepper only when bounds are defined AND multipleOf is specified
                    let hasBounds = (minimum != nil && maximum != nil) || (exclusiveMinimum != nil && exclusiveMaximum != nil)
                    let minValue = minimum ?? exclusiveMinimum
                    let maxValue = maximum ?? exclusiveMaximum

                    if hasBounds, let min = minValue, let max = maxValue, multipleOf != nil, max - min <= 1000 {
                        // Show stepper with text field for bounded integer ranges
                        HStack {
                            TextField(
                                "Enter number",
                                text: Binding(
                                    get: { formInputs[key] ?? "" },
                                    set: { formInputs[key] = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
#if os(iOS)
                            .keyboardType(.numberPad)
#endif

                            Stepper(
                                value: Binding(
                                    get: { Int(formInputs[key] ?? String(min)) ?? min },
                                    set: { formInputs[key] = String($0) }
                                ),
                                in: min...max
                            ) {
                                EmptyView()
                            }
                        }
                    } else {
                        // Just text field for unbounded integers
                        TextField(
                            "Enter number",
                            text: Binding(
                                get: { formInputs[key] ?? "" },
                                set: { formInputs[key] = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                    }
                    
                case .string(_, _, _, _, _, _, _, _, _, let format):
                    stringFieldView(key: key, format: format)
                    
                default:  // array, object and others
                    TextField(
                        "Enter JSON value",
                        text: Binding(
                            get: { formInputs[key] ?? "" },
                            set: { formInputs[key] = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                }
            }
        }
    }
    
    @ViewBuilder
    private func enumFieldView(key: String, enumValues: [JSONValue]) -> some View {
        Picker(
            "",
            selection: Binding(
                get: {
                    // Find the current value in enum values
                    if let currentValue = formInputs[key] {
                        // Try to match against enum value descriptions
                        for enumValue in enumValues {
                            if enumValue.description == currentValue {
                                return currentValue
                            }
                        }
                    }
                    // Default to first enum value if no match
                    return enumValues.first?.description ?? ""
                },
                set: { formInputs[key] = $0 }
            )
        ) {
            ForEach(enumValues, id: \.self) { enumValue in
                Text(enumValue.description)
                    .tag(enumValue.description)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }
    
    @ViewBuilder
    private func stringFieldView(key: String, format: StringFormat?) -> some View {
        switch format {
        case .dateTime:
            DatePicker(
                "",
                selection: Binding(
                    get: {
                        if let dateString = formInputs[key],
                           let date = ISO8601DateFormatter().date(from: dateString)
                        {
                            return date
                        }
                        return Date()
                    },
                    set: { date in
                        let formatter = ISO8601DateFormatter()
                        formInputs[key] = formatter.string(from: date)
                    }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            
        case .date:
            DatePicker(
                "",
                selection: Binding(
                    get: {
                        if let dateString = formInputs[key] {
                            let formatter = DateFormatter()
                            formatter.dateFormat = "yyyy-MM-dd"
                            if let date = formatter.date(from: dateString) {
                                return date
                            }
                        }
                        return Date()
                    },
                    set: { date in
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        formInputs[key] = formatter.string(from: date)
                    }
                ),
                displayedComponents: [.date]
            )
            .labelsHidden()
            
        case .time:
            DatePicker(
                "",
                selection: Binding(
                    get: {
                        if let timeString = formInputs[key] {
                            let formatter = DateFormatter()
                            formatter.dateFormat = "HH:mm:ss"
                            if let date = formatter.date(from: timeString) {
                                return date
                            }
                        }
                        return Date()
                    },
                    set: { date in
                        let formatter = DateFormatter()
                        formatter.dateFormat = "HH:mm:ss"
                        formInputs[key] = formatter.string(from: date)
                    }
                ),
                displayedComponents: [.hourAndMinute]
            )
            .labelsHidden()
            
        case .email:
            TextField(
                "Enter email address",
                text: Binding(
                    get: { formInputs[key] ?? "" },
                    set: { formInputs[key] = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .disableAutocorrection(true)
#if os(iOS)
            .autocapitalization(.none)
            .keyboardType(.emailAddress)
#endif
            
        case .uri, .uriReference:
            TextField(
                "Enter URL",
                text: Binding(
                    get: { formInputs[key] ?? "" },
                    set: { formInputs[key] = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .disableAutocorrection(true)
#if os(iOS)
            .autocapitalization(.none)
            .keyboardType(.URL)
#endif
            
        case .uuid:
            TextField(
                "Enter UUID (e.g., 123e4567-e89b-12d3-a456-426614174000)",
                text: Binding(
                    get: { formInputs[key] ?? "" },
                    set: { formInputs[key] = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .disableAutocorrection(true)
            .font(.system(.body, design: .monospaced))
#if os(iOS)
            .autocapitalization(.none)
#endif
            
        case .ipv4:
            TextField(
                "Enter IPv4 address (e.g., 192.168.1.1)",
                text: Binding(
                    get: { formInputs[key] ?? "" },
                    set: { formInputs[key] = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .disableAutocorrection(true)
            .font(.system(.body, design: .monospaced))
#if os(iOS)
            .autocapitalization(.none)
            .keyboardType(.numbersAndPunctuation)
#endif
            
        case .ipv6:
            TextField(
                "Enter IPv6 address",
                text: Binding(
                    get: { formInputs[key] ?? "" },
                    set: { formInputs[key] = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .disableAutocorrection(true)
            .font(.system(.body, design: .monospaced))
#if os(iOS)
            .autocapitalization(.none)
#endif
            
        case .hostname:
            TextField(
                "Enter hostname (e.g., example.com)",
                text: Binding(
                    get: { formInputs[key] ?? "" },
                    set: { formInputs[key] = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .disableAutocorrection(true)
#if os(iOS)
            .autocapitalization(.none)
            .keyboardType(.URL)
#endif
            
        default:
            TextField(
                "Enter value",
                text: Binding(
                    get: { formInputs[key] ?? "" },
                    set: { formInputs[key] = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Actions

    private func callTool() {
        guard let serverId else {
            errorMessage = "No server ID provided"
            return
        }

        isCallingTool = true
        toolCallResult = nil
        errorMessage = nil
        progress = nil

        let arguments = Self.convertFormInputsToArguments(formInputs)
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

    private static func convertFormInputsToArguments(_ formInputs: [String: String])
        -> [String: MCP.Value]
    {
        var arguments: [String: MCP.Value] = [:]

        for (key, value) in formInputs {
            if value.isEmpty { continue }

            if let intValue = Int(value) {
                arguments[key] = .int(intValue)
            } else if let doubleValue = Double(value) {
                arguments[key] = .double(doubleValue)
            } else if let boolValue = Bool(value) {
                arguments[key] = .bool(boolValue)
            } else {
                arguments[key] = .string(value)
            }
        }

        return arguments
    }
}
