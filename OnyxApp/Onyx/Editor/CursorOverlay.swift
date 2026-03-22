import SwiftUI
import AppKit

struct CursorOverlay: View {
    let presences: [UInt64: UserPresence]

    var body: some View {
        // Remote cursors are now drawn by the MarkdownNSTextView's layout manager.
        // This view serves as a placeholder for potential future overlay UI (e.g., presence avatars).
        EmptyView()
    }
}
