import Foundation

struct Backlink: Identifiable {
    let id: String
    let sourceDocId: String
    let sourceTitle: String
    let context: String
}

@Observable @MainActor
final class BacklinkEngine {
    /// Map: lowercased target title -> [Backlink]
    private var reverseIndex: [String: [Backlink]] = [:]

    func backlinks(for title: String) -> [Backlink] {
        reverseIndex[title.lowercased()] ?? []
    }

    var isEmpty: Bool { reverseIndex.isEmpty }

    func rebuild(documents: [DocumentInfo], provider: any DocumentProvider) {
        let docs = documents
        Task {
            let newIndex = await Self.buildIndex(docs: docs, provider: provider)
            self.reverseIndex = newIndex
        }
    }

    nonisolated private static func buildIndex(docs: [DocumentInfo], provider: any DocumentProvider) async -> [String: [Backlink]] {
        var newIndex: [String: [Backlink]] = [:]
        var counter = 0

        for doc in docs {
            guard let content = try? await provider.loadDocument(id: doc.id) else { continue }
            let links = extractWikiLinks(from: content.text)

            for link in links {
                let key = link.target.lowercased()
                counter += 1
                let backlink = Backlink(
                    id: "bl-\(counter)",
                    sourceDocId: doc.id,
                    sourceTitle: doc.title,
                    context: link.context
                )
                newIndex[key, default: []].append(backlink)
            }
        }

        return newIndex
    }

    // MARK: - Wiki Link Extraction

    private struct WikiLink {
        let target: String
        let context: String
    }

    nonisolated private static func extractWikiLinks(from text: String) -> [WikiLink] {
        var links: [WikiLink] = []
        let pattern = /\[\[([^\]]+)\]\]/
        let lines = text.components(separatedBy: "\n")

        for line in lines {
            for match in line.matches(of: pattern) {
                let target = String(match.1)
                    .components(separatedBy: "|").first ?? String(match.1) // handle [[target|display]]
                links.append(WikiLink(
                    target: target.trimmingCharacters(in: .whitespaces),
                    context: line.trimmingCharacters(in: .whitespaces)
                ))
            }
        }

        return links
    }
}
