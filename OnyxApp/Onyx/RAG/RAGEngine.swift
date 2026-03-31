import Foundation
import CryptoKit

struct RAGResult: Sendable {
    let chunk: TextChunk
    let score: Float
}

private struct RAGCache: Codable {
    let version: Int
    let entries: [VectorStore.SerializedEntry]
    let documentHashes: [String: String]
}

@Observable @MainActor
final class RAGEngine {
    // UI state
    var isIndexing = false
    var indexedDocumentCount = 0
    var totalChunks = 0

    // Context controls
    var pinnedDocIds: Set<String> = []
    var excludedDocIds: Set<String> = []

    // Index state — only touched on MainActor after swap
    private var vectorStore = VectorStore()
    private var bm25Index = BM25Index()
    private let chunker = DocumentChunker()
    private var vaultURL: URL?
    private var documentHashes: [String: String] = [:]

    nonisolated private static let cacheVersion = 2

    // MARK: - Pin / Exclude

    func togglePin(_ docId: String) {
        if pinnedDocIds.contains(docId) {
            pinnedDocIds.remove(docId)
        } else {
            pinnedDocIds.insert(docId)
            excludedDocIds.remove(docId)
        }
        saveContextPrefs()
    }

    func toggleExclude(_ docId: String) {
        if excludedDocIds.contains(docId) {
            excludedDocIds.remove(docId)
        } else {
            excludedDocIds.insert(docId)
            pinnedDocIds.remove(docId)
        }
        saveContextPrefs()
    }

    // MARK: - Load cached index (instant, call before indexVault)

    func loadCachedIndex(vaultURL: URL) {
        self.vaultURL = vaultURL
        let cacheFile = Self.cacheURL(for: vaultURL)

        let result: (entries: [VectorStore.SerializedEntry], hashes: [String: String])? = autoreleasepool {
            guard let data = try? Data(contentsOf: cacheFile),
                  let cache = try? JSONDecoder().decode(RAGCache.self, from: data),
                  cache.version == Self.cacheVersion else { return nil }
            return (cache.entries, cache.documentHashes)
        }

        guard let result else { return }

        vectorStore.load(from: result.entries)

        bm25Index.clear()
        for entry in result.entries {
            bm25Index.add(chunk: entry.chunk)
        }

        documentHashes = result.hashes
        indexedDocumentCount = Set(result.entries.map(\.chunk.documentId)).count
        totalChunks = result.entries.count

        loadContextPrefs()
    }

    // MARK: - Incremental vault indexing

