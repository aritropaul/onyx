import Foundation
import GRDB

struct Project: Identifiable, Equatable, Hashable {
    var id: String
    var teamId: String
    var name: String
    var icon: String
    var parentId: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString.lowercased(),
        teamId: String,
        name: String,
        icon: String = "folder",
        parentId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.teamId = teamId
        self.name = name
        self.icon = icon
        self.parentId = parentId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB

extension Project: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "project"

    enum Columns: String, ColumnExpression {
        case id, teamId, name, icon, parentId, createdAt, updatedAt
    }

    static let documents = hasMany(OnyxDocument.self, using: ForeignKey(["projectId"]))

    var documents: QueryInterfaceRequest<OnyxDocument> {
        request(for: Project.documents)
    }
}
