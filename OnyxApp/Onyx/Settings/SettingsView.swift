import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case editor = "Editor"
    case sync = "Sync"
    case ai = "AI"
    case account = "Account"

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .editor: "doc.text"
        case .sync: "arrow.triangle.2.circlepath"
        case .ai: "sparkles"
        case .account: "person.circle"
        }
    }

    var category: String {
        switch self {
        case .general, .editor: "App"
        case .sync, .ai: "Services"
        case .account: "Account"
        }
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: SettingsTab = .general
    @State private var settings = AppSettings.shared

    private var groupedTabs: [(String, [SettingsTab])] {
        var result: [(String, [SettingsTab])] = []
        var currentCategory = ""
        for tab in SettingsTab.allCases {
            if tab.category != currentCategory {
                currentCategory = tab.category
                result.append((currentCategory, [tab]))
            } else {
                result[result.count - 1].1.append(tab)
            }
        }
        return result
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OnyxTheme.Colors.textPrimary)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(groupedTabs, id: \.0) { category, tabs in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(OnyxTheme.Colors.textTertiary.opacity(0.6))
                                .tracking(0.8)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 4)

                            ForEach(tabs, id: \.self) { tab in
                                sidebarItem(tab)
                            }
                        }
                    }
                }
                .padding(.bottom, 16)
            }

            Spacer()

            Text("Onyx v0.1.0")
                .font(.system(size: 10))
                .foregroundStyle(OnyxTheme.Colors.textTertiary.opacity(0.5))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(width: 170)
    }

    private func sidebarItem(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(OnyxTheme.Animation.quick) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? OnyxTheme.Colors.accent : OnyxTheme.Colors.textTertiary)
                    .frame(width: 16)
                Text(tab.rawValue)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? OnyxTheme.Colors.textPrimary : OnyxTheme.Colors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: OnyxTheme.Radius.md)
                    .fill(isSelected ? Color.white.opacity(0.08) : .clear)
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch selectedTab {
                case .general:
                    GeneralSettings(settings: settings, appState: appState)
                case .editor:
                    EditorSettings(settings: settings)
                case .sync:
                    SyncSettings(settings: settings)
                case .ai:
                    AISettings(settings: settings, appState: appState)
                case .account:
                    AccountSettings(appState: appState)
                }
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(OnyxTheme.Colors.textTertiary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OnyxTheme.Colors.textSecondary)
            VStack { Divider().opacity(0.2) }
        }
        .padding(.bottom, 12)
    }
}

// MARK: - Card

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Row

private struct SettingsRow<Content: View>: View {
    let label: String
    let description: String?
    @ViewBuilder let content: Content

    init(_ label: String, description: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.description = description
        self.content = content()
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(OnyxTheme.Colors.textPrimary)
                if let desc = description {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundStyle(OnyxTheme.Colors.textTertiary)
                }
            }
            Spacer()
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct CardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 14)
    }
}

private struct SectionFooter: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(OnyxTheme.Colors.textTertiary.opacity(0.7))
            .padding(.top, 6)
            .padding(.horizontal, 2)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Bindable var settings: AppSettings
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(icon: "folder", title: "Vault")

            Card {
                SettingsRow("Location", description: appState.vaultURL != nil ? nil : "No vault open") {
                    if let url = appState.vaultURL {
                        HStack(spacing: 6) {
                            Text(url.lastPathComponent)
                                .font(.system(size: 12))
                                .foregroundStyle(OnyxTheme.Colors.textSecondary)
                            Button {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                            } label: {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 10))
                                    .foregroundStyle(OnyxTheme.Colors.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                CardDivider()
                SettingsRow("Sidebar width") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.sidebarWidth, in: 180...320, step: 4)
                            .frame(width: 120)
                        Text("\(Int(settings.sidebarWidth))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(OnyxTheme.Colors.textTertiary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
        }
    }
}

// MARK: - Editor

private struct EditorSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(icon: "textformat.size", title: "Typography")

            Card {
                SettingsRow("Font size") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.editorFontSize, in: 12...22, step: 1)
                            .frame(width: 120)
                        Text("\(Int(settings.editorFontSize))px")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(OnyxTheme.Colors.textTertiary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                CardDivider()
                SettingsRow("Line height") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.editorLineHeight, in: 1.2...2.0, step: 0.1)
                            .frame(width: 120)
                        Text(String(format: "%.1fx", settings.editorLineHeight))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(OnyxTheme.Colors.textTertiary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }

            SectionHeader(icon: "rectangle.expand.horizontal", title: "Layout")

            Card {
                SettingsRow("Content width") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.editorMaxWidth, in: 600...1200, step: 50)
                            .frame(width: 120)
                        Text("\(Int(settings.editorMaxWidth))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(OnyxTheme.Colors.textTertiary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                CardDivider()
                SettingsRow("Auto-save delay") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.autoSaveDelay, in: 100...2000, step: 100)
                            .frame(width: 120)
                        Text("\(Int(settings.autoSaveDelay))ms")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(OnyxTheme.Colors.textTertiary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
    }
}

