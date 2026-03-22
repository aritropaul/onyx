import SwiftUI

struct NewTabView: View {
    @Environment(AppState.self) private var appState
    let tabId: String

    var body: some View {
        VStack(spacing: 20) {
            Text("New Tab")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(OnyxTheme.Colors.textSecondary)

            HStack(spacing: 16) {
                newTabOption(
                    icon: "doc.text",
                    title: "Document",
                    subtitle: "Open or create a file"
                ) {
                    // Close this tab and open a document
                    if let projectId = appState.selectedProjectId ?? appState.projects.first?.id {
                        appState.closeTab(id: tabId)
                        appState.createDocument(projectId: projectId)
                    }
                }

                newTabOption(
                    icon: "sparkles",
                    title: "Claude",
                    subtitle: "AI assistant"
                ) {
                    // Replace this tab with an AI tab
                    appState.closeTab(id: tabId)
                    appState.openAITab()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func newTabOption(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(OnyxTheme.Colors.textTertiary)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(OnyxTheme.Colors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(OnyxTheme.Colors.textTertiary)
            }
            .frame(width: 140, height: 120)
            .background(
                RoundedRectangle(cornerRadius: OnyxTheme.Radius.lg)
                    .fill(OnyxTheme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OnyxTheme.Radius.lg)
                    .stroke(OnyxTheme.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
