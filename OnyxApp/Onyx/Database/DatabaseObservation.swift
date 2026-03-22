import Foundation
import GRDB
import GRDBQuery

// MARK: - All Documents Request

struct AllDocumentsRequest: ValueObservationQueryable {
    typealias Context = AppDatabase
    static var defaultValue: [OnyxDocument] { [] }

    func fetch(_ db: Database) throws -> [OnyxDocument] {
        try OnyxDocument.order(OnyxDocument.Columns.updatedAt.desc).fetchAll(db)
    }
}

// MARK: - Documents for Project

struct ProjectDocumentsRequest: ValueObservationQueryable {
    typealias Context = AppDatabase
    var projectId: String

    static var defaultValue: [OnyxDocument] { [] }

    func fetch(_ db: Database) throws -> [OnyxDocument] {
        try OnyxDocument
            .filter(OnyxDocument.Columns.projectId == projectId)
            .order(OnyxDocument.Columns.updatedAt.desc)
            .fetchAll(db)
    }
}

// MARK: - All Projects Request

struct AllProjectsRequest: ValueObservationQueryable {
    typealias Context = AppDatabase
    static var defaultValue: [Project] { [] }

    func fetch(_ db: Database) throws -> [Project] {
        try Project.order(Project.Columns.name).fetchAll(db)
    }
}

// MARK: - Projects for Team

struct TeamProjectsRequest: ValueObservationQueryable {
    typealias Context = AppDatabase
    var teamId: String

    static var defaultValue: [Project] { [] }

    func fetch(_ db: Database) throws -> [Project] {
        try Project
            .filter(Project.Columns.teamId == teamId)
            .order(Project.Columns.name)
            .fetchAll(db)
    }
}

// MARK: - All Teams Request

struct AllTeamsRequest: ValueObservationQueryable {
    typealias Context = AppDatabase
    static var defaultValue: [Team] { [] }

    func fetch(_ db: Database) throws -> [Team] {
        try Team.order(Team.Columns.name).fetchAll(db)
    }
}
