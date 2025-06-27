# Companion

<img align="right" width="128" src="/Companion/Assets.xcassets/AppIcon.appiconset/Icon-macOS-512x512@2x.png" alt="Screenshot of iMCP on first launch" />

**Companion** is a utility for testing and debugging your MCP servers
on macOS, iOS, and visionOS.
It's built using the
[official Swift SDK](https://github.com/modelcontextprotocol/swift-sdk).

<br clear="all">

![Screenshot of Companion on macOS showing MCP tool detail](/Assets/companion-macos-tool-detail.png)

> [!IMPORTANT]  
> Companion is in early development and is still missing some important features,
> including authentication, roots, and sampling.
>
> For a more complete MCP debugging experience, check out the
> [MCP Inspector](https://modelcontextprotocol.io/docs/tools/inspector).

## Features

- [x] Connect to local and remote MCP servers
- [x] Easily browse available prompts, resources, and tools
- [x] Call tools, generate prompts with arguments, and download resources

## Getting Started

First, [download the Companion app](https://github.com/loopwork/Companion/releases/latest/download/Companion.zip)
(requires macOS 15 or later).

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

- Xcode 16.3+
- macOS Sequoia 15+
- iOS / iPadOS 16+
- visionOS 2+

## License

This project is licensed under the Apache License, Version 2.0.

The app icon is a playful nod to [Finder](https://en.wikipedia.org/wiki/Finder_%28software%29) and
[Henohenomoheji](https://en.wikipedia.org/wiki/Henohenomoheji) (へのへのもへじ),
a face drawn by Japanese schoolchildren using hiragana characters.
Finder® is a trademark of Apple Inc.

This project is not affiliated with, endorsed, or sponsored by Apple Inc.
