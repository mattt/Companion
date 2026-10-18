import Foundation
import JSONSchema
import MCP
import Testing

@testable import Companion

struct FormValueTests {
    /// Mirrors the shape of iMCP's contacts_update tool:
    /// arrays of labeled objects, a nested birthday object,
    /// one required identifier, everything else optional.
    private func contactsSchema() throws -> JSONSchema {
        let json = """
            {
              "type": "object",
              "properties": {
                "identifier": { "type": "string", "description": "Unique identifier of the contact to update" },
                "givenName": { "type": "string" },
                "familyName": { "type": "string" },
                "organizationName": { "type": "string" },
                "jobTitle": { "type": "string" },
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
                "phoneNumbers": {
                  "type": "array",
                  "items": { "type": "string" }
                },
                "isFavorite": { "type": "boolean" },
                "priority": { "type": "integer", "enum": [1, 2, 3] },
                "nickname": { "anyOf": [{ "type": "string" }, { "type": "null" }] },
                "metadata": { "type": "object" }
              },
              "required": ["identifier"]
            }
            """
        return try JSONDecoder().decode(JSONSchema.self, from: Data(json.utf8))
    }

    @Test func initialValueMirrorsSchemaShape() throws {
        let schema = try contactsSchema()
        let value = FormValue.initial(for: schema)

        guard case .object(let fields) = value else {
            Issue.record("Root value should be an object")
            return
        }
        #expect(fields.map(\.key).contains("identifier"))
        #expect(fields.map(\.key).contains("emailAddresses"))

        let birthday = try #require(fields.first { $0.key == "birthday" }?.value)
        guard case .object(let birthdayFields) = birthday else {
            Issue.record("Birthday should be a nested object")
            return
        }
        #expect(Set(birthdayFields.map(\.key)) == ["year", "month", "day"])

        let emails = try #require(fields.first { $0.key == "emailAddresses" }?.value)
        #expect(emails == .array([]))
    }

    @Test func argumentsConvertNestedAndArrayValues() throws {
        let schema = try contactsSchema()
        var value = FormValue.initial(for: schema)
        value.setString("contact-42", forKey: "identifier")
        value.setString("Ada", forKey: "givenName")
        value.setString("1815", forKeyPath: ["birthday", "year"])
        value.setString("12", forKeyPath: ["birthday", "month"])
        value.setString("10", forKeyPath: ["birthday", "day"])
        value.appendItem(forKey: "emailAddresses", schema: schema)
        value.setString(
            "ada@example.com", forKeyPath: ["emailAddresses", "0", "value"])
        value.setString("home", forKeyPath: ["emailAddresses", "0", "label"])
        value.appendItem(forKey: "phoneNumbers", schema: schema)
        value.setString("555-0100", forKeyPath: ["phoneNumbers", "0"])
        value.setString("2", forKey: "priority")
        value.setString(#"{"source":"test"}"#, forKey: "metadata")

        let arguments = value.arguments(for: schema)

        #expect(arguments["identifier"] == .string("contact-42"))
        #expect(arguments["givenName"] == .string("Ada"))
        #expect(arguments["familyName"] == nil)
        #expect(
            arguments["birthday"]
                == .object(["year": .int(1815), "month": .int(12), "day": .int(10)]))
        #expect(
            arguments["emailAddresses"]
                == .array([
                    .object(["label": .string("home"), "value": .string("ada@example.com")])
                ]))
        #expect(arguments["phoneNumbers"] == .array([.string("555-0100")]))
        #expect(arguments["priority"] == .int(2))
        #expect(arguments["metadata"] == .object(["source": .string("test")]))
        #expect(arguments["nickname"] == nil)
    }

    @Test func emptyOptionalObjectIsOmitted() throws {
        let schema = try contactsSchema()
        var value = FormValue.initial(for: schema)
        value.setString("contact-1", forKey: "identifier")

        let arguments = value.arguments(for: schema)
        #expect(arguments["birthday"] == nil)
        #expect(arguments["emailAddresses"] == nil)
        #expect(arguments.count == 1 || arguments.count == 2)  // identifier (+ bool)
    }

    @Test func emptyOptionalEnumIsOmitted() throws {
        let schema = try contactsSchema()
        guard case .object(_, _, _, _, _, _, let properties, _, _) = schema,
            let priority = properties["priority"]
        else {
            Issue.record("priority property missing")
            return
        }
        let converted = FormValue.string("").argumentValue(for: priority, required: false)
        #expect(converted == nil, "converted was \(String(describing: converted))")
    }

    @Test func validationReportsMissingRequiredAndBadNumbers() throws {
        let schema = try contactsSchema()
        var value = FormValue.initial(for: schema)
        value.setString("not-a-number", forKeyPath: ["birthday", "month"])
        value.setString("{broken", forKey: "metadata")

        let problems = FormValue.validationProblems(schema: schema, value: value)

        #expect(problems.contains { $0.contains("identifier") })
        #expect(problems.contains { $0.contains("month") })
        #expect(problems.contains { $0.contains("metadata") })
    }

    @Test func nullableUnionUnwraps() throws {
        let schema = try contactsSchema()
        var value = FormValue.initial(for: schema)
        value.setString("contact-1", forKey: "identifier")
        value.setString("Countess", forKey: "nickname")

        #expect(value.arguments(for: schema)["nickname"] == .string("Countess"))
    }

    @Test func defaultsSeedInitialValues() throws {
        let json = """
            {
              "type": "object",
              "properties": {
                "greeting": { "type": "string", "default": "Hello" },
                "count": { "type": "integer", "default": 3 }
              }
            }
            """
        let schema = try JSONDecoder().decode(JSONSchema.self, from: Data(json.utf8))
        let arguments = FormValue.initial(for: schema).arguments(for: schema)

        #expect(arguments["greeting"] == .string("Hello"))
        #expect(arguments["count"] == .int(3))
    }
}
