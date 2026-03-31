import SwiftUI
import AppKit

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    @State private var renamingProjectId: String?
    @State private var renameText: String = ""
    @State private var hoveredId: String?
    @State private var expandedIds: Set<String> = []
    @State private var searchQuery: String = ""
    @State private var ragResults: [RAGResult] = []
    @State private var ragSearchTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool

    private var isVaultBacked: Bool {
        appState.vaultURL != nil
    }

    private var vaultName: String {
        appState.vaultURL?.lastPathComponent ?? "Onyx"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar: icon-only actions
            HStack(spacing: 4) {
                sidebarToolbarButton(icon: "doc.badge.plus", tooltip: "New Document") {
                    if let projectId = appState.selectedProjectId ?? appState.projects.first?.id {
                        appState.createDocument(projectId: projectId)
                    }
                }
                sidebarToolbarButton(icon: "folder.badge.plus", tooltip: "New Folder") {
                    appState.createProject(name: "New Folder")
                }
                sidebarToolbarButton(icon: "folder", tooltip: "Open Folder") {
                    openFolderAsProject()
                }
                if appState.vaultURL != nil {
                    sidebarToolbarButton(icon: "xmark.circle", tooltip: "Close Folder") {
                        appState.closeVault()
                    }
                }

                Spacer()

                sidebarToolbarButton(icon: "chevron.right", tooltip: "Collapse All") {
                    withAnimation(OnyxTheme.Animation.quick) {
                        expandedIds.removeAll()
                    }
                }
                sidebarToolbarButton(icon: "chevron.down", tooltip: "Expand All") {
                    withAnimation(OnyxTheme.Animation.quick) {
                        expandedIds = Set(appState.projects.map(\.id))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 36)
            .padding(.bottom, 12)

            // Vault name
            Text(vaultName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OnyxTheme.Colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 2)

            // RAG indexing indicator
            if appState.ragEngine.isIndexing {
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Indexing vault...")
                        .font(.system(size: 10))
                        .foregroundStyle(OnyxTheme.Colors.textTertiary)
                }
                .padding(.bottom, 4)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: appState.ragEngine.isIndexing)
            } else if appState.ragEngine.totalChunks > 0 {
                Text("\(appState.ragEngine.indexedDocumentCount) docs indexed")
                    .font(.system(size: 10))
                    .foregroundStyle(OnyxTheme.Colors.textTertiary.opacity(0.5))
                    .padding(.bottom, 4)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: appState.ragEngine.isIndexing)
            }

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(OnyxTheme.Colors.textTertiary)
                TextField("Search...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(OnyxTheme.Colors.textPrimary)
                    .focused($isSearchFocused)
                    .onExitCommand { searchQuery = ""; ragResults = []; isSearchFocused = false }
                    .onChange(of: searchQuery) { _, q in
                        debounceRAGSearch(q)
                    }
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        ragResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(OnyxTheme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSearchFocused ? OnyxTheme.Colors.surface : OnyxTheme.Colors.surface.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSearchFocused ? OnyxTheme.Colors.accent.opacity(0.4) : .clear, lineWidth: 1)
            )
            .animation(OnyxTheme.Animation.quick, value: isSearchFocused)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if appState.projects.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(OnyxTheme.Colors.textTertiary)
                            Text("No projects yet")
                                .font(.system(size: 13))
                                .foregroundStyle(OnyxTheme.Colors.textTertiary)
                            Button {
                                openFolderAsProject()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("Open Folder")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(OnyxTheme.Colors.accent)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: OnyxTheme.Radius.md)
                                        .fill(OnyxTheme.Colors.accentSubtle)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else if !searchQuery.isEmpty {
                        // Title matches (instant)
                        let q = searchQuery.lowercased()
                        let titleMatches = appState.documents
                            .filter { $0.title.lowercased().contains(q) }
                            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                        // Content matches via RAG (debounced)
                        let titleMatchIds = Set(titleMatches.map(\.id))
                        let contentMatches = ragResults.filter { !titleMatchIds.contains($0.chunk.documentId) }

                        let hasAny = !titleMatches.isEmpty || !contentMatches.isEmpty

                        if !hasAny {
                            Text("No results")
                                .font(.system(size: 11))
                                .foregroundStyle(OnyxTheme.Colors.textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 20)
                        }

                        // Title results
                        ForEach(titleMatches) { doc in
                            searchDocRow(doc: doc)
                        }

                        // Content results with snippet
                        ForEach(contentMatches, id: \.chunk.id) { result in
                            searchContentRow(result: result)
                        }
                    } else {
                        let flatItems = buildFlatList()
                        ForEach(flatItems, id: \.id) { item in
                            switch item.kind {
                            case .project(let project, let level):
                                projectRow(project: project, level: level)
                            case .document(let doc, let level):
                                docRow(doc: doc, level: level)
                            }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }

            // Bottom icon bar
            HStack(spacing: 12) {
                sidebarBottomButton(icon: "house") {
                    // Collapse all folders and scroll to top
                    withAnimation(OnyxTheme.Animation.quick) {
                        expandedIds.removeAll()
                        appState.selectedProjectId = nil
                    }
                }
                .help("Home")

                sidebarBottomButton(icon: "icloud") {
                    appState.openSettings()
                    // Navigate to sync tab
                }
                .help("Sync Settings")

                sidebarBottomButton(icon: "gearshape") {
                    appState.openSettings()
                }
                .help("Settings (⌘,)")

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(Color(white: 0.08))
        .onAppear {
            if expandedIds.isEmpty {
                expandedIds = Set(appState.projects.map(\.id))
            }
        }
    }

    // MARK: - Flat list

    private struct FlatItem: Identifiable {
        let id: String
        let kind: Kind
        enum Kind {
            case project(ProjectInfo, level: Int)
            case document(DocumentInfo, level: Int)
        }
    }

    private func buildFlatList() -> [FlatItem] {
        var items: [FlatItem] = []
        // Root-level documents (not inside any folder)
        let rootDocs = appState.documents
            .filter { $0.projectId.isEmpty }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        for doc in rootDocs {
            items.append(FlatItem(id: "d-\(doc.id)", kind: .document(doc, level: 0)))
        }
        for root in appState.childProjects(of: nil) {
            appendProjectTree(root, level: 0, into: &items)
        }
        return items
    }

    private func appendProjectTree(_ project: ProjectInfo, level: Int, into items: inout [FlatItem]) {
        items.append(FlatItem(id: "p-\(project.id)", kind: .project(project, level: level)))
        guard expandedIds.contains(project.id) else { return }
        for child in appState.childProjects(of: project.id) {
            appendProjectTree(child, level: level + 1, into: &items)
        }
        let docs = appState.documents
            .filter { $0.projectId == project.id }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        for doc in docs {
            items.append(FlatItem(id: "d-\(doc.id)", kind: .document(doc, level: level + 1)))
        }
    }

    // MARK: - Project row

    private func projectRow(project: ProjectInfo, level: Int) -> some View {
        let isHovered = hoveredId == "project-\(project.id)"
        let isExpanded = expandedIds.contains(project.id)

        return Button {
            withAnimation(OnyxTheme.Animation.quick) {
                if isExpanded {
                    expandedIds.remove(project.id)
                } else {
                    expandedIds.insert(project.id)
                }
            }
        } label: {
            HStack(spacing: 6) {
                // Chevron on the LEFT
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(OnyxTheme.Colors.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(OnyxTheme.Animation.quick, value: isExpanded)
                    .frame(width: 12)

                Image(systemName: "folder.fill")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(red: 0, green: 0.478, blue: 1.0))
                    .frame(width: 16)

                if renamingProjectId == project.id {
                    TextField("Name", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .regular))
                        .onSubmit { commitRename(projectId: project.id) }
                        .onExitCommand { renamingProjectId = nil }
                } else {
                    Text(project.name)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(OnyxTheme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .overlay(alignment: .trailing) {
                if isHovered {
                    SmallIconButton(icon: "plus") {
                        appState.createDocument(projectId: project.id)
                    }
                    .padding(.trailing, 8)
                    .transition(.opacity)
                }
            }
            .padding(.leading, CGFloat(level) * 20 + 8)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: OnyxTheme.Radius.md)
                    .fill(isHovered ? .white.opacity(0.04) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: OnyxTheme.Radius.md))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(OnyxTheme.Animation.quick) {
                hoveredId = hovering ? "project-\(project.id)" : nil
            }
        }
        .contextMenu {
            Button("New Page") {
                appState.createDocument(projectId: project.id)
            }
            Button("New Sub-folder") {
                appState.createProject(name: "New Folder", parentId: project.id)
            }
            Button("Rename") {
                renameText = project.name
                renamingProjectId = project.id
            }
            if let vaultURL = appState.vaultURL {
                Divider()
                Button("Open in Finder") {
                    let url = vaultURL.appendingPathComponent(project.id, isDirectory: true)
                    NSWorkspace.shared.open(url)
                }
            }
            Divider()
            Button("Delete Project", role: .destructive) {
                appState.deleteProject(id: project.id)
            }
        }
    }

    // MARK: - Document row

    private func docRow(doc: DocumentInfo, level: Int) -> some View {
        let isSelected = appState.activeTabId == doc.id
        let isHovered = hoveredId == "doc-\(doc.id)"

        return Button {
            appState.selectedProjectId = doc.projectId
            appState.openDocument(id: doc.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(isSelected ? OnyxTheme.Colors.textPrimary : OnyxTheme.Colors.textTertiary)
                    .frame(width: 16)

                Text(doc.title.isEmpty ? "Untitled" : doc.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? OnyxTheme.Colors.textPrimary : OnyxTheme.Colors.textSecondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.leading, CGFloat(level) * 20 + 8)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: OnyxTheme.Radius.md)
                    .fill(isSelected ? .white.opacity(0.08) : (isHovered ? .white.opacity(0.04) : .clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: OnyxTheme.Radius.md))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(OnyxTheme.Animation.quick) {
                hoveredId = hovering ? "doc-\(doc.id)" : nil
            }
        }
        .contextMenu {
            if appState.vaultURL != nil, let vault = appState.provider as? VaultProvider {
                Button("Reveal in Finder") {
                    let url = vault.resolveDocumentURL(id: doc.id)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Divider()
            }
            Button("Delete", role: .destructive) {
                appState.deleteDocument(id: doc.id)
            }
        }
    }

    private func commitRename(projectId: String) {
        if !renameText.isEmpty {
            appState.renameProject(id: projectId, name: renameText)
        }
        renamingProjectId = nil
    }

    private func openFolderAsProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a folder to open as workspace"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if appState.vaultURL == nil {
            // No vault configured — use this folder as the vault
            try? BookmarkManager.saveBookmark(for: url)
            appState.configureVault(url: url)
        } else if let vaultURL = appState.vaultURL {
            // Vault exists — symlink folder into vault if it's external
            if !url.path.hasPrefix(vaultURL.path) {
                let destURL = vaultURL.appendingPathComponent(url.lastPathComponent, isDirectory: true)
                try? FileManager.default.createSymbolicLink(at: destURL, withDestinationURL: url)
            }
            appState.refreshSidebarData()
        }
    }

    private func sidebarToolbarButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        SmallIconButton(icon: icon, action: action)
            .help(tooltip)
    }

    private func sidebarBottomButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OnyxTheme.Colors.textSecondary)
                .frame(width: 36, height: 36)
                .glassEffect(.regular, in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search rows

    private func searchDocRow(doc: DocumentInfo) -> some View {
        Button {
            appState.pendingSearchHighlight = searchQuery
            appState.openDocument(id: doc.id)
            isSearchFocused = false
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(OnyxTheme.Colors.textTertiary)
                    .frame(width: 16)
                Text(doc.title.isEmpty ? "Untitled" : doc.title)
                    .font(.system(size: 12))
                    .foregroundStyle(OnyxTheme.Colors.textSecondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func searchContentRow(result: RAGResult) -> some View {
        Button {
            appState.pendingSearchHighlight = searchQuery
            appState.openDocument(id: result.chunk.documentId)
            isSearchFocused = false
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(OnyxTheme.Colors.accent.opacity(0.7))
                    Text(result.chunk.documentTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(OnyxTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
                Text(result.chunk.content.prefix(80) + (result.chunk.content.count > 80 ? "..." : ""))
                    .font(.system(size: 10))
                    .foregroundStyle(OnyxTheme.Colors.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Debounced RAG search

    private func debounceRAGSearch(_ query: String) {
        ragSearchTask?.cancel()
        guard query.count >= 3 else {
            ragResults = []
            return
        }
        ragSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let results = appState.ragEngine.search(query: query, topK: 5)
            // Filter out low-relevance noise
            ragResults = results.filter { $0.score > 0.01 }
        }
    }
}
