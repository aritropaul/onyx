import Foundation

enum BlockType: String, CaseIterable, Identifiable {
    case paragraph
    case heading1
    case heading2
    case heading3
    case bulletList
    case numberedList
    case code
    case quote
    case divider
    case taskList
    case table

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .paragraph: "Text"
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .bulletList: "Bullet List"
        case .numberedList: "Numbered List"
        case .code: "Code"
        case .quote: "Quote"
        case .divider: "Divider"
        case .taskList: "Task List"
        case .table: "Table"
        }
    }

    var icon: String {
        switch self {
        case .paragraph: "text.alignleft"
        case .heading1: "textformat.size.larger"
        case .heading2: "textformat.size"
        case .heading3: "textformat.size.smaller"
        case .bulletList: "list.bullet"
        case .numberedList: "list.number"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .quote: "text.quote"
        case .divider: "minus"
        case .taskList: "checklist"
        case .table: "tablecells"
        }
    }

    var slashCommand: String {
        switch self {
        case .paragraph: "/text"
        case .heading1: "/h1"
        case .heading2: "/h2"
        case .heading3: "/h3"
        case .bulletList: "/bullet"
        case .numberedList: "/number"
        case .code: "/code"
        case .quote: "/quote"
        case .divider: "/divider"
        case .taskList: "/task"
        case .table: "/table"
        }
    }
}

struct BlockState: Identifiable, Equatable {
    let id: String
    var blockType: BlockType
    var spans: [InlineSpan]
    var children: [String]
    var indentLevel: Int
    var meta: [String: String]

    var text: String {
        get { spans.map(\.text).joined() }
        set { spans = [.plain(newValue)] }
    }

    init(id: String, blockType: BlockType, text: String, children: [String], indentLevel: Int, meta: [String: String]) {
        self.id = id
        self.blockType = blockType
        self.spans = [.plain(text)]
        self.children = children
        self.indentLevel = indentLevel
        self.meta = meta
    }

    init(id: String, blockType: BlockType, spans: [InlineSpan], children: [String], indentLevel: Int, meta: [String: String]) {
        self.id = id
        self.blockType = blockType
        self.spans = spans
        self.children = children
        self.indentLevel = indentLevel
        self.meta = meta
    }

    static func empty(type: BlockType = .paragraph) -> BlockState {
        BlockState(
            id: UUID().uuidString.lowercased(),
            blockType: type,
            spans: [.plain("")],
            children: [],
            indentLevel: 0,
            meta: [:]
        )
    }
}
