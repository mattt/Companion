import JSONSchema
import SwiftUI

// MARK: - Bindings into a FormValue tree

private extension Binding where Value == FormValue {
    var stringValue: Binding<String> {
        Binding<String>(
            get: {
                if case .string(let string) = wrappedValue { return string }
                return ""
            },
            set: { wrappedValue = .string($0) })
    }

    var boolValue: Binding<Bool> {
        Binding<Bool>(
            get: {
                if case .bool(let bool) = wrappedValue { return bool }
                return false
            },
            set: { wrappedValue = .bool($0) })
    }

    var elements: Binding<[FormValue]> {
        Binding<[FormValue]>(
            get: {
                if case .array(let elements) = wrappedValue { return elements }
                return []
            },
            set: { wrappedValue = .array($0) })
    }

    func field(_ key: String) -> Binding<FormValue> {
        Binding<FormValue>(
            get: {
                if case .object(let fields) = wrappedValue,
                    let field = fields.first(where: { $0.key == key })
                {
                    return field.value
                }
                return .string("")
            },
            set: { newValue in
                if case .object(var fields) = wrappedValue,
                    let index = fields.firstIndex(where: { $0.key == key })
                {
                    fields[index].value = newValue
                    wrappedValue = .object(fields)
                }
            })
    }

    func element(at index: Int) -> Binding<FormValue> {
        Binding<FormValue>(
            get: {
                if case .array(let elements) = wrappedValue,
                    elements.indices.contains(index)
                {
                    return elements[index]
                }
                return .string("")
            },
            set: { newValue in
                if case .array(var elements) = wrappedValue,
                    elements.indices.contains(index)
                {
                    elements[index] = newValue
                    wrappedValue = .array(elements)
                }
            })
    }
}

/// A form generated from a tool input schema.
///
/// Objects render as grouped fields and arrays as addable rows,
/// so structured arguments edit as real controls
/// instead of raw JSON text.
struct ToolFormView: View {
    let schema: JSONSchema
    @Binding var value: FormValue

    var body: some View {
        let effective = FormValue.effectiveSchema(schema).schema
        if case .object(_, _, _, _, _, _, let properties, let requiredKeys, _) = effective,
            !properties.isEmpty
        {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(
                    FormValue.orderedPropertyKeys(
                        keys: Array(properties.keys), required: requiredKeys),
                    id: \.self
                ) { key in
                    FormFieldView(
                        label: key,
                        schema: properties[key] ?? .empty,
                        isRequired: requiredKeys.contains(key),
                        value: $value.field(key))
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
}

/// One field in a tool form, recursing into objects and arrays.
struct FormFieldView: View {
    let label: String
    let schema: JSONSchema
    let isRequired: Bool
    @Binding var value: FormValue
    var showsHeader = true

    private var effective: JSONSchema { FormValue.effectiveSchema(schema).schema }
    private var displayLabel: String { effective.title ?? label }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsHeader {
                HStack {
                    Text(displayLabel)
                        .font(.caption)
                        .fontWeight(.medium)
                    if isRequired {
                        Text("*")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    Spacer()
                }

                if let description = effective.description {
                    Text(description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            fieldControl
        }
    }

    @ViewBuilder
    private var fieldControl: some View {
        if let enumValues = effective.enum, !enumValues.isEmpty {
            enumField(enumValues: enumValues)
        } else {
            switch effective {
            case .boolean:
                Toggle("", isOn: $value.boolValue)
                    .labelsHidden()

            case .number(_, _, _, _, _, _, let minimum, let maximum, let exclusiveMinimum, let exclusiveMaximum, let multipleOf):
                numberField(
                    minimum: minimum, maximum: maximum,
                    exclusiveMinimum: exclusiveMinimum, exclusiveMaximum: exclusiveMaximum,
                    multipleOf: multipleOf)

            case .integer(_, _, _, _, _, _, let minimum, let maximum, let exclusiveMinimum, let exclusiveMaximum, let multipleOf):
                integerField(
                    minimum: minimum, maximum: maximum,
                    exclusiveMinimum: exclusiveMinimum, exclusiveMaximum: exclusiveMaximum,
                    multipleOf: multipleOf)

            case .string(_, _, _, _, _, _, _, _, _, let format):
                stringField(format: format)

            case .array(_, _, _, _, _, _, let items, _, let maxItems, _):
                arrayField(items: items ?? .empty, maxItems: maxItems)

            case .object(_, _, _, _, _, _, let properties, let requiredKeys, _)
                where !properties.isEmpty:
                objectField(
                    properties: properties.map { (key: $0.key, schema: $0.value) },
                    requiredKeys: requiredKeys)

            default:
                TextEditor(text: $value.stringValue)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 56)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel(displayLabel)
            }
        }
    }

    // MARK: - Array and object fields

    @ViewBuilder
    private func arrayField(items itemSchema: JSONSchema, maxItems: Int?) -> some View {
        let elements = $value.elements
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(elements.wrappedValue.indices), id: \.self) { index in
                HStack(alignment: .top, spacing: 8) {
                    if isObjectSchema(itemSchema) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Item \(index + 1)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                Spacer()
                                removeItemButton(at: index)
                            }
                            FormFieldView(
                                label: label,
                                schema: itemSchema,
                                isRequired: false,
                                value: $value.element(at: index),
                                showsHeader: false)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        FormFieldView(
                            label: label,
                            schema: itemSchema,
                            isRequired: false,
                            value: $value.element(at: index),
                            showsHeader: false)
                        removeItemButton(at: index)
                    }
                }
            }

            Button {
                elements.wrappedValue.append(
                    FormValue.initial(for: itemSchema, required: true))
            } label: {
                Label("Add \(label)", systemImage: "plus")
            }
            .controlSize(.small)
            .disabled(maxItems.map { elements.wrappedValue.count >= $0 } ?? false)
        }
    }