// MARK: - Sync

private struct SyncSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(icon: "arrow.triangle.2.circlepath", title: "Sync Server")

            Card {
                SettingsRow("Enabled", description: "Connect to a remote sync server") {
                    Toggle("", isOn: $settings.syncEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                CardDivider()
                SettingsRow("Host") {
                    TextField("localhost", text: $settings.syncHost)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 160)
                        .disabled(!settings.syncEnabled)
                        .opacity(settings.syncEnabled ? 1 : 0.5)
                }
                CardDivider()
                SettingsRow("Port") {
                    TextField("3001", value: $settings.syncPort, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 70)
                        .disabled(!settings.syncEnabled)
                        .opacity(settings.syncEnabled ? 1 : 0.5)
                }
            }

            SectionFooter(text: "Sync enables real-time collaboration through a WebSocket server.")
        }
    }
}

// MARK: - AI

private struct AISettings: View {
    @Bindable var settings: AppSettings
    let appState: AppState
    @State private var customPrompt: String = ""
    @State private var promptSaved: Bool = false

    private var promptFileURL: URL? {
        appState.vaultURL?.appendingPathComponent(".onyx/ai/prompt.md")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(icon: "sparkles", title: "Claude")

            Card {
                SettingsRow("CLI path", description: cliDescription) {
                    TextField("Auto-detect", text: $settings.claudePath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 200)
                }
                CardDivider()
                SettingsRow("Model") {
                    Picker("", selection: $settings.claudeModel) {
                        Text("Haiku").tag("haiku")
                        Text("Sonnet").tag("sonnet")
                        Text("Opus").tag("opus")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }

            SectionFooter(text: "Claude runs locally via the CLI. Keys are managed by the Claude app.")

            if appState.vaultURL != nil {
                SectionHeader(icon: "text.quote", title: "System Prompt")

                Card {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Custom instructions for this vault's AI assistant")
                            .font(.system(size: 11))
                            .foregroundStyle(OnyxTheme.Colors.textTertiary)
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                            .padding(.bottom, 8)

                        TextEditor(text: $customPrompt)
                            .font(.system(size: 12, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .frame(height: 100)
                            .padding(.horizontal, 10)

                        HStack {
                            Spacer()
                            if promptSaved {
                                Text("Saved")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(OnyxTheme.Colors.accent)
                                    .transition(.opacity)
                            }
                            Button("Save") { savePrompt() }
                                .font(.system(size: 12))
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                        .padding(.top, 4)
                    }
                }

                SectionFooter(text: "Saved to .onyx/ai/prompt.md in your vault root.")
            }
        }
        .onAppear { loadPrompt() }
    }

    private var cliDescription: String? {
        if !settings.claudePath.isEmpty { return nil }
        let resolved = settings.resolvedClaudePath
        return resolved.isEmpty ? "Not found" : "Detected"
    }

    private func loadPrompt() {
        guard let url = promptFileURL else { return }
        customPrompt = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func savePrompt() {
        guard let url = promptFileURL else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? customPrompt.write(to: url, atomically: true, encoding: .utf8)
        withAnimation { promptSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { promptSaved = false }
        }
    }
}

// MARK: - Account

private struct AccountSettings: View {
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(icon: "person.circle", title: "Profile")

            Card {
                SettingsRow("Display Name") {
                    Text(appState.profileManager.profile.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(OnyxTheme.Colors.textSecondary)
                }
                CardDivider()
                SettingsRow("User ID") {
                    Text(appState.profileManager.profile.id)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(OnyxTheme.Colors.textTertiary)
                        .textSelection(.enabled)
                }
            }

            if let email = appState.profileManager.profile.email,
               appState.profileManager.isAuthenticated {
                SectionHeader(icon: "key", title: "Authentication")

                Card {
                    SettingsRow("Email") {
                        Text(email)
                            .font(.system(size: 12))
                            .foregroundStyle(OnyxTheme.Colors.textSecondary)
                    }
                    CardDivider()
                    SettingsRow("Session") {
                        Button("Logout", role: .destructive) {
                            appState.profileManager.logout()
                        }
                        .font(.system(size: 12))
                        .controlSize(.small)
                    }
                }
            }
        }
    }
}
