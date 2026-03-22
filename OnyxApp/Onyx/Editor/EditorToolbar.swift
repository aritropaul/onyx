import SwiftUI

extension Notification.Name {
    static let onyxToggleInlineStyle = Notification.Name("onyxToggleInlineStyle")
}

struct EditorToolbar: View {

    var body: some View {
        HStack(spacing: 2) {
            formatButton(label: "B", style: "bold", weight: .bold, help: "Bold (Cmd+B)")
            formatButton(label: "I", style: "italic", italic: true, help: "Italic (Cmd+I)")
            formatButton(label: "<>", style: "code", monospaced: true, help: "Code (Cmd+E)")
            formatButton(label: "S", style: "strikethrough", strikethrough: true, help: "Strikethrough (Cmd+Shift+S)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func formatButton(
        label: String,
        style: String,
        weight: Font.Weight = .regular,
        italic: Bool = false,
        monospaced: Bool = false,
        strikethrough: Bool = false,
        help: String
    ) -> some View {
        Button {
            NotificationCenter.default.post(
                name: .onyxToggleInlineStyle,
                object: nil,
                userInfo: ["style": style]
            )
        } label: {
            Text(label)
                .font(.system(size: 13, weight: weight, design: monospaced ? .monospaced : .default))
                .italic(italic)
                .strikethrough(strikethrough)
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
