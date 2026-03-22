import SwiftUI

struct DocumentStatsBar: View {
    let wordCount: Int
    let charCount: Int
    let isSynced: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text("\(wordCount) words")
                .monospacedDigit()
            Text("  \u{00B7}  ")
                .foregroundStyle(.quaternary)
            Text("\(charCount) characters")
                .monospacedDigit()

            Spacer()

            Circle()
                .fill(isSynced ? .green.opacity(0.8) : OnyxTheme.Colors.textTertiary.opacity(0.4))
                .frame(width: 5, height: 5)
        }
        .font(OnyxTheme.Typography.caption)
        .foregroundStyle(OnyxTheme.Colors.textTertiary)
        .padding(.horizontal, 16)
        .frame(height: 24)
        .background(OnyxTheme.Colors.background)
    }
}
