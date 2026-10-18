import Foundation
import MCP
import Testing

@testable import Companion

struct MarkdownBlockParserTests {
    @Test func parsesHeadingsParagraphsAndLists() {
        let markdown = """
            # Everything Server

            Follow these instructions to use the server.

            ## Tools

            - `get-roots-list`: see roots
            - `echo`: echo a message

            1. First step
            2. Second step
            """

        #expect(
            MarkdownBlockParser.parse(markdown) == [
                .heading(level: 1, text: "Everything Server"),
                .paragraph(text: "Follow these instructions to use the server."),
                .heading(level: 2, text: "Tools"),
                .list(items: ["`get-roots-list`: see roots", "`echo`: echo a message"]),
                .orderedList(items: ["First step", "Second step"]),
            ])
    }

    @Test func parsesCodeFencesLiterally() {
        let markdown = """
            Run this:

            ```sh
            # not a heading
            npx server-everything
            ```
            """

        #expect(
            MarkdownBlockParser.parse(markdown) == [
                .paragraph(text: "Run this:"),
                .code(text: "# not a heading\nnpx server-everything"),
            ])
    }

    @Test func stripsRemoteImagesKeepingAltText() {
        let markdown = "Before ![architecture diagram](https://example.com/diagram.png) after"
        let blocks = MarkdownBlockParser.parse(markdown)

        #expect(blocks == [.paragraph(text: "Before [Image: architecture diagram] after")])

        let renderedText = blocks.map(\.text).joined()
        #expect(!renderedText.contains("example.com"))
        #expect(!renderedText.contains("!["))
    }

    @Test func stripsReferenceStyleImages() {
        let blocks = MarkdownBlockParser.parse("Look ![logo][logo-ref] here")
        #expect(blocks == [.paragraph(text: "Look [Image: logo] here")])
    }

    @Test func joinsWrappedParagraphLines() {
        let blocks = MarkdownBlockParser.parse("first line\nsecond line")
        #expect(blocks == [.paragraph(text: "first line second line")])
    }

    @Test func logPlainTextFormat() {
        let messages = [
            ServerLogMessage(
                date: Date(timeIntervalSince1970: 0),
                level: .info,
                logger: "everything-server",
                data: .string("Roots updated: 0 root(s) received from client")
            ),
            ServerLogMessage(
                date: Date(timeIntervalSince1970: 60),
                level: .warning,
                logger: nil,
                data: .string("careful")
            ),
        ]

        #expect(
            ServerLogMessage.plainText(for: messages)
                == """
                1970-01-01T00:00:00Z [Info] everything-server Roots updated: 0 root(s) received from client
                1970-01-01T00:01:00Z [Warning] careful
                """)
        #expect(ServerLogMessage.plainText(for: []) == "")
    }
}
