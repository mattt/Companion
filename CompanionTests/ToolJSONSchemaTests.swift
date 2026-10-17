import Foundation
import JSONSchema
import MCP
import Testing

@testable import Companion

struct ToolJSONSchemaTests {
    @Test func decodesObjectSchema() {
        let tool = Tool(
            name: "echo",
            description: "Echo a message",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "message": .object(["type": .string("string")])
                ]),
                "required": .array([.string("message")]),
            ])
        )

        guard case .object(_, _, _, _, _, _, let properties, let required, _) =
            tool.jsonSchema
        else {
            Issue.record("Expected an object schema, got \(String(describing: tool.jsonSchema))")
            return
        }

        #expect(properties.keys.contains("message"))
        #expect(required.contains("message"))
    }

    @Test func invalidSchemaReturnsNil() {
        let tool = Tool(
            name: "broken",
            description: nil,
            inputSchema: .int(42)
        )

        #expect(tool.jsonSchema == nil)
    }
}
