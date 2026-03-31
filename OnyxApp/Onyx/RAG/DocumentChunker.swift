import Foundation

struct TextChunk: Sendable, Codable {
    let id: String
    let documentId: String
    let documentTitle: String
    let heading: String?
    let content: String
    let wordCount: Int
}

struct DocumentChunker: Sendable {
    static let maxChunkWords = 400
    static let overlapWords = 50

    func chunk(text: String, documentId: String, title: String) -> [TextChunk] {
        let body = stripFrontmatter(text)
        let sections = splitByHeadings(body)

        var chunks: [TextChunk] = []
        var chunkIndex = 0

        for section in sections {
            let parts = splitLargeSection(
                section.content,
                maxWords: Self.maxChunkWords,
                overlap: Self.overlapWords
            )
            for part in parts {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                chunks.append(TextChunk(
                    id: "\(documentId)_\(chunkIndex)",
                    documentId: documentId,
                    documentTitle: title,
                    heading: section.heading,
                    content: trimmed,
                    wordCount: trimmed.split(whereSeparator: { $0.isWhitespace }).count
                ))
                chunkIndex += 1
            }
        }

        return chunks
    }

    // MARK: - Frontmatter

    private func stripFrontmatter(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.first == "---" else { return text }
        for (i, line) in lines.dropFirst().enumerated() {
            if line == "---" {
                return lines.dropFirst(i + 2).joined(separator: "\n")
            }
        }
        return text
    }

    // MARK: - Section splitting

    private struct Section {
        let heading: String?
        let content: String
    }

    private func splitByHeadings(_ text: String) -> [Section] {
        let lines = text.components(separatedBy: "\n")
        var sections: [Section] = []
        var currentHeading: String? = nil
        var currentLines: [String] = []

        for line in lines {
            if line.hasPrefix("#") {
                // Flush current section
                let content = currentLines.joined(separator: "\n")
                if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sections.append(Section(heading: currentHeading, content: content))
                }
                // Extract heading text
                currentHeading = line.drop(while: { $0 == "#" })
                    .trimmingCharacters(in: .whitespaces)
                currentLines = []
            } else {
                currentLines.append(line)
            }
        }

        // Flush last section
        let content = currentLines.joined(separator: "\n")
        if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(Section(heading: currentHeading, content: content))
        }

        // If the entire document had no headings, return it as one section with the title
        if sections.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(Section(heading: nil, content: text))
        }

        return sections
    }

    // MARK: - Large section splitting with overlap

    private func splitLargeSection(_ text: String, maxWords: Int, overlap: Int) -> [String] {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        guard words.count > maxWords else { return [text] }

        var parts: [String] = []
        var start = 0

        while start < words.count {
            let end = min(start + maxWords, words.count)
            let slice = words[start..<end].joined(separator: " ")
            parts.append(slice)

            let next = end - overlap
            // Ensure forward progress — without this, the last chunk loops forever
            // when remaining words < overlap
            if next <= start {
                break
            }
            start = next
        }

        return parts
    }
}
