import Foundation

enum MarkdownSerializer {

    // MARK: - Serialize blocks to markdown with frontmatter

    static func serialize(blocks: [BlockState], metadata: DocumentMetadata) -> String {
        var lines: [String] = []

        // Frontmatter
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        lines.append("---")
        lines.append("id: \(metadata.id)")
        lines.append("created: \(iso.string(from: metadata.created))")
        lines.append("updated: \(iso.string(from: metadata.updated))")
        if !metadata.tags.isEmpty {
            lines.append("tags: [\(metadata.tags.joined(separator: ", "))]")
        } else {
            lines.append("tags: []")
        }
        for key in metadata.customProperties.keys.sorted() {
            lines.append("\(key): \(metadata.customProperties[key]!)")
        }
        lines.append("---")
        lines.append("")

        // Body
        for block in blocks {
            let text = spanToMarkdown(block.spans)
            let indent = String(repeating: "  ", count: block.indentLevel)

            switch block.blockType {
            case .heading1:
                lines.append("\(indent)# \(text)")
            case .heading2:
                lines.append("\(indent)## \(text)")
            case .heading3:
                lines.append("\(indent)### \(text)")
            case .bulletList:
                lines.append("\(indent)- \(text)")
            case .numberedList:
                lines.append("\(indent)1. \(text)")
            case .code:
                lines.append("\(indent)```")
                lines.append("\(indent)\(block.text)")
                lines.append("\(indent)```")
            case .quote:
                lines.append("\(indent)> \(text)")
            case .taskList:
                let checked = block.meta["checked"] == "true"
                let checkbox = checked ? "[x]" : "[ ]"
                lines.append("\(indent)- \(checkbox) \(text)")
            case .table:
                lines.append("\(indent)\(block.text)")
            case .divider:
                lines.append("\(indent)---")
            case .paragraph:
                lines.append("\(indent)\(text)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Deserialize markdown to blocks

    static func deserialize(markdown: String) -> (DocumentMetadata, [BlockState]) {
        let (metadata, body) = parseFrontmatter(markdown)
        let lines = body.components(separatedBy: "\n")
        var blocks: [BlockState] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            if trimmed.isEmpty {
                i += 1
                continue
            }

            let indentLevel = countIndent(line)

            // Code fence
            if trimmed.hasPrefix("```") {
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    let codeLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if codeLine.hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                let codeText = codeLines.joined(separator: "\n")
                blocks.append(BlockState(
                    id: UUID().uuidString.lowercased(),
                    blockType: .code,
                    text: codeText,
                    children: [],
                    indentLevel: indentLevel,
                    meta: [:]
                ))
                continue
            }

            // Divider (but not frontmatter)
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(BlockState(
                    id: UUID().uuidString.lowercased(),
                    blockType: .divider,
                    text: "",
                    children: [],
                    indentLevel: indentLevel,
                    meta: [:]
                ))
                i += 1
                continue
            }

            // Headings
            if trimmed.hasPrefix("### ") {
                let text = String(trimmed.dropFirst(4))
                blocks.append(makeBlock(.heading3, text: text, indent: indentLevel))
                i += 1
                continue
            }
            if trimmed.hasPrefix("## ") {
                let text = String(trimmed.dropFirst(3))
                blocks.append(makeBlock(.heading2, text: text, indent: indentLevel))
                i += 1
                continue
            }
            if trimmed.hasPrefix("# ") {
                let text = String(trimmed.dropFirst(2))
                blocks.append(makeBlock(.heading1, text: text, indent: indentLevel))
                i += 1
                continue
            }

            // Task list (before bullet list)
            if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                let isChecked = trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ")
                let text = String(trimmed.dropFirst(6))
                var block = makeBlock(.taskList, text: text, indent: indentLevel)
                block.meta["checked"] = isChecked ? "true" : "false"
                blocks.append(block)
                i += 1
                continue
            }

            // Table (header row + separator row + data rows)
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && i + 1 < lines.count {
                let nextTrimmed = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if nextTrimmed.hasPrefix("|") && nextTrimmed.contains("---") {
                    var tableLines: [String] = [lines[i]]
                    var j = i + 1
                    while j < lines.count {
                        let tLine = lines[j].trimmingCharacters(in: .whitespaces)
                        if tLine.hasPrefix("|") && tLine.hasSuffix("|") {
                            tableLines.append(lines[j])
                            j += 1
                        } else {
                            break
                        }
                    }
                    let tableText = tableLines.joined(separator: "\n")
                    blocks.append(BlockState(
                        id: UUID().uuidString.lowercased(),
                        blockType: .table,
                        text: tableText,
                        children: [],
                        indentLevel: indentLevel,
                        meta: [:]
                    ))
                    i = j
                    continue
                }
            }

            // Bullet list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let text = String(trimmed.dropFirst(2))
                blocks.append(makeBlock(.bulletList, text: text, indent: indentLevel))
                i += 1
                continue
            }

            // Numbered list
            if let dotRange = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                let text = String(trimmed[dotRange.upperBound...])
                blocks.append(makeBlock(.numberedList, text: text, indent: indentLevel))
                i += 1
                continue
            }

            // Quote
            if trimmed.hasPrefix("> ") {
                let text = String(trimmed.dropFirst(2))
                blocks.append(makeBlock(.quote, text: text, indent: indentLevel))
                i += 1
                continue
            }

            // Paragraph
            blocks.append(makeBlock(.paragraph, text: trimmed, indent: indentLevel))
            i += 1
        }

