import Foundation
import MCP
import Testing

@testable import Companion

struct FormConversionTests {
    @Test func keyValueRowsSkipEmptyKeys() {
        let rows = [
            KeyValueRow(key: "A", value: "1"),
            KeyValueRow(key: "  ", value: "ignored"),
            KeyValueRow(key: "B", value: ""),
        ]

        #expect(KeyValueRow.dictionary(from: rows) == ["A": "1", "B": ""])
        #expect(KeyValueRow.dictionary(from: []) == nil)
    }

    @Test func keyValueRowsRoundTripSorted() {
        let rows = KeyValueRow.rows(from: ["B": "2", "A": "1"])
        #expect(rows.map(\.key) == ["A", "B"])
        #expect(KeyValueRow.dictionary(from: rows) == ["A": "1", "B": "2"])
    }

    @Test func rootRowsTrimAndSkipEmptyURIs() {
        let rows = [
            RootRow(uri: " file:///tmp/project ", name: " Project "),
            RootRow(uri: "", name: "Ignored"),
            RootRow(uri: "file:///tmp/other", name: ""),
        ]

        let roots = RootRow.roots(from: rows)
        #expect(roots.count == 2)
        #expect(roots.first?.uri == "file:///tmp/project")
        #expect(roots.first?.name == "Project")
        #expect(roots.last?.name == nil)
    }

    @Test func sidecarSettingsRoundTrip() {
        let store = ServerSettingsStore()
        let name = "Test-\(UUID().uuidString)"
        defer { store.removeSettings(forServerNamed: name) }

        let settings = ServerSidecarSettings(
            roots: [MCP.Root(uri: "file:///tmp/project", name: "Project")],
            useOAuth: true,
            oauthClientID: "client-123"
        )
        store.save(settings, forServerNamed: name)

        #expect(store.settings(forServerNamed: name) == settings)
    }

    @Test func sidecarSettingsRenameMovesEntry() {
        let store = ServerSettingsStore()
        let oldName = "Old-\(UUID().uuidString)"
        let newName = "New-\(UUID().uuidString)"
        defer {
            store.removeSettings(forServerNamed: oldName)
            store.removeSettings(forServerNamed: newName)
        }

        let settings = ServerSidecarSettings(useOAuth: true, oauthClientID: "abc")
        store.save(settings, forServerNamed: oldName)
        store.rename(from: oldName, to: newName)

        #expect(store.settings(forServerNamed: newName) == settings)
        #expect(store.settings(forServerNamed: oldName) == ServerSidecarSettings())
    }
}
