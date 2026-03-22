import Foundation

/// In-memory document model. NOT @Observable — text lives in NSTextViews,
/// structural changes are signalled via a version counter in EditorView.
final class CRDTDocument {
    var blocks: [String: BlockState] = [:]
    var blockOrder: [String] = []

    let documentId: String

    init(documentId: String) {
        self.documentId = documentId
    }

    // MARK: - Block Operations

    @discardableResult
    func createBlock(type: BlockType = .paragraph, afterBlockId: String? = nil) -> String {
        let block = BlockState.empty(type: type)
        blocks[block.id] = block

        if let afterId = afterBlockId, let index = blockOrder.firstIndex(of: afterId) {
            blockOrder.insert(block.id, at: index + 1)
        } else {
            blockOrder.append(block.id)
        }

        return block.id
    }

    func deleteBlock(id: String) {
        blocks.removeValue(forKey: id)
        blockOrder.removeAll { $0 == id }
    }

    func moveBlock(id: String, afterBlockId: String?) {
        blockOrder.removeAll { $0 == id }
        if let afterId = afterBlockId, let index = blockOrder.firstIndex(of: afterId) {
            blockOrder.insert(id, at: index + 1)
        } else {
            blockOrder.insert(id, at: 0)
        }
    }

    func setBlockType(id: String, type: BlockType) {
        blocks[id]?.blockType = type
    }

    func setIndentLevel(id: String, level: Int) {
        blocks[id]?.indentLevel = level
    }

    // MARK: - Text (used for persistence and structural ops, NOT for keystroke sync)

    func setText(blockId: String, text: String) {
        blocks[blockId]?.text = text
    }

    func getText(blockId: String) -> String {
        blocks[blockId]?.text ?? ""
    }

    // MARK: - Spans (rich text)

    func setSpans(blockId: String, spans: [InlineSpan]) {
        blocks[blockId]?.spans = spans
    }

    func getSpans(blockId: String) -> [InlineSpan] {
        blocks[blockId]?.spans ?? [.plain("")]
    }

    // MARK: - State

    func orderedBlocks() -> [BlockState] {
        blockOrder.compactMap { blocks[$0] }
    }

    func ensureFirstBlock() {
        if blockOrder.isEmpty {
            createBlock(type: .paragraph)
        }
    }

    // MARK: - Snapshot Persistence

    func encodeSnapshot() -> Data? {
        let codableBlocks = blocks.mapValues { CodableBlockState(from: $0) }
        return try? JSONEncoder().encode(SnapshotData(blocks: codableBlocks, order: blockOrder))
    }

    func loadSnapshot(_ data: Data) {
        guard let snapshot = try? JSONDecoder().decode(SnapshotData.self, from: data) else { return }
        blocks = snapshot.blocks.mapValues { $0.toBlockState() }
        blockOrder = snapshot.order
    }
}

// MARK: - Codable Snapshot

private struct SnapshotData: Codable {
    let blocks: [String: CodableBlockState]
    let order: [String]
}

private struct CodableBlockState: Codable {
    let id: String
    let blockType: String
    let text: String
    let children: [String]
    let indentLevel: Int
    let meta: [String: String]
    let spans: [InlineSpan]?

    init(from block: BlockState) {
        self.id = block.id
        self.blockType = block.blockType.rawValue
        self.text = block.text
        self.children = block.children
        self.indentLevel = block.indentLevel
        self.meta = block.meta
        self.spans = block.spans
    }

    func toBlockState() -> BlockState {
        if let spans = spans, !spans.isEmpty {
            return BlockState(
                id: id,
                blockType: BlockType(rawValue: blockType) ?? .paragraph,
                spans: spans,
                children: children,
                indentLevel: indentLevel,
                meta: meta
            )
        }
        return BlockState(
            id: id,
            blockType: BlockType(rawValue: blockType) ?? .paragraph,
            text: text,
            children: children,
            indentLevel: indentLevel,
            meta: meta
        )
    }
}
