# Onyx

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A collaborative document editor -- a native-first alternative to Obsidian and Notion.

![Screenshot](docs/screenshot.png) <!-- TODO: add screenshot -->

## Components

- **onyx-crdt** -- Rust CRDT library using Yrs (Yjs), exposed to Swift via UniFFI XCFramework
- **onyx-server** -- Rust WebSocket sync server (Axum + Tokio + SQLite)
- **OnyxApp** -- Native macOS SwiftUI app (Swift 6, macOS 26.0, GRDB for local persistence)

## Features

- Liquid glass UI with macOS 26 glass effects
- Markdown editor with syntax highlighting, checklists, and wiki links
- Real-time collaboration via CRDT
- Built-in AI assistant (Claude integration)
- Vault-based file system (like Obsidian)
- Command palette, frontmatter properties, and tags

## Build

```
make crdt          # Build XCFramework from Rust CRDT
make server        # cargo build --release -p onyx-server
make server-run    # cargo run --release -p onyx-server
make test          # cargo test --workspace
make all           # Build both crdt and server
```

### macOS App

Open `OnyxApp/Onyx.xcodeproj` in Xcode, or build from the command line:

```
xcodebuild -project OnyxApp/Onyx.xcodeproj -scheme Onyx build
```

## Requirements

- macOS 26.0+
- Xcode 16+
- Rust toolchain

## License

MIT
