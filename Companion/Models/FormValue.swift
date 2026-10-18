import Foundation
import JSONSchema
import MCP

/// An editable value in a tool call form, shaped by a JSON Schema.
///
/// Scalars edit as text and convert to their schema type on submit.
/// Arrays and objects nest, so tools with structured arguments
/// (for example a list of email addresses, each with a label and value)
/// render as real fields instead of raw JSON text.
enum FormValue: Equatable {
    case string(String)
    case bool(Bool)
    case array([FormValue])
    case object([Field])

    struct Field: Equatable {
        var key: String
        var value: FormValue
    }

    // MARK: - Schema shape

    /// Unwraps a nullable union such as `anyOf: [X, null]`
    /// and single-element compositions.
    static func effectiveSchema(_ schema: JSONSchema) -> (schema: JSONSchema, isNullable: Bool) {
        switch schema {
        case .anyOf(let options), .oneOf(let options):
            let nonNull = options.filter { $0 != .null }
            if nonNull.count == 1, let only = nonNull.first {
                let inner = effectiveSchema(only)
                return (inner.schema, isNullable: true)
            }
            return (schema, isNullable: false)
        case .allOf(let options) where options.count == 1:
            return effectiveSchema(options[0])
        default:
            return (schema, isNullable: false)
        }
    }

    /// Whether the form renders this schema with structured fields
    /// instead of a raw JSON text field.
    static func isStructured(_ schema: JSONSchema) -> Bool {
        switch effectiveSchema(schema).schema {
        case .object(_, _, _, _, _, _, let properties, _, _):
            return !properties.isEmpty
        case .array, .string, .number, .integer, .boolean:
            return true
        default:
            return schema.enum?.isEmpty == false
        }
    }

    /// Property keys with required fields first,
    /// keeping schema order within each group.
    static func orderedPropertyKeys(keys: [String], required: [String]) -> [String] {
        let requiredSet = Set(required)
        return keys.filter { requiredSet.contains($0) }
            + keys.filter { !requiredSet.contains($0) }
    }

    // MARK: - Initial values

    static func initial(for schema: JSONSchema, required: Bool = false) -> FormValue {
        let effective = effectiveSchema(schema).schema

        if let defaultValue = effective.default {
            return formValue(from: defaultValue, schema: effective)
        }

        if let enumValues = effective.enum, !enumValues.isEmpty {
            return .string(required ? enumValues[0].description : "")
        }

        switch effective {
        case .object(_, _, _, _, _, _, let properties, let requiredKeys, _)
            where !properties.isEmpty:
            let fields = orderedPropertyKeys(keys: Array(properties.keys), required: requiredKeys).map { key in
                Field(
                    key: key,
                    value: initial(
                        for: properties[key] ?? .empty,
                        required: requiredKeys.contains(key)))
            }
            return .object(fields)
        case .array(_, _, _, _, _, _, let items, let minItems, _, _):
            let count = min(minItems ?? 0, 5)
            guard count > 0, let items else { return .array([]) }
            return .array((0..<count).map { _ in initial(for: items, required: true) })
        case .boolean:
            return .bool(false)
        default:
            return .string("")
        }
    }

    private static func formValue(from jsonValue: JSONValue, schema: JSONSchema) -> FormValue {
        let effective = effectiveSchema(schema).schema
        switch (jsonValue, effective) {
        case (.bool(let bool), _):
            return .bool(bool)
        case (.array(let values), .array(_, _, _, _, _, _, let items, _, _, _)):
            return .array(values.map { formValue(from: $0, schema: items ?? .empty) })
        case (.object(let dict), .object(_, _, _, _, _, _, let properties, let requiredKeys, _))
            where !properties.isEmpty:
            let fields = orderedPropertyKeys(keys: Array(properties.keys), required: requiredKeys).map { key in
                let propertySchema = properties[key] ?? .empty
                if let value = dict[key] {
                    return Field(key: key, value: formValue(from: value, schema: propertySchema))
                }
                return Field(
                    key: key,
                    value: initial(for: propertySchema, required: requiredKeys.contains(key)))
            }
            return .object(fields)
        case (.string(let string), _):
            return .string(string)
        case (.int(let int), _):
            return .string(String(int))
        case (.double(let double), _):
            return .string(String(double))
        case (.null, _):
            return .string("")
        default:
            return .string(jsonText(of: jsonValue))
        }
    }

