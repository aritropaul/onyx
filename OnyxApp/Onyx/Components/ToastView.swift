import SwiftUI

struct ToastView: View {
    let message: String
    let icon: String?

    init(_ message: String, icon: String? = nil) {
        self.message = message
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: OnyxTheme.Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(OnyxTheme.Colors.textSecondary)
            }

            Text(message)
                .font(OnyxTheme.Typography.caption)
                .foregroundStyle(OnyxTheme.Colors.textPrimary)
        }
        .padding(.horizontal, OnyxTheme.Spacing.lg)
        .padding(.vertical, OnyxTheme.Spacing.sm)
        .background(.ultraThinMaterial)
        .background(OnyxTheme.Colors.surface.opacity(0.9))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    }
}
