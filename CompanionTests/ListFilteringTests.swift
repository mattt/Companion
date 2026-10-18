import Foundation
import MCP
import Testing

@testable import Companion

struct ListFilteringTests {
    // Regression: the Everything server sends a top-level `title`
    // ("Print Environment Tool") for the `get-env` tool.
    // Filtering for "print" must find it.
    @Test func toolFilterMatchesTitle() {
        let tool = Tool(
            name: "get-env",
            title: "Print Environment Tool",
            description: "Returns all environment variables, helpful for debugging MCP server configuration",
            inputSchema: .object([:])
        )

        #expect(tool.matchesFilter("print"))
        #expect(tool.matchesFilter("PRINT"))
        #expect(tool.matchesFilter("get-env"))
        #expect(tool.matchesFilter("environment variables"))
        #expect(!tool.matchesFilter("database"))
    }

    @Test func toolFilterMatchesAnnotationTitle() {
        var annotations = Tool.Annotations()
        annotations.title = "Legacy Title"
        let tool = Tool(
            name: "legacy-tool",
            description: nil,
            inputSchema: .object([:]),
            annotations: annotations
        )

        #expect(tool.matchesFilter("legacy title"))
    }

    @Test func promptFilterMatchesTitle() {
        let prompt = Prompt(
            name: "completable-prompt",
            title: "Team Management",
            description: "First argument choice narrows values for second argument."
        )

        #expect(prompt.matchesFilter("team"))
        #expect(prompt.matchesFilter("completable"))
        #expect(prompt.matchesFilter("narrows"))
        #expect(!prompt.matchesFilter("database"))
    }
}

struct ListPaneWidthTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "ListPaneWidthTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    @Test func storedWidthDefaultsWhenUnset() {
        #expect(ListPaneWidth.stored(in: makeDefaults()) == ListPaneWidth.defaultWidth)
    }

    @Test func storedWidthRoundTrips() {
        let defaults = makeDefaults()
        ListPaneWidth.store(310, in: defaults)
        #expect(ListPaneWidth.stored(in: defaults) == 310)
    }

    @Test func storedWidthIsClampedToRange() {
        let defaults = makeDefaults()

        ListPaneWidth.store(10, in: defaults)
        #expect(ListPaneWidth.stored(in: defaults) == ListPaneWidth.range.lowerBound)

        ListPaneWidth.store(2000, in: defaults)
        #expect(ListPaneWidth.stored(in: defaults) == ListPaneWidth.range.upperBound)

        #expect(ListPaneWidth.clamped(0) == ListPaneWidth.range.lowerBound)
        #expect(ListPaneWidth.clamped(9999) == ListPaneWidth.range.upperBound)
    }
}
