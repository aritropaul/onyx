import SwiftUI

struct ProfileSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var editedName: String = ""
    @State private var showLoginSheet = false

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Display Name", text: $editedName)
                    .onAppear { editedName = appState.profileManager.profile.displayName }
                    .onSubmit { appState.profileManager.updateDisplayName(editedName) }
                    .onChange(of: editedName) { _, newValue in
                        appState.profileManager.updateDisplayName(newValue)
                    }

                LabeledContent("User ID") {
                    Text(appState.profileManager.profile.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Account") {
                if let email = appState.profileManager.profile.email,
                   appState.profileManager.isAuthenticated {
                    LabeledContent("Email") {
                        Text(email)
                            .foregroundStyle(.secondary)
                    }

                    Button("Logout", role: .destructive) {
                        appState.profileManager.logout()
                    }
                } else {
                    Button("Sign In") {
                        showLoginSheet = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .sheet(isPresented: $showLoginSheet) {
            LoginView()
        }
    }
}
