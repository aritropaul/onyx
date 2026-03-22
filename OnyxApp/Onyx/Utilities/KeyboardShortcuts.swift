import SwiftUI

// Keyboard shortcut utilities for the app
extension View {
    func onCommandK(perform action: @escaping () -> Void) -> some View {
        self.onKeyPress(characters: CharacterSet(charactersIn: "k"), phases: .down) { _ in
            action()
            return .handled
        }
    }
}