    private static func jsonText(of value: JSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value),
            let text = String(data: data, encoding: .utf8)
        else { return "" }
        return text
    }

    // MARK: - Mutation helpers

    mutating func setString(_ string: String, forKey key: String) {
        setString(string, forKeyPath: [key])
    }

    mutating func setString(_ string: String, forKeyPath keyPath: [String]) {
        guard let first = keyPath.first else {
            self = .string(string)
            return
        }
        let rest = Array(keyPath.dropFirst())
        switch self {
        case .object(var fields):
            guard let index = fields.firstIndex(where: { $0.key == first }) else { return }
            fields[index].value.setString(string, forKeyPath: rest)
            self = .object(fields)
        case .array(var items):
            guard let index = Int(first), items.indices.contains(index) else { return }
            items[index].setString(string, forKeyPath: rest)
            self = .array(items)
        default:
            return
        }
    }

    /// Appends a new item to an array field of a root object value.
    mutating func appendItem(forKey key: String, schema: JSONSchema) {
        guard case .object(var fields) = self,
            let index = fields.firstIndex(where: { $0.key == key }),
            case .object(_, _, _, _, _, _, let properties, _, _) =
                Self.effectiveSchema(schema).schema,
            let propertySchema = properties[key],
            case .array(_, _, _, _, _, _, let items, _, _, _) =
                Self.effectiveSchema(propertySchema).schema,
            case .array(var elements) = fields[index].value
        else { return }

        elements.append(Self.initial(for: items ?? .empty, required: true))
        fields[index].value = .array(elements)
        self = .object(fields)
    }

    // MARK: - Argument conversion

    /// Converts a root object value to tool call arguments.
    func arguments(for schema: JSONSchema) -> [String: MCP.Value] {
        guard case .object(let fields) = self,
            case .object(_, _, _, _, _, _, let properties, let requiredKeys, _) =
                Self.effectiveSchema(schema).schema
        else { return [:] }

        var arguments: [String: MCP.Value] = [:]
        for field in fields {
            let propertySchema = properties[field.key] ?? .empty
            if let value = field.value.argumentValue(
                for: propertySchema, required: requiredKeys.contains(field.key))
            {
                arguments[field.key] = value
            }
        }
        return arguments
    }

    /// Converts this value for its schema, or `nil` to omit the argument.
    func argumentValue(for schema: JSONSchema, required: Bool) -> MCP.Value? {
        let effective = Self.effectiveSchema(schema).schema

        // Enum values convert back to their original JSON type.
        if let enumValues = effective.enum, !enumValues.isEmpty {
            guard case .string(let text) = self else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                // Explicit branches: MCP.Value is ExpressibleByNilLiteral,
                // so a ternary nil would become .null instead of Optional.none.
                if required { return Self.mcpValue(from: enumValues[0]) }
                return nil
            }
            if let match = enumValues.first(where: { $0.description == trimmed }) {
                return Self.mcpValue(from: match)
            }
            return .string(trimmed)
        }

        switch effective {
        case .boolean:
            if case .bool(let bool) = self { return .bool(bool) }
            return nil

        case .integer:
            guard case .string(let text) = self else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return Int(trimmed).map { .int($0) }

        case .number:
            guard case .string(let text) = self else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return Double(trimmed).map { .double($0) }

        case .string:
            guard case .string(let text) = self else { return nil }
            if text.isEmpty {
                if required { return .string("") }
                return nil
            }
            return .string(text)

        case .array(_, _, _, _, _, _, let items, _, _, _):
            guard case .array(let elements) = self else { return nil }
            let converted = elements.compactMap {
                $0.argumentValue(for: items ?? .empty, required: false)
            }
            if converted.isEmpty {
                if required { return .array([]) }
                return nil
            }
            return .array(converted)

        case .object(_, _, _, _, _, _, let properties, let requiredKeys, _)
            where !properties.isEmpty:
            guard case .object(let fields) = self else { return nil }
            var object: [String: MCP.Value] = [:]
            for field in fields {
                let propertySchema = properties[field.key] ?? .empty
                if let value = field.value.argumentValue(
                    for: propertySchema, required: requiredKeys.contains(field.key))
                {
                    object[field.key] = value
                }
            }
            if object.isEmpty {
                if required { return .object([:]) }
                return nil
            }
            return .object(object)

        default:
            // Free-form values edit as JSON text.
            guard case .string(let text) = self else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return Self.parseJSON(trimmed)
        }
    }

    static func parseJSON(_ text: String) -> MCP.Value? {
        guard let data = text.data(using: .utf8),
            let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return nil }
        return mcpValue(from: jsonValue)
    }

    static func mcpValue(from jsonValue: JSONValue) -> MCP.Value {
        switch jsonValue {
        case .null: return .null
        case .bool(let bool): return .bool(bool)
        case .int(let int): return .int(int)
        case .double(let double): return .double(double)
        case .string(let string): return .string(string)
        case .array(let values): return .array(values.map { mcpValue(from: $0) })
        case .object(let dict): return .object(dict.mapValues { mcpValue(from: $0) })
        }
    }

    // MARK: - Validation

    /// Human-readable problems that should block submission.
    static func validationProblems(schema: JSONSchema, value: FormValue) -> [String] {
        var problems: [String] = []
        collectProblems(schema: schema, value: value, path: "", into: &problems)
        return problems
    }

    private static func collectProblems(
        schema: JSONSchema, value: FormValue, path: String, into problems: inout [String]
    ) {
        let effective = effectiveSchema(schema).schema

        switch effective {
        case .object(_, _, _, _, _, _, let properties, let requiredKeys, _)
            where !properties.isEmpty:
            guard case .object(let fields) = value else { return }
            for field in fields {
                let propertySchema = properties[field.key] ?? .empty
                let fieldPath = path.isEmpty ? field.key : "\(path).\(field.key)"
                if requiredKeys.contains(field.key),
                    field.value.argumentValue(for: propertySchema, required: true) == nil
                        || field.value.isEmptyValue
                {
                    problems.append("\(fieldPath) is required")
                }
                collectProblems(
                    schema: propertySchema, value: field.value, path: fieldPath,
                    into: &problems)
            }

        case .array(_, _, _, _, _, _, let items, _, _, _):
            guard case .array(let elements) = value, let items else { return }
            for (index, element) in elements.enumerated() {
                collectProblems(
                    schema: items, value: element, path: "\(path).\(index)", into: &problems)
            }

        case .integer:
            if case .string(let text) = value {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, Int(trimmed) == nil {
                    problems.append("\(path) must be an integer")
                }
            }

        case .number:
            if case .string(let text) = value {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, Double(trimmed) == nil {
                    problems.append("\(path) must be a number")
                }
            }

        default:
            if !isStructured(schema), case .string(let text) = value {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, parseJSON(trimmed) == nil {
                    problems.append("\(path) must be valid JSON")
                }
            }
        }
    }

    private var isEmptyValue: Bool {
        switch self {
        case .string(let text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .bool:
            return false
        case .array(let elements):
            return elements.allSatisfy(\.isEmptyValue)
        case .object(let fields):
            return fields.allSatisfy { $0.value.isEmptyValue }
        }
    }
}
