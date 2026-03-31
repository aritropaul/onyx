import SwiftUI
import AppKit

// MARK: - Window transparency for glass effect

private class TransparentWindowView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = self.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}

private struct TransparentWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { TransparentWindowView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Content View

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        Group {
            if !appState.isVaultConfigured {
                VaultPickerView { url in
                    appState.configureVault(url: url)
                }
            } else {
                HStack(spacing: 0) {
                    // Solid dark sidebar
                    SidebarView()
                        .frame(width: 228)

                    // Editor/content area
                    VStack(spacing: 0) {
                        // Tab bar sits above the glass container
                        if !appState.openTabs.isEmpty {
                            TabBarView()
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                        }

                        // Glass editor container
                        VStack(spacing: 0) {
                            if !appState.openTabs.isEmpty {
                                breadcrumbBar
                            }
                            if let tab = appState.activeTab {
                                if tab.id.hasPrefix("new-") {
                                    NewTabView(tabId: tab.id)
                                        .id(tab.id)
                                } else {
                                    switch tab.kind {
                                    case .document:
                                        EditorView(documentId: tab.id)
                                            .id(tab.id)
                                    case .ai:
                                        AIAssistantView(tabId: tab.id)
                                            .id(tab.id)
                                    case .settings:
                                        SettingsView()
                                            .id(tab.id)
                                    }
                                }
                            } else {
                                NewTabView(tabId: "empty")
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                        .padding(16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(nil, value: appState.activeTabId)
                }
                .background(Color(white: 0.08))
                .background(TransparentWindow())
                .ignoresSafeArea()
            }
        }
        .overlay {
            if appState.isCommandPaletteVisible {
                CommandPaletteView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .animation(OnyxTheme.Animation.standard, value: appState.isCommandPaletteVisible)
        .overlay {
            if appState.isSearchVisible {
                SearchOverlayView(
                    isVisible: $appState.isSearchVisible,
                    mode: appState.searchMode
                )
            }
        }
        // Keyboard shortcuts
        .onKeyPress(characters: CharacterSet(charactersIn: "p"), phases: .down) { press in
            if press.modifiers == .command {
                appState.searchMode = .files
                appState.isSearchVisible = true
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "f"), phases: .down) { press in
            if press.modifiers == [.command, .shift] {
                appState.searchMode = .content
                appState.isSearchVisible = true
                return .handled
            }
            return .ignored
        }
        .task {
            if appState.isVaultConfigured {
                appState.ensureDefaultTeam()
                await appState.loadSidebarData()
                appState.startObservingChanges()
            }
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumbBar: some View {
        HStack {
            Spacer()
            HStack(spacing: 6) {
                if let tab = appState.activeTab {
                    switch tab.kind {
                    case .document:
                        if let docInfo = appState.documents.first(where: { $0.id == tab.id }) {
                            let ancestorPath = appState.ancestors(of: docInfo.projectId)
                            ForEach(Array(ancestorPath.enumerated()), id: \.element.id) { index, ancestor in
                                if index > 0 {
                                    Text("/")
                                        .foregroundStyle(OnyxTheme.Colors.textTertiary.opacity(0.5))
                                }
                                Text(ancestor.name)
                                    .foregroundStyle(OnyxTheme.Colors.textTertiary)
                                    .onTapGesture {
                                        appState.selectedProjectId = ancestor.id
                                    }
                            }
                            Text("/")
                                .foregroundStyle(OnyxTheme.Colors.textTertiary.opacity(0.5))
                            Text(docInfo.title.isEmpty ? "Untitled" : docInfo.title)
                                .foregroundStyle(OnyxTheme.Colors.textTertiary)
                        }
                    case .ai:
                        Image(systemName: "sparkles")
                            .foregroundStyle(OnyxTheme.Colors.accent)
                        Text("Claude")
                            .foregroundStyle(OnyxTheme.Colors.textTertiary)
                    case .settings:
                        Image(systemName: "gearshape")
                            .foregroundStyle(OnyxTheme.Colors.textTertiary)
                        Text("Settings")
                            .foregroundStyle(OnyxTheme.Colors.textTertiary)
                    }
                }
            }
            .font(.system(size: 14, weight: .regular))
            Spacer()

            // Edit / View mode toggle (only for document tabs)
            if let tab = appState.activeTab, tab.kind == .document {
                HStack(spacing: 2) {
                    modeButton(icon: "pencil", isActive: appState.editorMode == .edit) {
                        appState.editorMode = .edit
                    }
                    modeButton(icon: "eye", isActive: appState.editorMode == .view) {
                        appState.editorMode = .view
                    }
                }
                .padding(2)
                .glassEffect(.regular, in: Capsule())
                .padding(.trailing, 12)
            }
        }
        .padding(.vertical, 10)
        .background(.clear)
    }

    private func modeButton(icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isActive ? OnyxTheme.Colors.textPrimary : OnyxTheme.Colors.textTertiary)
                .frame(width: 24, height: 24)
                .background(
                    isActive
                        ? Capsule().fill(Color.white.opacity(0.1))
                        : nil
                )
        }
        .buttonStyle(.plain)
    }
}

struct EmptyEditorView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("No Document Open")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Select a document from the sidebar, or press \u{2318}T to open a new tab.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
