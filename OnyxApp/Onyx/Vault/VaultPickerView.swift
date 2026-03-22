import SwiftUI
import AppKit

struct VaultPickerView: View {
    let onVaultSelected: (URL) -> Void
    @State private var existingPath: String?

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(.tertiary)

                Text("Welcome to Onyx")
                    .font(.title.weight(.semibold))

                Text("Choose how you'd like to store your documents.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    createNewVault()
                } label: {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("Create New Vault")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    openExistingVault()
                } label: {
                    HStack {
                        Image(systemName: "folder")
                        Text("Open Existing Vault")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    onVaultSelected(URL(fileURLWithPath: ""))
                } label: {
                    Text("Use Default Storage (SQLite)")
                        .font(.caption)
                }
                .buttonStyle(.link)
                .padding(.top, 8)
            }
            .frame(width: 280)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thickMaterial)
    }

    private func createNewVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder for your new Onyx vault"
        panel.prompt = "Create Vault"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try BookmarkManager.saveBookmark(for: url)
            // Create .onyx directory structure
            let onyxDir = url.appendingPathComponent(".onyx", isDirectory: true)
            try FileManager.default.createDirectory(at: onyxDir, withIntermediateDirectories: true)
            onVaultSelected(url)
        } catch {
            print("[VaultPicker] Failed to create vault: \(error)")
        }
    }

    private func openExistingVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an existing Onyx vault folder"
        panel.prompt = "Open Vault"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try BookmarkManager.saveBookmark(for: url)
            onVaultSelected(url)
        } catch {
            print("[VaultPicker] Failed to open vault: \(error)")
        }
    }
}
