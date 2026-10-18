import Foundation
import JSONSchema
import MCP

extension MCP.Tool {
    /// The tool input schema decoded as a `JSONSchema` value.
    ///
    /// The MCP SDK models `inputSchema` as an untyped `Value`.
    /// Companion renders tool call forms from a typed schema,
    /// so it encodes the `Value` and decodes it as `JSONSchema`.
    /// The result is `nil` when the value is not a valid JSON Schema.
    var jsonSchema: JSONSchema? {
        guard let data = try? JSONEncoder().encode(inputSchema) else {
            return nil
        }
        return try? JSONDecoder().decode(JSONSchema.self, from: data)
    }

    /// The tool output schema decoded as a `JSONSchema` value.
    var outputJSONSchema: JSONSchema? {
        guard let outputSchema,
            let data = try? JSONEncoder().encode(outputSchema)
        else {
            return nil
        }
        return try? JSONDecoder().decode(JSONSchema.self, from: data)
    }

    /// The best human-readable title for display.
    var displayTitle: String? {
        title ?? annotations.title
    }
}
