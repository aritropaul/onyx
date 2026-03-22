import Foundation

enum TabKind: String, Codable, Equatable {
    case document
    case ai
    case settings
}

struct TabItem: Identifiable, Equatable, Codable {
    let id: String
    var title: String
    var projectId: String
    var kind: TabKind

    init(id: String, title: String, projectId: String, kind: TabKind = .document) {
        self.id = id
        self.title = title
        self.projectId = projectId
        self.kind = kind
    }
}
