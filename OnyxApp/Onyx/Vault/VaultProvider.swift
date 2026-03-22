import Foundation

final class VaultProvider: DocumentProvider, @unchecked Sendable {
    let vaultURL: URL
    private let fileWatcher: FileWatcher
    private var changesContinuation: AsyncStream<Void>.Continuation?

    init(vaultURL: URL) {
        self.vaultURL = vaultURL
        self.fileWatcher = FileWatcher(path: vaultURL.path)
        ensureOnyxDirectory()
    }

    deinit {
        fileWatcher.stop()
    }

    private var onyxDir: URL { vaultURL.appendingPathComponent(".onyx", isDirectory: true) }

    private func ensureOnyxDirectory() {
        let fm = FileManager.default
        try? fm.createDirectory(at: onyxDir, withIntermediateDirectories: true)
        // config.json
        let configURL = onyxDir.appendingPathComponent("config.json")
        if !fm.fileExists(atPath: configURL.path) {
            let config = ["version": "1"]
            if let data = try? JSONEncoder().encode(config) {
                try? data.write(to: configURL)
            }
        }
        // cache directory
        try? fm.createDirectory(at: onyxDir.appendingPathComponent("cache", isDirectory: true), withIntermediateDirectories: true)
    }

    // MARK: - Projects (folders)

