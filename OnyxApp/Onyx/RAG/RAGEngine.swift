import Foundation

struct RAGResult: Sendable {
    let chunk: TextChunk
    let score: Float
}

private struct RAGCache: Codable {
    let version: Int
    let entries: [VectorStore.SerializedEntry]
}

@Observable @MainActor
final class RAGEngine {
    // UI state
    var isIndexing = false
    var indexedDocumentCount = 0
    var totalChunks = 0

    // Index state — only touched on MainActor after swap
    private var vectorStore = VectorStore()
    private var bm25Index = BM25Index()
    private let chunker = DocumentChunker()
    private var vaultURL: URL?

    nonisolated private static let cacheVersion = 1

    // MARK: - Load cached index (instant, call before indexVault)

    func loadCachedIndex(vaultURL: URL) {
        self.vaultURL = vaultURL
        let cacheFile = Self.cacheURL(for: vaultURL)

        // Decode inside autoreleasepool so raw Data and decoder temporaries are freed
        let entries: [VectorStore.SerializedEntry]? = autoreleasepool {
            guard let data = try? Data(contentsOf: cacheFile),
                  let cache = try? JSONDecoder().decode(RAGCache.self, from: data),
                  cache.version == Self.cacheVersion else { return nil }
            return cache.entries
        }

        guard let entries else { return }

        vectorStore.load(from: entries)

        bm25Index.clear()
        for entry in entries {
            bm25Index.add(chunk: entry.chunk)
        }

        indexedDocumentCount = Set(entries.map(\.chunk.documentId)).count
        totalChunks = entries.count
    }

    // MARK: - Full vault indexing (heavy work runs in background)

    func indexVault(provider: any DocumentProvider, vaultURL: URL? = nil) {
        guard !isIndexing else { return }
        if let vaultURL { self.vaultURL = vaultURL }
        isIndexing = true
        let chunker = self.chunker
        let saveURL = self.vaultURL

        // Clear old indexes now — frees memory before the heavy build starts.
        // Search is unavailable during indexing anyway (isIndexing == true).
        self.vectorStore = VectorStore()
        self.bm25Index = BM25Index()

        Task.detached {
            let docs = (try? await provider.allDocuments()) ?? []
            let newVectorStore = VectorStore()
            let newBM25 = BM25Index()
            var chunkCount = 0

            for (i, doc) in docs.enumerated() {
                guard let content = try? await provider.loadDocument(id: doc.id) else { continue }

                autoreleasepool {
                    let chunks = chunker.chunk(text: content.text, documentId: doc.id, title: doc.title)
                    for chunk in chunks {
                        newVectorStore.add(chunk: chunk)
                        newBM25.add(chunk: chunk)
                        chunkCount += 1
                    }
                }

                if i % 20 == 0 {
                    await Task.yield()
                }
            }

            newVectorStore.unloadEmbedding()

            if let saveURL {
                Self.saveToDisk(vectorStore: newVectorStore, vaultURL: saveURL)
            }

            let docCount = docs.count
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.vectorStore = newVectorStore
                self.bm25Index = newBM25
                self.indexedDocumentCount = docCount
                self.totalChunks = chunkCount
                self.isIndexing = false
            }
        }
    }

    // MARK: - Incremental updates

    func updateDocument(id: String, text: String, title: String) {
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
        totalChunks = bm25Index.count
        saveInBackground()
    }

    // MARK: - Search (runs on MainActor, fast)

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
            .prefix(topK)
            .compactMap { id, score in
                guard let chunk = chunkMap[id] else { return nil }
                return RAGResult(chunk: chunk, score: score)
            }
    }

    /// Build a context block to prepend to the user's prompt for Claude.
    func buildContext(for query: String, topK: Int = 5) -> String {
        let results = search(query: query, topK: topK)
        guard !results.isEmpty else { return "" }

        var ctx = "<context>\nRelevant notes from your vault:\n\n"
        for (i, r) in results.enumerated() {
            ctx += "[\(i + 1)] \(r.chunk.documentTitle)"
            if let h = r.chunk.heading { ctx += " > \(h)" }
            ctx += "\n\(r.chunk.content)\n\n"
        }
        ctx += "</context>"
        return ctx
    }

    // MARK: - Persistence

    nonisolated private static func cacheURL(for vaultURL: URL) -> URL {
        vaultURL
            .appendingPathComponent(".onyx", isDirectory: true)
            .appendingPathComponent("rag", isDirectory: true)
            .appendingPathComponent("index.json")
    }

    nonisolated private static func saveToDisk(vectorStore: VectorStore, vaultURL: URL) {
        let ragDir = vaultURL
            .appendingPathComponent(".onyx", isDirectory: true)
            .appendingPathComponent("rag", isDirectory: true)
        try? FileManager.default.createDirectory(at: ragDir, withIntermediateDirectories: true)

        autoreleasepool {
            let cache = RAGCache(version: cacheVersion, entries: vectorStore.serialize())
            if let data = try? JSONEncoder().encode(cache) {
                try? data.write(to: ragDir.appendingPathComponent("index.json"), options: .atomic)
            }
        }
    }

    private func saveInBackground() {
        guard let vaultURL else { return }
        let serialized = vectorStore.serialize()
        Task.detached {
            autoreleasepool {
                let ragDir = vaultURL
                    .appendingPathComponent(".onyx", isDirectory: true)
                    .appendingPathComponent("rag", isDirectory: true)
                try? FileManager.default.createDirectory(at: ragDir, withIntermediateDirectories: true)

                let cache = RAGCache(version: Self.cacheVersion, entries: serialized)
                if let data = try? JSONEncoder().encode(cache) {
                    try? data.write(to: ragDir.appendingPathComponent("index.json"), options: .atomic)
                }
            }
        }
    }
}