    func indexVault(provider: any DocumentProvider, vaultURL: URL? = nil) {
        guard !isIndexing else { return }
        if let vaultURL { self.vaultURL = vaultURL }
        isIndexing = true
        let chunker = self.chunker
        let saveURL = self.vaultURL
        let oldHashes = self.documentHashes
        let existingEntries = self.vectorStore.serialize()

        Task.detached {
            let docs = (try? await provider.allDocuments()) ?? []
            let currentDocIds = Set(docs.map(\.id))
            let oldDocIds = Set(oldHashes.keys)

            var newHashes: [String: String] = [:]
            var changedDocs: [(id: String, title: String, text: String)] = []
            var unchangedDocIds: Set<String> = []

            // Load each document and check for changes
            for doc in docs {
                guard let content = try? await provider.loadDocument(id: doc.id) else { continue }
                let hash = Self.contentHash(content.text)
                newHashes[doc.id] = hash

                if oldHashes[doc.id] == hash {
                    unchangedDocIds.insert(doc.id)
                } else {
                    changedDocs.append((id: doc.id, title: doc.title, text: content.text))
                }
            }

            // Build new indexes: keep unchanged entries, re-chunk changed ones
            let newVectorStore = VectorStore()
            let newBM25 = BM25Index()

            // Re-add unchanged entries from serialized cache (no re-embedding needed)
            for entry in existingEntries {
                if unchangedDocIds.contains(entry.chunk.documentId) {
                    newVectorStore.addSerialized(entry)
                    newBM25.add(chunk: entry.chunk)
                }
            }

            // Process changed/new documents
            for doc in changedDocs {
                autoreleasepool {
                    let chunks = chunker.chunk(text: doc.text, documentId: doc.id, title: doc.title)
                    for chunk in chunks {
                        newVectorStore.add(chunk: chunk)
                        newBM25.add(chunk: chunk)
                    }
                }
            }

            newVectorStore.unloadEmbedding()

            if let saveURL {
                Self.saveToDisk(vectorStore: newVectorStore, hashes: newHashes, vaultURL: saveURL)
            }

            let docCount = docs.count
            let chunkCount = newBM25.count
            let removedCount = oldDocIds.subtracting(currentDocIds).count
            let changedCount = changedDocs.count
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.vectorStore = newVectorStore
                self.bm25Index = newBM25
                self.documentHashes = newHashes
                self.indexedDocumentCount = docCount
                self.totalChunks = chunkCount
                self.isIndexing = false
            }
        }
    }

    // MARK: - Incremental single-document update

    func updateDocument(id: String, text: String, title: String) {
        let hash = Self.contentHash(text)
        guard documentHashes[id] != hash else { return } // unchanged
        documentHashes[id] = hash

        vectorStore.remove(documentId: id)
        bm25Index.remove(documentId: id)
        let chunks = chunker.chunk(text: text, documentId: id, title: title)
        for chunk in chunks {
            vectorStore.add(chunk: chunk)
            bm25Index.add(chunk: chunk)
        }
        totalChunks = bm25Index.count
        saveInBackground()
    }

    func removeDocument(id: String) {
        vectorStore.remove(documentId: id)
        bm25Index.remove(documentId: id)
        documentHashes.removeValue(forKey: id)
        totalChunks = bm25Index.count
        saveInBackground()
    }

    // MARK: - Search

    func search(query: String, topK: Int = 5) -> [RAGResult] {
        let vectorHits = vectorStore.search(query: query, topK: topK * 2)
        let bm25Hits = bm25Index.search(query: query, topK: topK * 2)

        // Reciprocal rank fusion
        var fusedScores: [String: Float] = [:]
        var chunkMap: [String: TextChunk] = [:]
        let k: Float = 60

        for (rank, hit) in vectorHits.enumerated() {
            fusedScores[hit.chunk.id, default: 0] += 1.0 / (k + Float(rank + 1))
            chunkMap[hit.chunk.id] = hit.chunk
        }

        for (rank, hit) in bm25Hits.enumerated() {
            fusedScores[hit.chunk.id, default: 0] += 1.0 / (k + Float(rank + 1))
            chunkMap[hit.chunk.id] = hit.chunk
        }

        return fusedScores
            .sorted { $0.value > $1.value }
            .compactMap { id, score in
                guard let chunk = chunkMap[id] else { return nil }
                // Filter out excluded documents
                if excludedDocIds.contains(chunk.documentId) { return nil }
                return RAGResult(chunk: chunk, score: score)
            }
            .prefix(topK)
            .map { $0 }
    }

    /// Build a context block to prepend to the user's prompt for Claude.
    /// Returns the context string and the results used.
    func buildContext(for query: String, topK: Int = 5) -> (context: String, results: [RAGResult]) {
        var results = search(query: query, topK: topK)

        // Add pinned documents (always included, at the top)
        let pinnedResults = pinnedChunks()
        let existingIds = Set(results.map(\.chunk.documentId))
        let newPinned = pinnedResults.filter { !existingIds.contains($0.chunk.documentId) }
        results = newPinned + results

        guard !results.isEmpty else { return ("", []) }

        var ctx = "<context>\nRelevant notes from your vault:\n\n"
        for (i, r) in results.enumerated() {
            ctx += "[\(i + 1)] \(r.chunk.documentTitle)"
            if let h = r.chunk.heading { ctx += " > \(h)" }
            if pinnedDocIds.contains(r.chunk.documentId) { ctx += " (pinned)" }
            ctx += "\n\(r.chunk.content)\n\n"
        }
        ctx += "</context>"
        return (ctx, results)
    }

    private func pinnedChunks() -> [RAGResult] {
        guard !pinnedDocIds.isEmpty else { return [] }
        var results: [RAGResult] = []
        for entry in vectorStore.serialize() {
            if pinnedDocIds.contains(entry.chunk.documentId) {
                // Take only the first chunk per pinned document
                if !results.contains(where: { $0.chunk.documentId == entry.chunk.documentId }) {
                    results.append(RAGResult(chunk: entry.chunk, score: 1.0))
                }
            }
        }
        return results
    }

    // MARK: - Content hash

    nonisolated private static func contentHash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return Array(digest).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Persistence

    nonisolated private static func cacheURL(for vaultURL: URL) -> URL {
        vaultURL
            .appendingPathComponent(".onyx", isDirectory: true)
            .appendingPathComponent("rag", isDirectory: true)
            .appendingPathComponent("index.json")
    }

    nonisolated private static func saveToDisk(vectorStore: VectorStore, hashes: [String: String], vaultURL: URL) {
        let ragDir = vaultURL
            .appendingPathComponent(".onyx", isDirectory: true)
            .appendingPathComponent("rag", isDirectory: true)
        try? FileManager.default.createDirectory(at: ragDir, withIntermediateDirectories: true)

        autoreleasepool {
            let cache = RAGCache(version: cacheVersion, entries: vectorStore.serialize(), documentHashes: hashes)
            if let data = try? JSONEncoder().encode(cache) {
                try? data.write(to: ragDir.appendingPathComponent("index.json"), options: .atomic)
            }
        }
    }

    private func saveInBackground() {
        guard let vaultURL else { return }
        let serialized = vectorStore.serialize()
        let hashes = documentHashes
        Task.detached {
            autoreleasepool {
                Self.saveToDisk(vectorStore: VectorStore(), hashes: hashes, vaultURL: vaultURL)
                // Actually save with the serialized entries
                let ragDir = vaultURL
                    .appendingPathComponent(".onyx", isDirectory: true)
                    .appendingPathComponent("rag", isDirectory: true)
                try? FileManager.default.createDirectory(at: ragDir, withIntermediateDirectories: true)

                let cache = RAGCache(version: Self.cacheVersion, entries: serialized, documentHashes: hashes)
                if let data = try? JSONEncoder().encode(cache) {
                    try? data.write(to: ragDir.appendingPathComponent("index.json"), options: .atomic)
                }
            }
        }
    }

    // MARK: - Context preferences persistence

    private func contextPrefsURL() -> URL? {
        vaultURL?
            .appendingPathComponent(".onyx", isDirectory: true)
            .appendingPathComponent("ai", isDirectory: true)
            .appendingPathComponent("context.json")
    }

    private func saveContextPrefs() {
        guard let url = contextPrefsURL() else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let prefs = ContextPrefs(pinned: Array(pinnedDocIds), excluded: Array(excludedDocIds))
        if let data = try? JSONEncoder().encode(prefs) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func loadContextPrefs() {
        guard let url = contextPrefsURL(),
              let data = try? Data(contentsOf: url),
              let prefs = try? JSONDecoder().decode(ContextPrefs.self, from: data) else { return }
        pinnedDocIds = Set(prefs.pinned)
        excludedDocIds = Set(prefs.excluded)
    }
}

private struct ContextPrefs: Codable {
    let pinned: [String]
    let excluded: [String]
}
