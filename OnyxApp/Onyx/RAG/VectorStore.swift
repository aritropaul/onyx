import Foundation
import NaturalLanguage

final class VectorStore: @unchecked Sendable {
    private var entries: [(vector: [Float], chunk: TextChunk)] = []
    private var _embedding: NLEmbedding?
    private var _embeddingLoaded = false

    private var embedding: NLEmbedding? {
        if !_embeddingLoaded {
            _embedding = NLEmbedding.sentenceEmbedding(for: .english)
            _embeddingLoaded = true
        }
        return _embedding
    }

    var isAvailable: Bool { embedding != nil }

    /// Release the embedding model from memory. It will be lazy-loaded again on next use.
    func unloadEmbedding() {
        _embedding = nil
        _embeddingLoaded = false
    }

    // MARK: - Embedding

    func embed(_ text: String) -> [Float]? {
        guard let embedding else { return nil }
        // NLEmbedding.vector(for:) creates autoreleased ObjC objects internally.
        // Without a pool, these accumulate in Task.detached loops — the main cause of 32GB bloat.
        return autoreleasepool {
            guard let vector = embedding.vector(for: text) else { return nil }
            return normalize(vector.map { Float($0) })
        }
    }

    // MARK: - Index operations

    func add(chunk: TextChunk) {
        guard let vector = embed(chunk.content) else { return }
        entries.append((vector: vector, chunk: chunk))
    }

    /// Add a pre-embedded entry (from cache) without re-computing the vector.
    func addSerialized(_ entry: SerializedEntry) {
        entries.append((vector: entry.vector, chunk: entry.chunk))
    }

    func search(query: String, topK: Int) -> [(chunk: TextChunk, score: Float)] {
        guard let queryVector = embed(query), !entries.isEmpty else { return [] }

        return entries
            .map { (chunk: $0.chunk, score: dotProduct($0.vector, queryVector)) }
            .sorted { $0.score > $1.score }
            .prefix(topK)
            .map { $0 }
    }

    func remove(documentId: String) {
        entries.removeAll { $0.chunk.documentId == documentId }
    }

    func clear() {
        entries.removeAll()
    }

    var count: Int { entries.count }

    // MARK: - Serialization

    struct SerializedEntry: Codable {
        let vector: [Float]
        let chunk: TextChunk
    }

    func serialize() -> [SerializedEntry] {
        entries.map { SerializedEntry(vector: $0.vector, chunk: $0.chunk) }
    }

    func load(from serialized: [SerializedEntry]) {
        entries = serialized.map { (vector: $0.vector, chunk: $0.chunk) }
    }

    // MARK: - Vector math

    private func normalize(_ v: [Float]) -> [Float] {
        let magnitude = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard magnitude > 0 else { return v }
        return v.map { $0 / magnitude }
    }

    private func dotProduct(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    }
}
