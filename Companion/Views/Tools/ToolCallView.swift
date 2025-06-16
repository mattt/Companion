import ComposableArchitecture
import JSONSchema
import SwiftUI

struct ToolCallView: View {
    let store: StoreOf<ToolDetailFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Call Tool", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Show form fields if tool has input schema
            if let schema = store.tool.inputSchema {
                formFieldsView(for: schema)
            }

            if store.isCallingTool {
                Button(action: { store.send(.cancelToolCall) }) {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button(action: { store.send(.callToolTapped) }) {
                    Text("Submit")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(store.serverId == nil)
            }

            // Show progress indicator when calling tool
            if store.isCallingTool {
                HStack {
                    ProgressView()
                        .progressViewStyle(
                            CircularProgressViewStyle(tint: .secondary)
                        )
                        .scaleEffect(0.8)
                    Text("Calling...")
                        .foregroundColor(.secondary)
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
            else if let result = store.toolCallResult {
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
                            store.send(.dismissResult)
                        }
                        .font(.caption)
                    }

                    if !result.content.isEmpty {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(result.content.enumerated()), id: \.offset) {
                                index, content in
                                switch content {
                                case .text(let text):
                                    textContentView(text)
                                case .image(let data, let mimeType, let metadata):
                                    imageContentView(
                                        data: data, mimeType: mimeType, metadata: metadata)
                                case .audio(let data, let mimeType):
                                    audioContentView(data: data, mimeType: mimeType)
                                case .resource(let uri, let mimeType, let text):
                                    resourceContentView(uri: uri, mimeType: mimeType, text: text)
                                }
                            }
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
                            get: { Bool(store.formInputs[key] ?? "false") ?? false },
                            set: { store.send(.updateFormInput(key, String($0))) }
                        )
                    )
                    .labelsHidden()

                case let .number(_, _, _, _, _, _, minimum, maximum, _, _, _):
                    VStack(alignment: .leading, spacing: 8) {
                        if let min = minimum, let max = maximum, max - min <= 1000 {
                            // Show slider for bounded ranges
                            HStack {
                                Slider(
                                    value: Binding(
                                        get: {
                                            Double(store.formInputs[key] ?? String(min)) ?? min
                                        },
                                        set: { store.send(.updateFormInput(key, String($0))) }
                                    ),
                                    in: min...max
                                )
                                Text(store.formInputs[key] ?? String(min))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(minWidth: 40)
                            }
                        }

                        // Always provide text field option
                        TextField(
                            "Enter number",
                            text: Binding(
                                get: { store.formInputs[key] ?? "" },
                                set: { store.send(.updateFormInput(key, $0)) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                            .keyboardType(.decimalPad)
                        #endif
                    }

                case let .integer(_, _, _, _, _, _, minimum, maximum, _, _, _):
                    if let min = minimum, let max = maximum, max - min <= 1000 {
                        // Show stepper with text field for bounded integer ranges
                        HStack {
                            TextField(
                                "Enter number",
                                text: Binding(
                                    get: { store.formInputs[key] ?? "" },
                                    set: { store.send(.updateFormInput(key, $0)) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                                .keyboardType(.numberPad)
                            #endif

                            Stepper(
                                value: Binding(
                                    get: { Int(store.formInputs[key] ?? String(min)) ?? min },
                                    set: { store.send(.updateFormInput(key, String($0))) }
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
                                get: { store.formInputs[key] ?? "" },
                                set: { store.send(.updateFormInput(key, $0)) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                            .keyboardType(.numberPad)
                        #endif
                    }

                case let .string(_, _, _, _, _, _, _, _, _, format):
                    stringFieldView(key: key, format: format)

                default:  // array, object and others
                    TextField(
                        "Enter JSON value",
                        text: Binding(
                            get: { store.formInputs[key] ?? "" },
                            set: { store.send(.updateFormInput(key, $0)) }
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
                    if let currentValue = store.formInputs[key] {
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
                set: { store.send(.updateFormInput(key, $0)) }
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
                        if let dateString = store.formInputs[key],
                            let date = ISO8601DateFormatter().date(from: dateString)
                        {
                            return date
                        }
                        return Date()
                    },
                    set: { date in
                        let formatter = ISO8601DateFormatter()
                        store.send(.updateFormInput(key, formatter.string(from: date)))
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
                        if let dateString = store.formInputs[key] {
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
                        store.send(.updateFormInput(key, formatter.string(from: date)))
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
                        if let timeString = store.formInputs[key] {
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
                        store.send(.updateFormInput(key, formatter.string(from: date)))
                    }
                ),
                displayedComponents: [.hourAndMinute]
            )
            .labelsHidden()

        case .email:
            TextField(
                "Enter email address",
                text: Binding(
                    get: { store.formInputs[key] ?? "" },
                    set: { store.send(.updateFormInput(key, $0)) }
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
                    get: { store.formInputs[key] ?? "" },
                    set: { store.send(.updateFormInput(key, $0)) }
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
                    get: { store.formInputs[key] ?? "" },
                    set: { store.send(.updateFormInput(key, $0)) }
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
                    get: { store.formInputs[key] ?? "" },
                    set: { store.send(.updateFormInput(key, $0)) }
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
                    get: { store.formInputs[key] ?? "" },
                    set: { store.send(.updateFormInput(key, $0)) }
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
                    get: { store.formInputs[key] ?? "" },
                    set: { store.send(.updateFormInput(key, $0)) }
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
                    get: { store.formInputs[key] ?? "" },
                    set: { store.send(.updateFormInput(key, $0)) }
                )
            )
            .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Content View Helpers

    @ViewBuilder
    private func textContentView(_ text: String) -> some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                #if os(visionOS)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                #else
                    .background(.fill.tertiary)
                    .cornerRadius(8)
                #endif
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func imageContentView(data: String, mimeType: String, metadata: [String: String]?)
        -> some View
    {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Image", systemImage: "photo")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(mimeType)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let imageData = Data(base64Encoded: data) {
                #if os(macOS)
                    if let nsImage = NSImage(data: imageData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .cornerRadius(8)
                    } else {
                        imageDecodeErrorView()
                    }
                #else
                    if let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .cornerRadius(8)
                    } else {
                        imageDecodeErrorView()
                    }
                #endif
            } else {
                imageDecodeErrorView()
            }

            if let metadata = metadata, !metadata.isEmpty {
                metadataView(metadata)
            }
        }
        .padding()
        #if os(visionOS)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        #else
            .background(.fill.tertiary)
            .cornerRadius(8)
        #endif
    }

    @ViewBuilder
    private func audioContentView(data: String, mimeType: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Audio", systemImage: "waveform")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(mimeType)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundColor(.accentColor)
                Text("Audio content available")
                    .font(.body)
                Spacer()
                Text("\(data.count) bytes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            #if os(visionOS)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            #else
                .background(.fill.quaternary)
                .cornerRadius(6)
            #endif
        }
        .padding()
        #if os(visionOS)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        #else
            .background(.fill.tertiary)
            .cornerRadius(8)
        #endif
    }

    @ViewBuilder
    private func resourceContentView(uri: String, mimeType: String, text: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Resource", systemImage: "doc")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if !mimeType.isEmpty {
                    Text(mimeType)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(uri)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.accentColor)
                .textSelection(.enabled)

            if let text = text, !text.isEmpty {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .padding()
        #if os(visionOS)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        #else
            .background(.fill.tertiary)
            .cornerRadius(8)
        #endif
    }

    @ViewBuilder
    private func imageDecodeErrorView() -> some View {
        Text("Failed to decode image data")
            .font(.caption)
            .foregroundColor(.red)
            .padding()
            .frame(maxWidth: .infinity)
            #if os(visionOS)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            #else
                .background(.fill.tertiary)
                .cornerRadius(8)
            #endif
    }

    @ViewBuilder
    private func metadataView(_ metadata: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Metadata:")
                .font(.caption2)
                .foregroundColor(.secondary)
            ForEach(Array(metadata.keys.sorted()), id: \.self) { key in
                HStack {
                    Text(key)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(metadata[key] ?? "")
                        .font(.caption2)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        #if os(visionOS)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        #else
            .background(.fill.quaternary)
            .cornerRadius(6)
        #endif
    }
}
