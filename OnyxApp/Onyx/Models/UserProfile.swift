import Foundation

struct UserProfile: Codable, Equatable {
    var id: String
    var displayName: String
    var email: String?
    var avatarURL: String?
}
