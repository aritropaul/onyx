---
id: e9e2bd03-9ff0-4828-befb-8b1c0424ce31
created: 2026-03-21T23:21:44Z
updated: 2026-03-22T03:17:44Z
tags: []
---
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Onyx is a collaborative document editor (Obsidian/Notion alternative) with three components:
- **onyx-crdt** — Rust CRDT library using Yrs (Yjs), exposed to Swift via UniFFI XCFramework
- **onyx-server** — Rust WebSocket sync server (Axum + Tokio + SQLite)
- **OnyxApp** — Native macOS SwiftUI app (Swift 6, macOS 26.0, GRDB for local persistence)

## Build Commands

```bash
make crdt          # Build XCFramework from Rust CRDT (runs build-xcframework.sh)
make server        # cargo build --release -p onyx-server
make server-run    # cargo run --release -p onyx-server
make test          # cargo test --workspace (Rust tests only)
make all           # Build both crdt and server
make clean         # Clean cargo + xcframework artifacts
make docker-up     # Build and run server in Docker (port 3000)
```

**macOS app**: Open `OnyxApp/Onyx.xcodeproj` in Xcode or build with:
```bash
xcodebuild -project OnyxApp/Onyx.xcodeproj -scheme Onyx -configuration Debug build
```

The Xcode project is generated from `OnyxApp/project.yml` using XcodeGen.

## Architecture

### Data Flow: Collaborative Editing

1. User edits text in `MarkdownNSTextView` (custom NSTextView subclass)
2. `MarkdownHighlighter` applies syntax highlighting and block-level formatting
3. `CRDTDocument` maintains in-memory block structure (blocks map + blockOrder array)
4. `SyncManager` sends updates via WebSocket to `onyx-server`
5. Server broadcasts to other clients and persists snapshots to SQLite

### CRDT Layer (onyx-crdt)

The Yrs document stores blocks as a Y.Map ("blocks") with nested maps per block (type, content as Y.Text, children as Y.Array, indent, meta) and a Y.Array ("block_order") for ordering. The UDL interface definition is at `onyx-crdt/uniffi/onyx_crdt.udl`.

Build produces: `onyx-crdt/OnyxCRDTFFI.xcframework` + `onyx-crdt/generated/onyx_crdt.swift`

### Server (onyx-server)

Routes: `POST /auth/register`, `POST /auth/login`, `GET /auth/me`, `GET /docs/{doc_id}` (WebSocket), `GET /health`

Binary protocol: `[1-byte type][payload]` — 0x00 SyncStep1, 0x01 SyncStep2, 0x02 Update, 0x03 Awareness

Env vars: `ONYX_DB_PATH` (default: "onyx.db"), `ONYX_BIND` (default: "0.0.0.0:3000"), `ONYX_JWT_SECRET`

### macOS App (OnyxApp)

Key editor files:
- `Editor/MarkdownNSTextView.swift` — Custom NSTextView with decoration drawing
- `Editor/MarkdownHighlighter.swift` — Regex-based syntax highlighting with block styling
- `Editor/MarkdownEditorField.swift` — SwiftUI coordinator bridging NSTextView

Data layer: GRDB with tables for team, project, document. Documents store both `crdtSnapshot` (BLOB) and `markdownText` (String).

Sync: `SyncClient.swift` (WebSocket with exponential backoff) + `SyncManager.swift` (protocol orchestration, connects to `ws://localhost:3001/docs/{docId}`)

### Block Types

Paragraph, Heading1-3, BulletList, NumberedList, Code, Quote, Divider, TaskList, Table (Swift has all 11; Rust UDL has 9 — no TaskList/Table yet)
