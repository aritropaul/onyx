import Foundation
import SwiftUI

@Observable @MainActor
final class AppSettings {
    static let shared = AppSettings()

    // MARK: - Editor

    var editorFontSize: Double {
        didSet { save("editorFontSize", value: editorFontSize) }
    }
    var editorLineHeight: Double {
        didSet { save("editorLineHeight", value: editorLineHeight) }
    }
    var editorMaxWidth: Double {
        didSet { save("editorMaxWidth", value: editorMaxWidth) }
    }
    var autoSaveDelay: Double {
        didSet { save("autoSaveDelay", value: autoSaveDelay) }
    }
    var showLineNumbers: Bool {
        didSet { save("showLineNumbers", value: showLineNumbers) }
    }

    // MARK: - Appearance

    var accentColorHex: String {
        didSet { save("accentColorHex", value: accentColorHex) }
    }
    var sidebarWidth: Double {
        didSet { save("sidebarWidth", value: sidebarWidth) }
    }

    // MARK: - Sync

    var syncEnabled: Bool {
        didSet { save("syncEnabled", value: syncEnabled) }
    }
    var syncHost: String {
        didSet { save("syncHost", value: syncHost) }
    }
    var syncPort: Int {
        didSet { save("syncPort", value: syncPort) }
    }

    // MARK: - AI

    var claudePath: String {
        didSet { save("claudePath", value: claudePath) }
    }
    var claudeModel: String {
        didSet { save("claudeModel", value: claudeModel) }
    }

    // MARK: - Init

    private let defaults = UserDefaults.standard
    private let prefix = "onyx.settings."

    init() {
        self.editorFontSize = UserDefaults.standard.object(forKey: "onyx.settings.editorFontSize") as? Double ?? 15
        self.editorLineHeight = UserDefaults.standard.object(forKey: "onyx.settings.editorLineHeight") as? Double ?? 1.5
        self.editorMaxWidth = UserDefaults.standard.object(forKey: "onyx.settings.editorMaxWidth") as? Double ?? 800
        self.autoSaveDelay = UserDefaults.standard.object(forKey: "onyx.settings.autoSaveDelay") as? Double ?? 300
        self.showLineNumbers = UserDefaults.standard.object(forKey: "onyx.settings.showLineNumbers") as? Bool ?? false
        self.accentColorHex = UserDefaults.standard.string(forKey: "onyx.settings.accentColorHex") ?? "#6685FF"
        self.sidebarWidth = UserDefaults.standard.object(forKey: "onyx.settings.sidebarWidth") as? Double ?? 228
        self.syncEnabled = UserDefaults.standard.object(forKey: "onyx.settings.syncEnabled") as? Bool ?? false
        self.syncHost = UserDefaults.standard.string(forKey: "onyx.settings.syncHost") ?? "localhost"
        self.syncPort = UserDefaults.standard.object(forKey: "onyx.settings.syncPort") as? Int ?? 3001
        self.claudePath = UserDefaults.standard.string(forKey: "onyx.settings.claudePath") ?? ""
        self.claudeModel = UserDefaults.standard.string(forKey: "onyx.settings.claudeModel") ?? "sonnet"
    }

    private func save(_ key: String, value: Any) {
        defaults.set(value, forKey: prefix + key)
    }

    /// Auto-detect claude path if not set
    var resolvedClaudePath: String {
        if !claudePath.isEmpty { return claudePath }
        let fm = FileManager.default
        let home = NSHomeDirectory()

        let staticPaths = [
            "\(home)/.local/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.claude/bin/claude",
            "/opt/homebrew/bin/claude",
            "/opt/homebrew/opt/node/bin/claude",
        ]
        if let hit = staticPaths.first(where: { fm.fileExists(atPath: $0) }) {
            return hit
        }

        let nvmDir = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmDir) {
            let sorted = versions.sorted(by: >)
            for v in sorted {
                let p = "\(nvmDir)/\(v)/bin/claude"
                if fm.fileExists(atPath: p) { return p }
            }
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !out.isEmpty, fm.fileExists(atPath: out) {
                return out
            }
        } catch {
            // fall through
        }

        return ""
    }
}
