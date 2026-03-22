import SwiftUI

@Observable @MainActor
final class AppState {
    let database: AppDatabase
    let profileManager: ProfileManager
    var syncManager: SyncManager?
    var provider: any DocumentProvider
    var vaultURL: URL?

    var selectedProjectId: String?
    var isCommandPaletteVisible: Bool = false
    var isSidebarVisible: Bool = true
    var isVaultConfigured: Bool = true
    var editorMode: EditorMode = .view

    // Tab state
    var aiViewModels: [String: AIAssistantViewModel] = [:]
    var openTabs: [TabItem] = [] {
        didSet { persistTabs() }
    }
    var activeTabId: String? {
        didSet { UserDefaults.standard.set(activeTabId, forKey: "onyx.activeTabId") }
    }

    var selectedDocumentId: String? {
        activeTabId
    }

    // Provider-sourced data for sidebar
    var projects: [ProjectInfo] = []
    var documents: [DocumentInfo] = []

    init(database: AppDatabase = .shared) {
        self.database = database
        self.profileManager = ProfileManager()
        self.syncManager = SyncManager()
        self.provider = DatabaseProvider(database: database)
        restoreTabs()
    }

    private func persistTabs() {
        if let data = try? JSONEncoder().encode(openTabs) {
            UserDefaults.standard.set(data, forKey: "onyx.openTabs")
        }
    }

    private func restoreTabs() {
        if let data = UserDefaults.standard.data(forKey: "onyx.openTabs"),
           let tabs = try? JSONDecoder().decode([TabItem].self, from: data) {
            openTabs = tabs
        }
        activeTabId = UserDefaults.standard.string(forKey: "onyx.activeTabId")
    }

    func configureVault(url: URL) {
        if url.path.isEmpty {
            provider = DatabaseProvider(database: database)
            vaultURL = nil
            isVaultConfigured = true
        } else {
            provider = VaultProvider(vaultURL: url)
            vaultURL = url
            isVaultConfigured = true
        }
        Task {
            await loadSidebarData()
        }
        startObservingChanges()
    }

    // MARK: - Sidebar Data

    func refreshSidebarData() {
        Task {
            await loadSidebarData()
        }
    }

    func loadSidebarData() async {
        projects = (try? await provider.projects()) ?? []
        documents = (try? await provider.allDocuments()) ?? []
    }

    private var observeTask: Task<Void, Never>?

    func startObservingChanges() {
        observeTask?.cancel()
        let provider = self.provider
        observeTask = Task { [weak self] in
            for await _ in provider.observeChanges() {
                self?.refreshSidebarData()
            }
        }
    }

    // MARK: - Tab Management

    func openDocument(id: String) {
        if let existing = openTabs.firstIndex(where: { $0.id == id }) {
            activeTabId = openTabs[existing].id
        } else {
            let docInfo = documents.first(where: { $0.id == id })
            let tab = TabItem(
                id: id,
                title: docInfo?.title ?? "Untitled",
                projectId: docInfo?.projectId ?? "",
                kind: .document
            )
            openTabs.append(tab)
            activeTabId = id
        }
    }

    func openAITab() {
        let id = "ai-\(UUID().uuidString.prefix(8))"
        let tab = TabItem(id: id, title: "Claude", projectId: "", kind: .ai)
        let vm = AIAssistantViewModel()
        vm.tabId = id
        aiViewModels[id] = vm
        openTabs.append(tab)
        activeTabId = id
    }

    func openNewTab() {
        let id = "new-\(UUID().uuidString.prefix(8))"
        let tab = TabItem(id: id, title: "New Tab", projectId: "", kind: .document)
        openTabs.append(tab)
        activeTabId = id
    }

    func openSettings() {
        if let existing = openTabs.first(where: { $0.kind == .settings }) {
            activeTabId = existing.id
        } else {
            let tab = TabItem(id: "settings", title: "Settings", projectId: "", kind: .settings)
            openTabs.append(tab)
            activeTabId = "settings"
        }
    }