        return (metadata, blocks)
    }

    // MARK: - Inline span to markdown string

    private static func spanToMarkdown(_ spans: [InlineSpan]) -> String {
        spans.map { span in
            var text = span.text

            if let wikiLink = span.wikiLink {
                text = "[[\(wikiLink)]]"
            } else if let link = span.link {
                text = "[\(text)](\(link))"
            }
            if span.styles.contains(.bold) {
                text = "**\(text)**"
            }
            if span.styles.contains(.italic) {
                text = "*\(text)*"
            }
            if span.styles.contains(.code) {
                text = "`\(text)`"
            }
            if span.styles.contains(.strikethrough) {
                text = "~~\(text)~~"
            }

            return text
        }.joined()
    }

    // MARK: - Parse markdown inline formatting to spans

    private static func makeBlock(_ type: BlockType, text: String, indent: Int) -> BlockState {
        let spans = parseInlineMarkdown(text)
        return BlockState(
            id: UUID().uuidString.lowercased(),
            blockType: type,
            spans: spans,
            children: [],
            indentLevel: indent,
            meta: [:]
        )
    }

    private static func parseInlineMarkdown(_ text: String) -> [InlineSpan] {
        var spans: [InlineSpan] = []
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            // Bold: **text**
            if remaining.hasPrefix("**"),
               let endRange = remaining[remaining.index(remaining.startIndex, offsetBy: 2)...].range(of: "**") {
                let inner = String(remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<endRange.lowerBound])
                spans.append(InlineSpan(text: inner, styles: [.bold]))
                remaining = remaining[endRange.upperBound...]
                continue
            }

            // Italic: *text*
            if remaining.hasPrefix("*") && !remaining.hasPrefix("**"),
               let endRange = remaining[remaining.index(after: remaining.startIndex)...].range(of: "*") {
                let inner = String(remaining[remaining.index(after: remaining.startIndex)..<endRange.lowerBound])
                spans.append(InlineSpan(text: inner, styles: [.italic]))
                remaining = remaining[endRange.upperBound...]
                continue
            }

            // Code: `text`
            if remaining.hasPrefix("`"),
               let endRange = remaining[remaining.index(after: remaining.startIndex)...].range(of: "`") {
                let inner = String(remaining[remaining.index(after: remaining.startIndex)..<endRange.lowerBound])
                spans.append(InlineSpan(text: inner, styles: [.code]))
                remaining = remaining[endRange.upperBound...]
                continue
            }

            // Strikethrough: ~~text~~
            if remaining.hasPrefix("~~"),
               let endRange = remaining[remaining.index(remaining.startIndex, offsetBy: 2)...].range(of: "~~") {
                let inner = String(remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<endRange.lowerBound])
                spans.append(InlineSpan(text: inner, styles: [.strikethrough]))
                remaining = remaining[endRange.upperBound...]
                continue
            }

            // Wiki link: [[Document Name]]
            if remaining.hasPrefix("[["),
               let closeRange = remaining.range(of: "]]") {
                let innerStart = remaining.index(remaining.startIndex, offsetBy: 2)
                let title = String(remaining[innerStart..<closeRange.lowerBound])
                spans.append(InlineSpan(text: title, wikiLink: title))
                remaining = remaining[closeRange.upperBound...]
                continue
            }

            // Link: [text](url)
            if remaining.hasPrefix("["),
               let bracketEnd = remaining.range(of: "]("),
               let parenEnd = remaining[bracketEnd.upperBound...].range(of: ")") {
                let linkText = String(remaining[remaining.index(after: remaining.startIndex)..<bracketEnd.lowerBound])
                let url = String(remaining[bracketEnd.upperBound..<parenEnd.lowerBound])
                spans.append(InlineSpan(text: linkText, link: url))
                remaining = remaining[parenEnd.upperBound...]
                continue
            }

            // Plain text until next special character
            var endIdx = remaining.index(after: remaining.startIndex)
            let specials: [Character] = ["*", "`", "~", "["]
            while endIdx < remaining.endIndex && !specials.contains(remaining[endIdx]) {
                endIdx = remaining.index(after: endIdx)
            }
            let plain = String(remaining[remaining.startIndex..<endIdx])
            if let last = spans.last, last.styles.isEmpty && last.link == nil {
                spans[spans.count - 1].text += plain
            } else {
                spans.append(.plain(plain))
            }
            remaining = remaining[endIdx...]
        }

        return spans.isEmpty ? [.plain("")] : spans
    }

    // MARK: - Public frontmatter helpers

    static func extractMetadata(from markdown: String) -> DocumentMetadata {
        let (metadata, _) = parseFrontmatter(markdown)
        return metadata
    }

    static func generateFrontmatter(metadata: DocumentMetadata) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        var lines: [String] = []
        lines.append("---")
        lines.append("id: \(metadata.id)")
        lines.append("created: \(iso.string(from: metadata.created))")
        lines.append("updated: \(iso.string(from: metadata.updated))")
        if !metadata.tags.isEmpty {
            lines.append("tags: [\(metadata.tags.joined(separator: ", "))]")
        } else {
            lines.append("tags: []")
        }
        for key in metadata.customProperties.keys.sorted() {
            lines.append("\(key): \(metadata.customProperties[key]!)")
        }
        lines.append("---")
        return lines.joined(separator: "\n")
    }

    static func replaceFrontmatter(in markdown: String, with metadata: DocumentMetadata) -> String {
        let (_, body) = parseFrontmatter(markdown)
        return generateFrontmatter(metadata: metadata) + "\n" + body
    }

    // MARK: - Frontmatter parsing

    static func parseFrontmatter(_ markdown: String) -> (DocumentMetadata, String) {
        let lines = markdown.components(separatedBy: "\n")

        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return (DocumentMetadata(), markdown)
        }

        var endIndex: Int?
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                endIndex = i
                break
            }
        }

        guard let fmEnd = endIndex else {
            return (DocumentMetadata(), markdown)
        }

        let fmLines = Array(lines[1..<fmEnd])
        var fm: [String: String] = [:]
        for line in fmLines {
            if let colonIdx = line.firstIndex(of: ":") {
                let key = line[line.startIndex..<colonIdx].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
                fm[key] = value
            }
        }

        // Handle multi-line YAML list for tags (e.g. "tags:\n  - tag1\n  - tag2")
        if fm["tags"]?.isEmpty == true {
            var yamlTags: [String] = []
            var inTags = false
            for line in fmLines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == "tags:" { inTags = true; continue }
                if inTags {
                    if trimmed.hasPrefix("- ") {
                        yamlTags.append(String(trimmed.dropFirst(2)))
                    } else {
                        inTags = false
                    }
                }
            }
            if !yamlTags.isEmpty {
                fm["tags"] = "[\(yamlTags.joined(separator: ", "))]"
            }
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let dateOnly = DateFormatter()
        dateOnly.dateFormat = "yyyy-MM-dd"

        let id = fm["id"] ?? UUID().uuidString.lowercased()
        let created = fm["created"].flatMap { iso.date(from: $0) ?? dateOnly.date(from: $0) } ?? Date()
        let updated = fm["updated"].flatMap { iso.date(from: $0) ?? dateOnly.date(from: $0) } ?? Date()
        let tagsStr = fm["tags"]?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")) ?? ""
        let tags = tagsStr.isEmpty ? [] : tagsStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        let reservedKeys: Set<String> = ["id", "created", "updated", "tags"]
        var customProperties: [String: String] = [:]
        for (key, value) in fm where !reservedKeys.contains(key) {
            customProperties[key] = value
        }

        let metadata = DocumentMetadata(id: id, created: created, updated: updated, tags: tags, customProperties: customProperties)
        let body = lines[(fmEnd + 1)...].joined(separator: "\n")

        return (metadata, body)
    }

    private static func countIndent(_ line: String) -> Int {
        var spaces = 0
        for char in line {
            if char == " " { spaces += 1 }
            else if char == "\t" { spaces += 2 }
            else { break }
        }
        return spaces / 2
    }
}
