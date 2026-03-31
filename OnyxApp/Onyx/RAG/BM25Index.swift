import Foundation

final class BM25Index: @unchecked Sendable {
    private var chunks: [TextChunk] = []
    private var invertedIndex: [String: [(chunkIdx: Int, tf: Int)]] = [:]
    private var docLengths: [Int] = []
    private var avgDocLength: Double = 0

    private let k1: Double = 1.2
    private let b: Double = 0.75

    // MARK: - Indexing

    func add(chunk: TextChunk) {
        let idx = chunks.count
        chunks.append(chunk)

        let terms = tokenize(chunk.content)
        docLengths.append(terms.count)
        avgDocLength = Double(docLengths.reduce(0, +)) / Double(docLengths.count)

        var termFreq: [String: Int] = [:]
        for term in terms {
            termFreq[term, default: 0] += 1
        }

        for (term, tf) in termFreq {
            invertedIndex[term, default: []].append((chunkIdx: idx, tf: tf))
        }
    }

    // MARK: - Search

    func search(query: String, topK: Int) -> [(chunk: TextChunk, score: Double)] {
        let queryTerms = tokenize(query)
        guard !queryTerms.isEmpty, !chunks.isEmpty else { return [] }

        let n = Double(chunks.count)
        var scores = [Double](repeating: 0, count: chunks.count)

        for term in Set(queryTerms) {
            guard let postings = invertedIndex[term] else { continue }
            let df = Double(postings.count)
            let idf = log((n - df + 0.5) / (df + 0.5) + 1.0)

            for posting in postings {
                let tf = Double(posting.tf)
                let dl = Double(docLengths[posting.chunkIdx])
                let tfNorm = (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * dl / avgDocLength))
                scores[posting.chunkIdx] += idf * tfNorm
            }
        }

        return scores.enumerated()
            .filter { $0.element > 0 }
            .sorted { $0.element > $1.element }
            .prefix(topK)
            .map { (chunk: chunks[$0.offset], score: $0.element) }
    }

    // MARK: - Mutation

    func remove(documentId: String) {
        let remaining = chunks.filter { $0.documentId != documentId }
        rebuild(from: remaining)
    }

    func clear() {
        chunks.removeAll()
        invertedIndex.removeAll()
        docLengths.removeAll()
        avgDocLength = 0
    }

    var count: Int { chunks.count }

    // MARK: - Private

    private func rebuild(from newChunks: [TextChunk]) {
        clear()
        for chunk in newChunks {
            add(chunk: chunk)
        }
    }

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
    }
}
