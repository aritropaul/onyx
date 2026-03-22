import Foundation
import GRDB

struct OnyxDocument: Identifiable, Equatable, Hashable {
    var id: String
    var projectId: String
    var title: String
    var crdtSnapshot: Data?
    var markdownText: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString.lowercased(),
        projectId: String,
        title: String = "Untitled",
        crdtSnapshot: Data? = nil,
        markdownText: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.crdtSnapshot = crdtSnapshot
        self.markdownText = markdownText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB

extension OnyxDocument: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "document"

    enum Columns: String, ColumnExpression {
        case id, projectId, title, crdtSnapshot, markdownText, createdAt, updatedAt
    }
}
