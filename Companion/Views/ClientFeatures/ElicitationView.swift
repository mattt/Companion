import JSONSchema
import MCP
import SwiftUI

/// Sheet for an `elicitation/create` request.
///
/// Form mode renders fields from the requested schema.
/// URL mode shows the message and opens the URL in a browser.
/// The user accepts, declines, or cancels in both modes.
struct ElicitationView: View {
    let request: PendingElicitationRequest
    @Environment(ServerStore.self) private var store
    @Environment(\.openURL) private var openURL

    @State private var values: [String: String] = [:]
    @State private var boolValues: [String: Bool] = [:]

    private var coordinator: ClientFeatureCoordinator { store.featureCoordinator }

    var body: some View {
        NavigationStack {
            Form {
                switch request.parameters {
                case .form(let parameters):
                    formContent(parameters)
                case .url(let parameters):
                    urlContent(parameters)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Information Request")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        coordinator.completeElicitation(
                            request, result: MCP.CreateElicitation.Result(action: .cancel))
                    }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Decline", role: .destructive) {
                        coordinator.completeElicitation(
                            request, result: MCP.CreateElicitation.Result(action: .decline))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        submit()
                    }
                    .disabled(!canSubmit)
                }
            }
        }
        .interactiveDismissDisabled()
        #if os(macOS)
            .frame(minWidth: 480, minHeight: 420)
        #endif
        .onAppear(perform: seedDefaults)
    }

    // MARK: Form mode

    @ViewBuilder
    private func formContent(
        _ parameters: MCP.CreateElicitation.Parameters.FormParameters
    ) -> some View {
        Section {
            Text(parameters.message)
            LabeledContent("Server", value: request.serverName)
        }

        let schema = parameters.requestedSchema
        Section(schema.title ?? "Details") {
            if let description = schema.description {
                Text(description)
                    .foregroundStyle(.secondary)
            }
            ForEach(sortedKeys(schema), id: \.self) { key in
                field(for: key, schema: schema)
            }
        }
    }

    @ViewBuilder
    private func field(for key: String, schema: MCP.Elicitation.RequestSchema) -> some View {
        let property = propertySchema(for: key, in: schema)
        let isRequired = schema.required?.contains(key) == true
        let title = property?.title ?? key

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .fontWeight(.medium)
                if isRequired {
                    Text("*")
                        .foregroundStyle(.red)
                }
            }
            if let description = property?.description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let property, case .boolean = property {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { boolValues[key] ?? false },
                        set: { boolValues[key] = $0 }
                    )
                )
                .labelsHidden()
            } else if let enumValues = property?.enum, !enumValues.isEmpty {
                Picker(
                    "",
                    selection: Binding(
                        get: { values[key] ?? enumValues.first?.description ?? "" },
                        set: { values[key] = $0 }
                    )
                ) {
                    ForEach(enumValues, id: \.self) { value in
                        Text(value.description).tag(value.description)
                    }
                }
                .labelsHidden()
            } else {
                TextField(
                    title,
                    text: Binding(
                        get: { values[key] ?? "" },
                        set: { values[key] = $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: URL mode

    @ViewBuilder
    private func urlContent(
        _ parameters: MCP.CreateElicitation.Parameters.URLParameters
    ) -> some View {
        Section {
            Text(parameters.message)
            LabeledContent("Server", value: request.serverName)
            Text(parameters.url)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

            if let url = URL(string: parameters.url) {
                Button("Open in Browser") {
                    openURL(url)
                }
            }
        } footer: {
            Text(
                "Open the page, complete the request there, then come back "
                    + "and choose Submit. The server confirms completion "
                    + "with a notification.")
        }
    }

    // MARK: Submission

    private var canSubmit: Bool {
        guard case .form(let parameters) = request.parameters else { return true }
        let schema = parameters.requestedSchema
        for key in schema.required ?? [] {
            if let property = propertySchema(for: key, in: schema),
                case .boolean = property
            {
                continue
            }
            if (values[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
        }
        return true
    }

    private func submit() {
        switch request.parameters {
        case .url:
            coordinator.completeElicitation(
                request, result: MCP.CreateElicitation.Result(action: .accept))
        case .form(let parameters):
            var content: [String: MCP.Value] = [:]
            let schema = parameters.requestedSchema
            for key in schema.properties.keys {
                if let property = propertySchema(for: key, in: schema),
                    case .boolean = property
                {
                    content[key] = .bool(boolValues[key] ?? false)
                } else if let value = values[key], !value.isEmpty {
                    content[key] = typedValue(value, for: propertySchema(for: key, in: schema))
                }
            }
            coordinator.completeElicitation(
                request,
                result: MCP.CreateElicitation.Result(action: .accept, content: content))
        }
    }

    private func typedValue(_ string: String, for schema: JSONSchema?) -> MCP.Value {
        switch schema {
        case .integer:
            if let intValue = Int(string) { return .int(intValue) }
            return .string(string)
        case .number:
            if let doubleValue = Double(string) { return .double(doubleValue) }
            return .string(string)
        default:
            return .string(string)
        }
    }

    // MARK: Schema helpers

    private func sortedKeys(_ schema: MCP.Elicitation.RequestSchema) -> [String] {
        schema.properties.keys.sorted { lhs, rhs in
            let lhsRequired = schema.required?.contains(lhs) == true
            let rhsRequired = schema.required?.contains(rhs) == true
            if lhsRequired != rhsRequired { return lhsRequired }
            return lhs < rhs
        }
    }

    private func propertySchema(
        for key: String, in schema: MCP.Elicitation.RequestSchema
    ) -> JSONSchema? {
        guard let value = schema.properties[key],
            let data = try? JSONEncoder().encode(value)
        else { return nil }
        return try? JSONDecoder().decode(JSONSchema.self, from: data)
    }

    private func seedDefaults() {
        guard case .form(let parameters) = request.parameters else { return }
        let schema = parameters.requestedSchema
        for key in schema.properties.keys {
            guard let property = propertySchema(for: key, in: schema) else { continue }
            if case .boolean = property {
                if boolValues[key] == nil { boolValues[key] = false }
            } else if values[key] == nil, let defaultValue = property.default {
                values[key] = defaultValue.description
            }
        }
    }
}
