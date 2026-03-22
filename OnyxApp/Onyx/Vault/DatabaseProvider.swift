import Foundation
import GRDB

final class DatabaseProvider: DocumentProvider, @unchecked Sendable {
    let database: AppDatabase
    private let teamId: String

    init(database: AppDatabase) {
        self.database = database
        let teams = (try? database.teams()) ?? []
        if let team = teams.first {
            self.teamId = team.id
        } else {
            var team = Team(name: "Personal")
            try? database.saveTeam(&team)
            self.teamId = team.id
        }
    }

    func projects() async throws -> [ProjectInfo] {
        try database.allProjects().map { project in
            ProjectInfo(
                id: project.id,
                name: project.name,
                icon: project.icon,
                parentId: project.parentId,
                createdAt: project.createdAt,
                updatedAt: project.updatedAt
            )
        }
    }

    func documents(in projectId: String) async throws -> [DocumentInfo] {
        try database.documents(projectId: projectId).map { doc in
            DocumentInfo(
                id: doc.id,
                projectId: doc.projectId,
                title: doc.title,
                createdAt: doc.createdAt,
                updatedAt: doc.updatedAt
            )
        }
    }

    func allDocuments() async throws -> [DocumentInfo] {
        try database.allDocuments().map { doc in
            DocumentInfo(
                id: doc.id,
                projectId: doc.projectId,
                title: doc.title,
                createdAt: doc.createdAt,
                updatedAt: doc.updatedAt
            )
        }
    }

    func loadDocument(id: String) async throws -> DocumentContent {
        guard let doc = try database.document(id: id) else {
            throw ProviderError.notFound
        }

        // Prefer markdownText if available
        if let markdown = doc.markdownText {
            let metadata = MarkdownSerializer.extractMetadata(from: markdown)
            return DocumentContent(
                text: markdown,
                metadata: metadata
            )
        }

        // Fall back: convert old CRDT snapshot to markdown
        let crdtDoc = CRDTDocument(documentId: id)
        if let snapshot = doc.crdtSnapshot {
            crdtDoc.loadSnapshot(snapshot)
        }
        crdtDoc.ensureFirstBlock()

        let metadata = DocumentMetadata(id: id, created: doc.createdAt, updated: doc.updatedAt)
        let markdown = MarkdownSerializer.serialize(blocks: crdtDoc.orderedBlocks(), metadata: metadata)

        return DocumentContent(
            text: markdown,
            metadata: metadata
        )
    }

    func saveDocument(id: String, content: DocumentContent) async throws {
        try database.updateDocumentMarkdown(id: id, text: content.text)
    }

    func createProject(name: String) async throws -> ProjectInfo {
        try await createProject(name: name, parentId: nil)
    }

    func createProject(name: String, parentId: String?) async throws -> ProjectInfo {
        var project = Project(teamId: teamId, name: name, parentId: parentId)
        try database.saveProject(&project)
        return ProjectInfo(
            id: project.id,
            name: project.name,
            icon: project.icon,
            parentId: project.parentId,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt
        )
    }

    func createDocument(in projectId: String, title: String) async throws -> DocumentInfo {
        var doc = OnyxDocument(projectId: projectId, title: title)
        try database.saveDocument(&doc)
        return DocumentInfo(
            id: doc.id,
            projectId: doc.projectId,
            title: doc.title,
            createdAt: doc.createdAt,
            updatedAt: doc.updatedAt
        )
    }

    func deleteProject(id: String) async throws {
        try database.deleteProject(id: id)
    }

    func deleteDocument(id: String) async throws {
        try database.deleteDocument(id: id)
    }

    func renameProject(id: String, name: String) async throws {
        try database.renameProject(id: id, name: name)
    }

    func observeChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db -> Int in
                let projects = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM project") ?? 0
                let documents = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM document") ?? 0
                return projects + documents
            }

            let cancellable = observation.start(in: database.dbWriter, onError: { _ in }) { _ in
                continuation.yield()
            }

            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
}

enum ProviderError: Error {
    case notFound
    case invalidPath
    case serializationFailed
}
