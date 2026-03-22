import Foundation

enum MessageState: String, Equatable, Codable {
    case complete
    case thinking
    case streaming
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    var content: String
    var state: MessageState
    let timestamp: Date

    enum Role: String, Codable {
        case user
        case assistant
    }

    init(role: Role, content: String, state: MessageState, timestamp: Date = Date()) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.state = state
        self.timestamp = timestamp
    }
}

@Observable @MainActor
final class AIAssistantViewModel {
    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isLoading: Bool = false
    var tabId: String?

    /// UUID session ID for this conversation — persists across messages
    var sessionId: String = UUID().uuidString

    private var currentProcess: Process?
    private var revealTask: Task<Void, Never>?
    private var messageCount: Int = 0

    /// Called by the view to update the tab title on first message
    var onFirstMessage: ((String) -> Void)?

    func sendMessage(vaultURL: URL?) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        let isFirst = messages.filter({ $0.role == .user }).isEmpty
        inputText = ""
        messages.append(ChatMessage(role: .user, content: text, state: .complete))
        messages.append(ChatMessage(role: .assistant, content: "", state: .thinking))
        isLoading = true

        if isFirst {
            let title = String(text.prefix(30)) + (text.count > 30 ? "..." : "")
            onFirstMessage?(title)
        }

        let isFirstMessage = messageCount == 0
        messageCount += 1

        let workDir = vaultURL
        Task.detached { [weak self] in
            await self?.runClaude(prompt: text, workingDirectory: workDir, isFirstMessage: isFirstMessage)
        }
    }

    func cancel() {
        currentProcess?.terminate()
        currentProcess = nil
        revealTask?.cancel()
        revealTask = nil
        if let lastIndex = messages.indices.last, messages[lastIndex].role == .assistant {
            messages[lastIndex].state = .complete
        }
        isLoading = false
    }

    func clearChat() {
        cancel()
        messages.removeAll()
        messageCount = 0
        sessionId = UUID().uuidString
    }

    // MARK: - Text reveal animation

    private func revealText(_ fullText: String) {
        revealTask?.cancel()

        let words = fullText.components(separatedBy: " ")
        guard !words.isEmpty else {
            updateLastAssistant(fullText, state: .complete)
            isLoading = false
            return
        }

        updateLastAssistant("", state: .streaming)

        revealTask = Task { [weak self] in
            var revealed = ""
            for (i, word) in words.enumerated() {
                if Task.isCancelled { return }
                revealed += (i > 0 ? " " : "") + word
                self?.updateLastAssistant(revealed, state: .streaming)
                try? await Task.sleep(for: .milliseconds(18))
            }
            if !Task.isCancelled {
                self?.updateLastAssistant(fullText, state: .complete)
                self?.isLoading = false
                self?.save()
            }
        }
    }

    // MARK: - Claude process

    private func runClaude(prompt: String, workingDirectory: URL?, isFirstMessage: Bool) {
        let resolvedPath = AppSettings.shared.resolvedClaudePath
        guard !resolvedPath.isEmpty else {
            Task { @MainActor [weak self] in
                self?.updateLastAssistant("Error: `claude` CLI not found.", state: .complete)
                self?.isLoading = false
            }
            return
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        let model = AppSettings.shared.claudeModel
        process.executableURL = URL(fileURLWithPath: resolvedPath)

        var args = ["-p", "--dangerously-skip-permissions", "--permission-mode", "bypassPermissions", "--model", model]

        if isFirstMessage {
            // First message: start a new session with this ID
            args += ["--session-id", sessionId]

            // Load custom system prompt from .onyx/ai/prompt.md
            // Tell Claude it has full tool access
            var systemAddendum = "You have full permissions to read, write, edit, and execute files. Never ask the user for permission — just do it."

            if let dir = workingDirectory {
                let promptFile = dir.appendingPathComponent(".onyx/ai/prompt.md")
                if let customPrompt = try? String(contentsOf: promptFile, encoding: .utf8),
                   !customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    systemAddendum += "\n\n" + customPrompt
                }
            }

            args += ["--append-system-prompt", systemAddendum]
        } else {
            // Subsequent messages: resume the existing session
            args += ["--resume", sessionId]
        }

        args.append(prompt)
        process.arguments = args
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        if let dir = workingDirectory {
            process.currentDirectoryURL = dir
        }

        self.currentProcess = process

        process.terminationHandler = { [weak self] _ in
            let outData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let errOutput = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentProcess = nil

                if output.isEmpty && !errOutput.isEmpty {
                    self.updateLastAssistant("Error: \(errOutput)", state: .complete)
                    self.isLoading = false
                } else if output.isEmpty {
                    self.updateLastAssistant("No response received.", state: .complete)
                    self.isLoading = false
                } else {
                    self.revealText(output)
                }
            }
        }

        do {
            try process.run()
        } catch {
            Task { @MainActor [weak self] in
                self?.updateLastAssistant("Failed to launch claude: \(error.localizedDescription)", state: .complete)
                self?.isLoading = false
            }
        }
    }

    private func updateLastAssistant(_ content: String, state: MessageState) {
        guard let lastIndex = messages.indices.last,
              messages[lastIndex].role == .assistant else { return }
        messages[lastIndex].content = content
        messages[lastIndex].state = state
    }

    // MARK: - Persistence

    private static var chatDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Onyx/ai-chats", isDirectory: true)
    }

    func save() {
        guard let tabId else { return }
        let completed = messages.filter { $0.state == .complete && !$0.content.isEmpty }
        guard !completed.isEmpty else { return }
        let dir = Self.chatDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Save messages + sessionId together
        let payload = ChatPayload(sessionId: sessionId, messageCount: messageCount, messages: completed)
        let url = dir.appendingPathComponent("\(tabId).json")
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func loadIfNeeded() {
        guard let tabId, messages.isEmpty else { return }
        let url = Self.chatDir.appendingPathComponent("\(tabId).json")
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(ChatPayload.self, from: data) else { return }
        messages = payload.messages
        sessionId = payload.sessionId
        messageCount = payload.messageCount
    }

    static func deleteChatFile(tabId: String) {
        let url = chatDir.appendingPathComponent("\(tabId).json")
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Persistence model

private struct ChatPayload: Codable {
    let sessionId: String
    let messageCount: Int
    let messages: [ChatMessage]
}
