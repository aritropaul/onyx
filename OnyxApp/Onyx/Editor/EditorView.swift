import SwiftUI

struct EditorView: View {
    let documentId: String
    @Environment(AppState.self) private var appState
    @State private var documentTitle: String = ""
    @State private var markdownText: String = ""
    @State private var documentMetadata = DocumentMetadata()
    @State private var cursorOffset: Int = 0
    @State private var isLoading = true

    private var bodyBinding: Binding<String> {
        Binding(
            get: {
                let (_, body) = MarkdownSerializer.parseFrontmatter(markdownText)
                return body
            },
            set: { newBody in
                let fm = MarkdownSerializer.generateFrontmatter(metadata: documentMetadata)
                markdownText = fm + "\n" + newBody
            }
        )
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        // Title
                        TextField("Untitled", text: $documentTitle, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(nil)
                            .onSubmit { saveTitle() }
                            .padding(.horizontal, 64)
                            .padding(.top, 24)
                            .padding(.bottom, 12)
                            .frame(maxWidth: 800, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .center)

                        // Frontmatter property editor
                        FrontmatterView(metadata: $documentMetadata)
                            .frame(maxWidth: 800)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .onChange(of: documentMetadata) { _, newMetadata in
                                guard !isLoading else { return }
                                markdownText = MarkdownSerializer.replaceFrontmatter(in: markdownText, with: newMetadata)
                                autoSave()
                                sendSyncUpdate()
                            }

                        // Markdown editor — body only, no frontmatter
                        MarkdownEditorField(
                            text: bodyBinding,
                            mode: appState.editorMode,
                            onTextChange: { _ in
                                autoSave()
                                sendSyncUpdate()
                            },
                            onCursorChange: { offset in
                                cursorOffset = offset
                                sendCursorPosition(offset: offset)
                            },
                            onWikiLinkClick: { title in
                                navigateToDocument(titled: title)
                            }
                        )
                        .frame(maxWidth: 800)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: max(geo.size.height - 120, 300))
                    }
                }

                // Stats bar (fixed at bottom)
                DocumentStatsBar(
                    wordCount: wordCount,
                    charCount: charCount,
                    isSynced: appState.syncManager?.isConnected ?? false
                )
            }
        }
        .background(.clear)
        .onAppear {
            loadDocument()
            connectSync()
        }
        .onDisappear {
            saveAll()
            disconnectSync()
        }
    }

    // MARK: - Stats

    private var bodyText: String {
        let (_, body) = MarkdownSerializer.parseFrontmatter(markdownText)
        return body
    }

    private var wordCount: Int {
        let words = bodyText.split { $0.isWhitespace || $0.isNewline }
        return words.count
    }

    private var charCount: Int {
        bodyText.count
    }

    // MARK: - Persistence

    private func loadDocument() {
        Task { @MainActor in
            if let content = try? await appState.provider.loadDocument(id: documentId) {
                isLoading = true
                documentMetadata = content.metadata
                markdownText = content.text
                isLoading = false
            }

            // Use persisted tab title immediately (no async dependency)
            if let tab = appState.openTabs.first(where: { $0.id == documentId }) {
                documentTitle = tab.title
            }

            // Then try to get the most up-to-date title
            if appState.documents.isEmpty {
                await appState.loadSidebarData()
            }
            if let docInfo = appState.documents.first(where: { $0.id == documentId }),
               !docInfo.title.isEmpty {
                documentTitle = docInfo.title
            } else if let doc = try? appState.database.document(id: documentId) {
                documentTitle = doc.title
            }
        }
    }

    @State private var autoSaveTask: Task<Void, Never>?

    private func autoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            saveDocument()
        }
    }

    private func saveTitle() {
        guard !documentTitle.isEmpty else { return }
        guard var doc = try? appState.database.document(id: documentId) else { return }
        guard doc.title != documentTitle else { return }
        doc.title = documentTitle
        doc.updatedAt = Date()
        try? appState.database.saveDocument(&doc)
    }

    private func saveDocument() {
        var metadata = documentMetadata
        metadata.updated = Date()
        // Build the save text without mutating @State — writing back to markdownText
        // triggers onTextChange → autoSave → saveDocument in an infinite loop,
        // and each cycle writes to disk triggering the file watcher → indexVault.
        let text = MarkdownSerializer.replaceFrontmatter(in: markdownText, with: metadata)

        let content = DocumentContent(text: text, metadata: metadata)

        Task {
            try? await appState.provider.saveDocument(id: documentId, content: content)
        }
    }

    private func saveAll() {
        saveDocument()
        saveTitle()
    }

    // MARK: - Wiki Link Navigation

    private func navigateToDocument(titled title: String) {
        let pathComponents = title.split(separator: "/")

        if pathComponents.count > 1 {
            // Path-based link (e.g. "Teams/AI/README") — match projectId + title exactly
            let docTitle = String(pathComponents.last!)
            let projectPath = pathComponents.dropLast().joined(separator: "/")
            if let doc = appState.documents.first(where: {
                $0.title.caseInsensitiveCompare(docTitle) == .orderedSame &&
                $0.projectId.caseInsensitiveCompare(projectPath) == .orderedSame
            }) {
                appState.openDocument(id: doc.id)
            }
        } else {
            // Simple title link — resolve by proximity: same folder → parent/peer folders
            let candidates = appState.documents.filter {
                $0.title.caseInsensitiveCompare(title) == .orderedSame
            }
            guard !candidates.isEmpty else { return }
            if candidates.count == 1 {
                appState.openDocument(id: candidates[0].id)
                return
            }

            let currentProjectId = appState.documents.first(where: { $0.id == documentId })?.projectId ?? ""

            // 1. Same folder
            if let doc = candidates.first(where: { $0.projectId == currentProjectId }) {
                appState.openDocument(id: doc.id)
                return
            }

            // 2. Parent folder
            if !currentProjectId.isEmpty {
                let parentPath: String
                if let lastSlash = currentProjectId.lastIndex(of: "/") {
                    parentPath = String(currentProjectId[..<lastSlash])
                } else {
                    parentPath = "" // root
                }
                if let doc = candidates.first(where: { $0.projectId == parentPath }) {
                    appState.openDocument(id: doc.id)
                    return
                }

                // 3. Peer folders (siblings sharing the same parent)
                if let doc = candidates.first(where: { peerProjectId in
                    let candidateParent: String
                    if let slash = peerProjectId.projectId.lastIndex(of: "/") {
                        candidateParent = String(peerProjectId.projectId[..<slash])
                    } else {
                        candidateParent = ""
                    }
                    return candidateParent == parentPath
                }) {
                    appState.openDocument(id: doc.id)
                    return
                }
            }

            // 4. Fallback to first match
            appState.openDocument(id: candidates[0].id)
        }
    }

    // MARK: - Sync

    private func connectSync() {
        guard let syncManager = appState.syncManager else { return }
        let docId = documentId
        let token = appState.profileManager.authToken
        Task {
            await syncManager.connect(documentId: docId, markdownText: markdownText, authToken: token)
        }
    }

    private func disconnectSync() {
        guard let syncManager = appState.syncManager else { return }
        Task {
            await syncManager.disconnect()
        }
    }

    private func sendSyncUpdate() {
        guard let syncManager = appState.syncManager else { return }
        syncManager.sendDocumentUpdate(documentId: documentId, text: markdownText)
    }

    private func sendCursorPosition(offset: Int) {
        guard let syncManager = appState.syncManager, syncManager.isConnected else { return }
        Task {
            await syncManager.sendAwareness(
                offset: offset,
                userName: appState.profileManager.profile.displayName
            )
        }
    }
}
