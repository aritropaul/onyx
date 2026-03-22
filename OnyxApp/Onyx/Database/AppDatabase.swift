import Foundation
import GRDB

final class AppDatabase: Sendable {
    let dbWriter: any DatabaseWriter

    init(_ dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try migrator.migrate(dbWriter)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1") { db in
            try db.create(table: "team") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "project") { t in
                t.primaryKey("id", .text)
                t.column("teamId", .text).notNull()
                    .references("team", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("icon", .text).notNull().defaults(to: "folder")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "document") { t in
                t.primaryKey("id", .text)
                t.column("projectId", .text).notNull()
                    .references("project", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("crdtSnapshot", .blob)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v2") { db in
            try db.alter(table: "project") { t in
                t.add(column: "parentId", .text)
                    .references("project", onDelete: .cascade)
            }
        }

        migrator.registerMigration("v3") { db in
            try db.alter(table: "document") { t in
                t.add(column: "markdownText", .text)
            }
        }

        return migrator
    }
}

// MARK: - Shared Access

extension AppDatabase {
    static let shared = makeShared()

    private static func makeShared() -> AppDatabase {
        do {
            let fileManager = FileManager.default
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = appSupport.appendingPathComponent("Onyx", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let dbURL = directory.appendingPathComponent("onyx.sqlite")
            let dbPool = try DatabasePool(path: dbURL.path)
            return try AppDatabase(dbPool)
        } catch {
            fatalError("Database setup failed: \(error)")
        }
    }

    static func empty() throws -> AppDatabase {
        let dbQueue = try DatabaseQueue()
        return try AppDatabase(dbQueue)
    }
}

// MARK: - Writes

extension AppDatabase {
    func saveTeam(_ team: inout Team) throws {
        try dbWriter.write { db in
            try team.save(db)
        }
    }

    func deleteTeam(id: String) throws {
        try dbWriter.write { db in
            _ = try Team.deleteOne(db, id: id)
        }
    }

    func saveProject(_ project: inout Project) throws {
        try dbWriter.write { db in
            try project.save(db)
        }
    }

    func deleteProject(id: String) throws {
        try dbWriter.write { db in
            _ = try Project.deleteOne(db, id: id)
        }
    }

    func saveDocument(_ document: inout OnyxDocument) throws {
        try dbWriter.write { db in
            try document.save(db)
        }
    }

    func deleteDocument(id: String) throws {
        try dbWriter.write { db in
            _ = try OnyxDocument.deleteOne(db, id: id)
        }
    }

    func renameProject(id: String, name: String) throws {
        try dbWriter.write { db in
            try db.execute(
                sql: "UPDATE project SET name = ?, updatedAt = ? WHERE id = ?",
                arguments: [name, Date(), id]
            )
        }
    }

    func updateDocumentSnapshot(id: String, snapshot: Data) throws {
        try dbWriter.write { db in
            try db.execute(
                sql: "UPDATE document SET crdtSnapshot = ?, updatedAt = ? WHERE id = ?",
                arguments: [snapshot, Date(), id]
            )
        }
    }

    func updateDocumentMarkdown(id: String, text: String) throws {
        try dbWriter.write { db in
            try db.execute(
                sql: "UPDATE document SET markdownText = ?, updatedAt = ? WHERE id = ?",
                arguments: [text, Date(), id]
            )
        }
    }
}

// MARK: - Reads

extension AppDatabase {
    func teams() throws -> [Team] {
        try dbWriter.read { db in
            try Team.order(Team.Columns.name).fetchAll(db)
        }
    }

    func projects(teamId: String) throws -> [Project] {
        try dbWriter.read { db in
            try Project
                .filter(Project.Columns.teamId == teamId)
                .order(Project.Columns.name)
                .fetchAll(db)
        }
    }

    func documents(projectId: String) throws -> [OnyxDocument] {
        try dbWriter.read { db in
            try OnyxDocument
                .filter(OnyxDocument.Columns.projectId == projectId)
                .order(OnyxDocument.Columns.updatedAt.desc)
                .fetchAll(db)
        }
    }

    func document(id: String) throws -> OnyxDocument? {
        try dbWriter.read { db in
            try OnyxDocument.fetchOne(db, id: id)
        }
    }

    func allProjects() throws -> [Project] {
        try dbWriter.read { db in
            try Project.order(Project.Columns.name).fetchAll(db)
        }
    }

    func allDocuments() throws -> [OnyxDocument] {
        try dbWriter.read { db in
            try OnyxDocument.order(OnyxDocument.Columns.updatedAt.desc).fetchAll(db)
        }
    }
}