    func closeVault() {
        observeTask?.cancel()
        observeTask = nil
        openTabs.removeAll()
        activeTabId = nil
        projects.removeAll()
        documents.removeAll()
        selectedProjectId = nil
        vaultURL = nil
        provider = DatabaseProvider(database: database)
        isVaultConfigured = false
    }

    var activeTab: TabItem? {
        guard let id = activeTabId else { return nil }
        return openTabs.first { $0.id == id }
    }

    func closeTab(id: String) {
        guard let idx = openTabs.firstIndex(where: { $0.id == id }) else { return }
        // Save AI chat before closing, then clean up
        aiViewModels[id]?.save()
        aiViewModels[id]?.cancel()
        aiViewModels.removeValue(forKey: id)
        openTabs.remove(at: idx)
        if activeTabId == id {
            if !openTabs.isEmpty {
                let newIdx = min(idx, openTabs.count - 1)
                activeTabId = openTabs[newIdx].id
            } else {
                activeTabId = nil
            }
        }
    }

    func closeOtherTabs(except id: String) {
        openTabs.removeAll { $0.id != id }
        activeTabId = id
    }

    func closeActiveTab() {
        guard let id = activeTabId else { return }
        closeTab(id: id)
    }

    func selectNextTab() {
        guard let id = activeTabId,
              let idx = openTabs.firstIndex(where: { $0.id == id }),
              idx < openTabs.count - 1 else { return }
        activeTabId = openTabs[idx + 1].id
    }

    func selectPreviousTab() {
        guard let id = activeTabId,
              let idx = openTabs.firstIndex(where: { $0.id == id }),
              idx > 0 else { return }
        activeTabId = openTabs[idx - 1].id
    }

    // MARK: - Tree Helpers

    func childProjects(of parentId: String?) -> [ProjectInfo] {
        projects.filter { $0.parentId == parentId }
    }

    func ancestors(of projectId: String) -> [ProjectInfo] {
        var result: [ProjectInfo] = []
        var currentId: String? = projectId
        while let id = currentId, let project = projects.first(where: { $0.id == id }) {
            result.insert(project, at: 0)
            currentId = project.parentId
        }
        return result
    }

    // MARK: - Document Management

    func createDocument(projectId: String, title: String? = nil) {
        let docTitle: String
        if let title = title, !title.isEmpty {
            docTitle = title
        } else {
            docTitle = nextUntitledName(in: projectId)
        }
        Task {
            if let doc = try? await provider.createDocument(in: projectId, title: docTitle) {
                refreshSidebarData()
                openDocument(id: doc.id)
            }
        }
    }

    private func nextUntitledName(in projectId: String) -> String {
        let existing = documents.filter { $0.projectId == projectId }.map(\.title)
        if !existing.contains("Untitled") { return "Untitled" }
        var n = 1
        while existing.contains("Untitled-\(n)") { n += 1 }
        return "Untitled-\(n)"
    }

    func createProject(name: String) {
        Task {
            if let project = try? await provider.createProject(name: name) {
                selectedProjectId = project.id
                refreshSidebarData()
            }
        }
    }

    func createProject(name: String, parentId: String?) {
        Task {
            if let project = try? await provider.createProject(name: name, parentId: parentId) {
                selectedProjectId = project.id
                refreshSidebarData()
            }
        }
    }

    func createProject(teamId: String, name: String) {
        createProject(name: name)
    }

    func deleteDocument(id: String) {
        Task {
            try? await provider.deleteDocument(id: id)
            closeTab(id: id)
            refreshSidebarData()
        }
    }

    func deleteProject(id: String) {
        Task {
            try? await provider.deleteProject(id: id)
            if selectedProjectId == id {
                selectedProjectId = nil
            }
            refreshSidebarData()
        }
    }

    func renameProject(id: String, name: String) {
        guard !name.isEmpty else { return }
        Task {
            try? await provider.renameProject(id: id, name: name)
            refreshSidebarData()
        }
    }

    func ensureDefaultTeam() {
        let teams = (try? database.teams()) ?? []
        if teams.isEmpty {
            var team = Team(name: "Personal")
            try? database.saveTeam(&team)
        }
    }
}
