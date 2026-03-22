import SwiftUI

struct OnyxSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: OnyxTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(OnyxTheme.Colors.textTertiary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(OnyxTheme.Typography.body)
                .foregroundStyle(OnyxTheme.Colors.textPrimary)
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(OnyxTheme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, OnyxTheme.Spacing.md)
        .padding(.vertical, OnyxTheme.Spacing.sm)
        .background(OnyxTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: OnyxTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: OnyxTheme.Radius.md)
                .stroke(
                    isFocused ? OnyxTheme.Colors.accent : OnyxTheme.Colors.border,
                    lineWidth: 1
                )
        )
    }
}
