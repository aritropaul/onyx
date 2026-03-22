import SwiftUI

struct AppCommands: Commands {
    @Bindable var appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Document") {
                if let projectId = appState.selectedProjectId {
                    appState.createDocument(projectId: projectId)
                }
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(appState.selectedProjectId == nil)

            Button("New Project") {
                let teams = (try? appState.database.teams()) ?? []
                if let team = teams.first {
                    appState.createProject(teamId: team.id, name: "New Project")
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("New Tab") {
                appState.openNewTab()
            }
            .keyboardShortcut("t", modifiers: .command)
        }

        CommandGroup(replacing: .sidebar) {
            Button("Toggle Sidebar") {
                withAnimation(OnyxTheme.Animation.standard) {
                    appState.isSidebarVisible.toggle()
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
        }

        CommandGroup(after: .textEditing) {
            Button("Command Palette") {
                appState.isCommandPaletteVisible.toggle()
            }
            .keyboardShortcut("k", modifiers: .command)

            Divider()

            Button("Close Tab") {
                appState.closeActiveTab()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(appState.activeTabId == nil)

            Button("Next Tab") {
                appState.selectNextTab()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled(appState.openTabs.count < 2)

            Button("Previous Tab") {
                appState.selectPreviousTab()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled(appState.openTabs.count < 2)
        }
    }
}
