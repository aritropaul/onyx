import Foundation

struct ProjectInfo: Identifiable, Equatable {
    var id: String
    var name: String
    var icon: String
    var parentId: String?
    var createdAt: Date
    var updatedAt: Date
}

struct DocumentInfo: Identifiable, Equatable {
    var id: String
    var projectId: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
}

struct DocumentContent {
    var text: String
    var metadata: DocumentMetadata
}

struct DocumentMetadata: Codable, Equatable {
    var id: String
    var created: Date
    var updated: Date
    var tags: [String]
    var customProperties: [String: String]

    init(id: String = UUID().uuidString.lowercased(), created: Date = Date(), updated: Date = Date(), tags: [String] = [], customProperties: [String: String] = [:]) {
        self.id = id
        self.created = created
        self.updated = updated
        self.tags = tags
        self.customProperties = customProperties
    }
}

protocol DocumentProvider: Sendable {
    func projects() async throws -> [ProjectInfo]
    func documents(in projectId: String) async throws -> [DocumentInfo]
    func allDocuments() async throws -> [DocumentInfo]
    func loadDocument(id: String) async throws -> DocumentContent
    func saveDocument(id: String, content: DocumentContent) async throws
    func createProject(name: String) async throws -> ProjectInfo
    func createProject(name: String, parentId: String?) async throws -> ProjectInfo
    func createDocument(in projectId: String, title: String) async throws -> DocumentInfo
    func deleteProject(id: String) async throws
    func deleteDocument(id: String) async throws
    func renameProject(id: String, name: String) async throws

    func observeChanges() -> AsyncStream<Void>
}

extension DocumentProvider {
    func createProject(name: String) async throws -> ProjectInfo {
        try await createProject(name: name, parentId: nil)
    }
}
