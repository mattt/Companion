# MCP Companion App - Agent Guidelines

## Build & Test Commands

- **Build**: `xcodebuild -scheme Companion -workspace Companion.xcodeproj/project.xcworkspace build`
- **Test All**: `xcodebuild -scheme Companion -workspace Companion.xcodeproj/project.xcworkspace test`
- **Single Test**: `xcodebuild -scheme Companion -workspace Companion.xcodeproj/project.xcworkspace test -only-testing:CompanionTests/TestClassName/testMethodName`
- **UI Tests**: `xcodebuild -scheme Companion -workspace Companion.xcodeproj/project.xcworkspace test -only-testing:CompanionUITests`

* Ignore SourceKit warnings about missing types/modules - assume they exist
