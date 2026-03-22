import Foundation
import SwiftUI

struct UserPresence: Identifiable, Equatable {
    let id: UInt64
    var userName: String
    var color: Color
    var cursorOffset: Int?
    var lastSeen: Date

    var isStale: Bool {
        Date().timeIntervalSince(lastSeen) > 30
    }
}