    func projects() async throws -> [ProjectInfo] {
        var results: [ProjectInfo] = []
        collectProjects(at: vaultURL, parentId: nil, into: &results)
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func collectProjects(at url: URL, parentId: String?, into results: inout [ProjectInfo]) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey]) else { return }

        for itemURL in contents {
            guard let isDir = try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir else { continue }
            let name = itemURL.lastPathComponent
            guard !name.hasPrefix(".") else { continue }

            let relativePath = itemURL.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
            let created = (try? itemURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            let updated = (try? itemURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()

            let info = ProjectInfo(
                id: relativePath,
                name: name,
                icon: "folder",
                parentId: parentId,
                createdAt: created,
                updatedAt: updated
            )
            results.append(info)

            // Recurse into subdirectories
            collectProjects(at: itemURL, parentId: relativePath, into: &results)
        }
    }

    func documents(in projectId: String) async throws -> [DocumentInfo] {
        let projectURL = vaultURL.appendingPathComponent(projectId, isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectURL.path) else { return [] }

        let contents = try fm.contentsOfDirectory(at: projectURL, includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey])

        return contents.compactMap { url in
            guard url.pathExtension == "md" else { return nil }
            let title = url.deletingPathExtension().lastPathComponent
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            let updated = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()

            // Read frontmatter for ID if available
            let docId = readDocumentId(at: url) ?? url.path

            return DocumentInfo(
                id: docId,
                projectId: projectId,
                title: title,
                createdAt: created,
                updatedAt: updated
            )
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func allDocuments() async throws -> [DocumentInfo] {
        let projects = try await projects()
        var all: [DocumentInfo] = []
        // Root-level documents (not inside any subfolder)
        let rootDocs = try await documents(in: "")
        all.append(contentsOf: rootDocs)
        for project in projects {
            let docs = try await documents(in: project.id)
            all.append(contentsOf: docs)
        }
        return all.sorted { $0.updatedAt > $1.updatedAt }
    }

    func loadDocument(id: String) async throws -> DocumentContent {
        let fileURL = resolveDocumentURL(id: id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ProviderError.notFound
        }
        let markdown = try String(contentsOf: fileURL, encoding: .utf8)
        let metadata = MarkdownSerializer.extractMetadata(from: markdown)

        return DocumentContent(
            text: markdown,
            metadata: metadata
        )
    }

    func saveDocument(id: String, content: DocumentContent) async throws {
        let fileURL = resolveDocumentURL(id: id)
        try content.text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func createProject(name: String) async throws -> ProjectInfo {
        try await createProject(name: name, parentId: nil)
    }

    func createProject(name: String, parentId: String?) async throws -> ProjectInfo {
        let baseURL: URL
        if let parentId = parentId {
            baseURL = vaultURL.appendingPathComponent(parentId, isDirectory: true)
        } else {
            baseURL = vaultURL
        }
        let projectURL = baseURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let relativePath = projectURL.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
        return ProjectInfo(
            id: relativePath,
            name: name,
            icon: "folder",
            parentId: parentId,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func createDocument(in projectId: String, title: String) async throws -> DocumentInfo {
        let projectURL = vaultURL.appendingPathComponent(projectId, isDirectory: true)
        try? FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let docId = UUID().uuidString.lowercased()
        let fileName = sanitizeFilename(title.isEmpty ? "Untitled" : title) + ".md"
        let fileURL = projectURL.appendingPathComponent(fileName)

        let metadata = DocumentMetadata(id: docId)
        let markdown = MarkdownSerializer.generateFrontmatter(metadata: metadata) + "\n"
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)

        // Store ID → path mapping in cache
        saveDocumentMapping(id: docId, path: fileURL.path)

        return DocumentInfo(
            id: docId,
            projectId: projectId,
            title: title.isEmpty ? "Untitled" : title,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func deleteProject(id: String) async throws {
        let projectURL = vaultURL.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.removeItem(at: projectURL)
    }

    func deleteDocument(id: String) async throws {
        let fileURL = resolveDocumentURL(id: id)
        try FileManager.default.removeItem(at: fileURL)
    }

    func renameProject(id: String, name: String) async throws {
        let oldURL = vaultURL.appendingPathComponent(id, isDirectory: true)
        let newURL = vaultURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.moveItem(at: oldURL, to: newURL)
    }

    func observeChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            self.changesContinuation = continuation
            self.fileWatcher.start { [weak self] in
                self?.changesContinuation?.yield()
            }
            continuation.onTermination = { @Sendable [weak self] _ in
                DispatchQueue.main.async {
                    self?.fileWatcher.stop()
                    self?.changesContinuation = nil
                }
            }
        }
    }

    // MARK: - Private helpers

    func projectFolderURL(projectId: String) -> URL {
        vaultURL.appendingPathComponent(projectId, isDirectory: true)
    }

    func resolveDocumentURL(id: String) -> URL {
        // Check mapping cache first
        if let path = loadDocumentMapping(id: id) {
            return URL(fileURLWithPath: path)
        }
        // Fallback: ID might be a file path
        if id.hasPrefix("/") {
            return URL(fileURLWithPath: id)
        }
        // Search vault for document with matching frontmatter ID
        if let url = findDocumentByFrontmatterId(id) {
            saveDocumentMapping(id: id, path: url.path)
            return url
        }
        // Last resort
        return vaultURL.appendingPathComponent(id)
    }

    private func readDocumentId(at url: URL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: "\n")
        guard lines.first == "---" else { return nil }
        for line in lines.dropFirst() {
            if line == "---" { break }
            if line.hasPrefix("id:") {
                return line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func findDocumentByFrontmatterId(_ id: String) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: vaultURL, includingPropertiesForKeys: nil) else { return nil }
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }
            if readDocumentId(at: url) == id {
                return url
            }
        }
        return nil
    }

    private var mappingURL: URL {
        onyxDir.appendingPathComponent("doc_mapping.json")
    }

    private func loadAllMappings() -> [String: String] {
        guard let data = try? Data(contentsOf: mappingURL),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return map
    }

    private func saveDocumentMapping(id: String, path: String) {
        var map = loadAllMappings()
        map[id] = path
        if let data = try? JSONEncoder().encode(map) {
            try? data.write(to: mappingURL, options: .atomic)
        }
    }

    private func loadDocumentMapping(id: String) -> String? {
        let map = loadAllMappings()
        guard let path = map[id], FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    private func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: invalid).joined(separator: "-")
    }
}
