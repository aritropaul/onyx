import SwiftUI
import GRDB
import GRDBQuery

@main
struct OnyxApp: App {
    @State private var appState: AppState

    init() {
        let state = AppState()
        if BookmarkManager.hasBookmark {
            if let url = BookmarkManager.startAccessing() {
                state.configureVault(url: url)
            }
        }
        self._appState = State(initialValue: state)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(\.appDatabase, appState.database)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 700)
        .commands {
            AppCommands(appState: appState)
        }

    }
}

// MARK: - Database Environment Key

private struct AppDatabaseKey: EnvironmentKey {
    static let defaultValue: AppDatabase = .shared
}

extension EnvironmentValues {
    var appDatabase: AppDatabase {
        get { self[AppDatabaseKey.self] }
        set { self[AppDatabaseKey.self] = newValue }
    }
}

// MARK: - Make AppDatabase a TopLevelDatabaseReader for GRDBQuery

extension AppDatabase: TopLevelDatabaseReader {
    @MainActor var reader: any DatabaseReader {
        get throws { dbWriter }
    }
}
