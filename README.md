# Companion

<img align="right" width="128" src="/Companion/Assets.xcassets/AppIcon.appiconset/Icon-macOS-512x512@2x.png" alt="Companion app icon" />

**Companion** is a utility for testing and debugging your MCP servers
on macOS, iOS, and visionOS.
It's built using the
[official Swift SDK](https://github.com/modelcontextprotocol/swift-sdk).

<br clear="all">

![Screenshot of Companion on macOS showing MCP tool detail](/Assets/companion-macos-tool-detail.png)

> [!IMPORTANT]
> Companion is in early development.
> It implements the MCP client feature set through protocol version 2025-11-25,
> with two exceptions.
> Sampling runs without tool use,
> so a server that asks for sampling with tools gets a text completion.
> The experimental Tasks feature is not supported by the Swift SDK yet.
>
> For another MCP debugging experience, check out the
> [MCP Inspector](https://modelcontextprotocol.io/docs/tools/inspector).

## Features

- [x] Connect to local (STDIO) and remote (Streamable HTTP) MCP servers
- [x] Browse prompts, resources, and tools, with live list updates
- [x] Call tools with progress reporting, cancellation, and structured output
- [x] Generate prompts and read resources,
  with argument completions and resource subscriptions
- [x] View server log messages and set the logging level
- [x] Ping servers to check that they respond
- [x] Answer sampling requests with Apple Foundation Models
  or your own OpenAI, Anthropic, Gemini, or Ollama model
- [x] Respond to elicitation requests in form and URL modes
- [x] Share per-server roots with servers that ask for them
- [x] Authenticate with custom headers, a bearer token, or OAuth 2.1 sign-in

## Getting Started

First, [download the Companion app](https://github.com/mattt/Companion/releases/latest/download/Companion.zip)
(requires macOS 15 or later).

Or, if you have [Homebrew](https://brew.sh) installed,
you can run the following command:

```console
brew install --cask mattt/tap/Companion
```

<img align="right" width="344" src="/Assets/companion-macos-add-server.png" alt="Screenshot of Companion on macOS showing Add server sheet" />

When you open the app,
you'll see a sidebar on the left and a placeholder view on the right.
Click the <kbd>+</kbd> button in the toolbar to add an MCP server.

> [!TIP]
> Looking for a fun MCP server?
> Check out [iMCP](https://iMCP.app/?ref=Companion),
> which gives models access to your Messages, Contacts, Reminders and more.
>
> Click on the iMCP menubar icon,
> select "Copy server command to clipboard",
> and paste that into the "Command" field for your STDIO server.

Once you add a server,
it'll automatically connect.
When it does, it'll show available prompts, resources, and tools.
Click on one of those sections to see a list, and drill into whatever you're interested in.
Or, select the parent item in the sidebar to get information about the server.

## Requirements

- Xcode 27+
- macOS Sequoia 15.4+
- iOS / iPadOS 18.4+
- visionOS 2.4+

## License

This project is available under the MIT license.
See the LICENSE file for more info.

## Legal

The app icon is a playful nod to [Finder](https://en.wikipedia.org/wiki/Finder_%28software%29) and
[Henohenomoheji](https://en.wikipedia.org/wiki/Henohenomoheji) (へのへのもへじ),
a face drawn by Japanese schoolchildren using hiragana characters.
Finder® is a trademark of Apple Inc.

This project is not affiliated with, endorsed, or sponsored by Apple Inc.
