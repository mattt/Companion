# Companion

<img align="right" width="128" src="/Companion/Assets.xcassets/AppIcon.appiconset/Icon-macOS-512x512@2x.png" alt="Screenshot of iMCP on first launch" />

**Companion** is a utility for testing and debugging your MCP servers
on macOS, iOS, and visionOS.
It's built using the
[official Swift SDK](https://github.com/modelcontextprotocol/swift-sdk).

<br clear="all">

![Companion on macOS showing MCP tool detail](/Assets/companion-macos-tool-detail.png)

> [!IMPORTANT]  
> Companion is in early development and is still missing some important features,
> including authentication, roots, and sampling.
>
> For a more complete MCP debugging experience, check out the
> [MCP Inspector](https://modelcontextprotocol.io/docs/tools/inspector).

The app icon is a playful nod to [Finder](https://en.wikipedia.org/wiki/Finder_%28software%29) and
[Henohenomoheji](https://en.wikipedia.org/wiki/Henohenomoheji) (へのへのもへじ),
a face drawn by Japanese schoolchildren using hiragana characters.

## Features

- [x] Connect to local and remote MCP servers
- [x] Easily browse available prompts, resources, and tools
- [x] Call tools, generate prompts with arguments, and download resources

## Requirements

- Xcode 16.3+
- macOS Sequoia 15+
- iOS / iPadOS 16+
- visionOS 2+

> [!WARNING]  
> Pre-compiled builds will be available soon.
> In the meantime,
> you can build and run Companion on development devices
> using the latest release or pre-release of Xcode.

## License

This project is licensed under the Apache License, Version 2.0.