    private func removeItemButton(at index: Int) -> some View {
        Button(role: .destructive) {
            $value.elements.wrappedValue.remove(at: index)
        } label: {
            Image(systemName: "minus.circle.fill")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
        .accessibilityLabel("Remove item \(index + 1)")
    }

    private func isObjectSchema(_ schema: JSONSchema) -> Bool {
        if case .object(_, _, _, _, _, _, let properties, _, _) =
            FormValue.effectiveSchema(schema).schema
        {
            return !properties.isEmpty
        }
        return false
    }

    @ViewBuilder
    private func objectField(
        properties: [(key: String, schema: JSONSchema)], requiredKeys: [String]
    ) -> some View {
        let byKey = Dictionary(uniqueKeysWithValues: properties.map { ($0.key, $0.schema) })
        VStack(alignment: .leading, spacing: 10) {
            ForEach(
                FormValue.orderedPropertyKeys(
                    keys: properties.map(\.key), required: requiredKeys),
                id: \.self
            ) { key in
                FormFieldView(
                    label: key,
                    schema: byKey[key] ?? .empty,
                    isRequired: requiredKeys.contains(key),
                    value: $value.field(key))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Scalar fields

    @ViewBuilder
    private func enumField(enumValues: [JSONValue]) -> some View {
        Picker("", selection: $value.stringValue) {
            if !isRequired {
                Text("(none)").tag("")
            }
            ForEach(enumValues, id: \.self) { enumValue in
                Text(enumValue.description)
                    .tag(enumValue.description)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }

    @ViewBuilder
    private func numberField(
        minimum: Double?, maximum: Double?,
        exclusiveMinimum: Double?, exclusiveMaximum: Double?,
        multipleOf: Double?
    ) -> some View {
        let minValue = minimum ?? exclusiveMinimum
        let maxValue = maximum ?? exclusiveMaximum

        VStack(alignment: .leading, spacing: 8) {
            if let min = minValue, let max = maxValue, let step = multipleOf,
                max - min <= 1000
            {
                HStack {
                    Slider(
                        value: Binding(
                            get: { Double($value.stringValue.wrappedValue) ?? min },
                            set: { $value.stringValue.wrappedValue = String($0) }
                        ),
                        in: min...max,
                        step: step
                    )
                    Text($value.stringValue.wrappedValue.isEmpty
                        ? String(min) : $value.stringValue.wrappedValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(minWidth: 40)
                }
            }

            TextField("Enter number", text: $value.stringValue)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                    .keyboardType(.decimalPad)
                #endif
        }
    }

    @ViewBuilder
    private func integerField(
        minimum: Int?, maximum: Int?,
        exclusiveMinimum: Int?, exclusiveMaximum: Int?,
        multipleOf: Int?
    ) -> some View {
        let minValue = minimum ?? exclusiveMinimum
        let maxValue = maximum ?? exclusiveMaximum

        if let min = minValue, let max = maxValue, multipleOf != nil, max - min <= 1000 {
            HStack {
                TextField("Enter number", text: $value.stringValue)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                        .keyboardType(.numberPad)
                    #endif

                Stepper(
                    value: Binding(
                        get: { Int($value.stringValue.wrappedValue) ?? min },
                        set: { $value.stringValue.wrappedValue = String($0) }
                    ),
                    in: min...max
                ) {
                    EmptyView()
                }
            }
        } else {
            TextField("Enter number", text: $value.stringValue)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                    .keyboardType(.numberPad)
                #endif
        }
    }
}

extension FormFieldView {
    @ViewBuilder
    fileprivate func stringField(format: StringFormat?) -> some View {
        switch format {
        case .dateTime:
            DatePicker(
                "",
                selection: Binding(
                    get: {
                        ISO8601DateFormatter().date(from: $value.stringValue.wrappedValue)
                            ?? Date()
                    },
                    set: { date in
                        $value.stringValue.wrappedValue =
                            ISO8601DateFormatter().string(from: date)
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
                        Self.dateFormatter.date(from: $value.stringValue.wrappedValue)
                            ?? Date()
                    },
                    set: { date in
                        $value.stringValue.wrappedValue =
                            Self.dateFormatter.string(from: date)
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
                        Self.timeFormatter.date(from: $value.stringValue.wrappedValue)
                            ?? Date()
                    },
                    set: { date in
                        $value.stringValue.wrappedValue =
                            Self.timeFormatter.string(from: date)
                    }
                ),
                displayedComponents: [.hourAndMinute]
            )
            .labelsHidden()

        case .email:
            TextField("Enter email address", text: $value.stringValue)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                #if os(iOS)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                #endif

        case .uri, .uriReference:
            TextField("Enter URL", text: $value.stringValue)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                #if os(iOS)
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                #endif

        case .uuid:
            TextField(
                "Enter UUID (e.g., 123e4567-e89b-12d3-a456-426614174000)",
                text: $value.stringValue
            )
            .textFieldStyle(.roundedBorder)
            .disableAutocorrection(true)
            .font(.system(.body, design: .monospaced))
            #if os(iOS)
                .autocapitalization(.none)
            #endif

        case .ipv4:
            TextField("Enter IPv4 address (e.g., 192.168.1.1)", text: $value.stringValue)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .font(.system(.body, design: .monospaced))
                #if os(iOS)
                    .autocapitalization(.none)
                    .keyboardType(.numbersAndPunctuation)
                #endif

        case .ipv6:
            TextField("Enter IPv6 address", text: $value.stringValue)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .font(.system(.body, design: .monospaced))
                #if os(iOS)
                    .autocapitalization(.none)
                #endif

        case .hostname:
            TextField("Enter hostname (e.g., example.com)", text: $value.stringValue)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                #if os(iOS)
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                #endif

        default:
            TextField("Enter value", text: $value.stringValue)
                .textFieldStyle(.roundedBorder)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

#Preview("Contacts Update Form") {
    @Previewable @State var value: FormValue = .object([])

    let schemaJSON = """
        {
          "type": "object",
          "properties": {
            "identifier": { "type": "string", "description": "Unique identifier of the contact to update" },
            "givenName": { "type": "string" },
            "familyName": { "type": "string" },
            "birthday": {
              "type": "object",
              "properties": {
                "year": { "type": "integer" },
                "month": { "type": "integer" },
                "day": { "type": "integer" }
              },
              "required": ["month", "day"]
            },
            "emailAddresses": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "label": { "type": "string" },
                  "value": { "type": "string", "format": "email" }
                },
                "required": ["value"]
              }
            },
            "phoneNumbers": { "type": "array", "items": { "type": "string" } }
          },
          "required": ["identifier"]
        }
        """
    let schema =
        (try? JSONDecoder().decode(JSONSchema.self, from: Data(schemaJSON.utf8)))
        ?? .empty

    ScrollView {
        ToolFormView(schema: schema, value: $value)
            .padding()
    }
    .task {
        value = FormValue.initial(for: schema)
        value.appendItem(forKey: "emailAddresses", schema: schema)
    }
    .frame(width: 420, height: 640)
}
