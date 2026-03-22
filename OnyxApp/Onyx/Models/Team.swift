import Foundation
import GRDB

struct Team: Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var createdAt: Date

    init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

// MARK: - GRDB

extension Team: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "team"

    enum Columns: String, ColumnExpression {
        case id, name, createdAt
    }

    static let projects = hasMany(Project.self, using: ForeignKey(["teamId"]))

    var projects: QueryInterfaceRequest<Project> {
        request(for: Team.projects)
    }
}
