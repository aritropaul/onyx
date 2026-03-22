import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isRegisterMode = false
    @Environment(\.dismiss) private var dismiss

    private var authManager: AuthManager {
        AuthManager(profileManager: appState.profileManager)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(isRegisterMode ? "Create Account" : "Sign In")
                .font(.title2.weight(.semibold))

            VStack(spacing: 12) {
                if isRegisterMode {
                    TextField("Display Name", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }

                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }

            if let error = authManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(action: submit) {
                if authManager.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(isRegisterMode ? "Register" : "Login")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(authManager.isLoading || !isFormValid)

            Button(isRegisterMode ? "Already have an account? Sign In" : "Don't have an account? Register") {
                isRegisterMode.toggle()
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(32)
        .frame(width: 320)
    }

    private var isFormValid: Bool {
        if isRegisterMode {
            return !email.isEmpty && !password.isEmpty && !displayName.isEmpty
        }
        return !email.isEmpty && !password.isEmpty
    }

    private func submit() {
        let manager = AuthManager(profileManager: appState.profileManager)
        Task {
            let success: Bool
            if isRegisterMode {
                success = await manager.register(email: email, password: password, displayName: displayName)
            } else {
                success = await manager.login(email: email, password: password)
            }
            if success {
                dismiss()
            }
        }
    }
}
