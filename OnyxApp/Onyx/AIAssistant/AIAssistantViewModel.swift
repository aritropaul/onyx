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
    var toolUses: [ToolUseInfo]

    enum Role: String, Codable {
        case user
        case assistant
    }

    init(role: Role, content: String, state: MessageState, timestamp: Date = Date(), toolUses: [ToolUseInfo] = []) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.state = state
        self.timestamp = timestamp
        self.toolUses = toolUses
    }
}

struct ToolUseInfo: Codable, Identifiable {
    let id: String
    let name: String
    let input: String

    init(name: String, input: String) {
        self.id = UUID().uuidString
        self.name = name
        self.input = input
    }
}

@Observable @MainActor
final class AIAssistantViewModel {
    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isLoading: Bool = false
    var tabId: String?

    /// Last retrieved RAG context for display in the UI
    var lastRetrievedContext: [RAGResult] = []
    var showContextPanel: Bool = false

    /// UUID session ID for this conversation — persists across messages
    var sessionId: String = UUID().uuidString

    private var currentProcess: Process?
    private var revealTask: Task<Void, Never>?
    private var messageCount: Int = 0

    /// Called by the view to update the tab title on first message
    var onFirstMessage: ((String) -> Void)?

    func sendMessage(vaultURL: URL?, ragEngine: RAGEngine?) {
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

        // RAG: retrieve relevant vault context and augment prompt
        let (ragContext, results) = ragEngine?.buildContext(for: text) ?? ("", [])
        lastRetrievedContext = results

        let augmentedPrompt: String
        if ragContext.isEmpty {
            augmentedPrompt = text
        } else {
            augmentedPrompt = "\(ragContext)\n\n\(text)"
        }

        let workDir = vaultURL
        Task.detached { [weak self] in
            await self?.runClaude(prompt: augmentedPrompt, workingDirectory: workDir, isFirstMessage: isFirstMessage)
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
        lastRetrievedContext = []
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

    // MARK: - Claude process (stream-json with --verbose)

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

        // Use --verbose + --output-format stream-json for real-time streaming.
        // Each JSON line is flushed immediately, so readabilityHandler gets events
        // as they happen — tool use shows up in real-time, and the final result
        // text arrives in the "result" event.
        var args = ["-p", "--verbose", "--output-format", "stream-json",
                    "--dangerously-skip-permissions", "--permission-mode", "bypassPermissions",
                    "--model", model]

        if isFirstMessage {
            args += ["--session-id", sessionId]

            var systemAddendum = """
            You are an AI assistant embedded in Onyx, a local-first document vault editor. You have full permissions to read, write, edit, and execute files. Never ask the user for permission — just do it.
            """

            if let dir = workingDirectory {
                systemAddendum += "\n\nThe vault is at: \(dir.path)"
                systemAddendum += "\nDocuments are markdown files with YAML frontmatter (id, created, updated, tags)."
                systemAddendum += "\nYou can read, create, search, and edit any file in this vault."

                let promptFile = dir.appendingPathComponent(".onyx/ai/prompt.md")
                if let customPrompt = try? String(contentsOf: promptFile, encoding: .utf8),
                   !customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    systemAddendum += "\n\n" + customPrompt
                }
            }

            args += ["--append-system-prompt", systemAddendum]
        } else {
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

        // Thread-safe state shared between readabilityHandler (background) and MainActor
        let state = StreamState()

        // Stream JSON lines as they arrive — each line is flushed by the CLI
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }

            // Buffer may contain partial lines; accumulate and split
            state.appendBuffer(chunk)
            let lines = state.drainLines()

            for line in lines {
                guard !line.isEmpty else { continue }
                guard let lineData = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let type = json["type"] as? String else { continue }

                // assistant message — extract tool_use from content blocks
                if type == "assistant",
                   let message = json["message"] as? [String: Any],
                   let content = message["content"] as? [[String: Any]] {
                    for block in content {
                        guard let blockType = block["type"] as? String else { continue }
                        if blockType == "tool_use", let name = block["name"] as? String {
                            state.addToolUse(ToolUseInfo(name: name, input: ""))
                            let snapshot = state.getToolUses()
                            Task { @MainActor [weak self] in
                                guard let self else { return }
                                if let i = self.messages.indices.last,
                                   self.messages[i].role == .assistant {
                                    self.messages[i].toolUses = snapshot
                                    if self.messages[i].state == .thinking {
                                        self.messages[i].state = .streaming
                                    }
                                }
                            }
                        }
                    }
                }

                // final result — contains the complete response text
                if type == "result", let resultText = json["result"] as? String {
                    state.setResult(resultText)
                    let toolUses = state.getToolUses()
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let i = self.messages.indices.last,
                           self.messages[i].role == .assistant {
                            self.messages[i].toolUses = toolUses
                        }
                        self.revealText(resultText)
                    }
                }
            }
        }

        process.terminationHandler = { [weak self] _ in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errOutput = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentProcess = nil

                // If result was already handled by stream parser, nothing to do
                if state.hasResult() { return }

                // Fallback: stream-json didn't deliver a result event
                if !errOutput.isEmpty {
                    self.updateLastAssistant("Error: \(errOutput)", state: .complete)
                    self.isLoading = false
                } else {
                    self.updateLastAssistant("No response received.", state: .complete)
                    self.isLoading = false
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

// MARK: - Thread-safe stream state for readabilityHandler

private final class StreamState: @unchecked Sendable {
    private var toolUses: [ToolUseInfo] = []
    private var resultText: String?
    private var lineBuffer: String = ""
    private let lock = NSLock()

    func addToolUse(_ info: ToolUseInfo) {
        lock.lock()
        toolUses.append(info)
        lock.unlock()
    }

    func getToolUses() -> [ToolUseInfo] {
        lock.lock()
        defer { lock.unlock() }
        return toolUses
    }

    func setResult(_ text: String) {
        lock.lock()
        resultText = text
        lock.unlock()
    }

    func hasResult() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return resultText != nil
    }

    /// Append raw data to the line buffer (may contain partial lines)
    func appendBuffer(_ text: String) {
        lock.lock()
        lineBuffer += text
        lock.unlock()
    }

    /// Extract all complete lines (terminated by \n) from the buffer
    func drainLines() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        var lines: [String] = []
        while let newlineIdx = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineIdx])
            lineBuffer = String(lineBuffer[lineBuffer.index(after: newlineIdx)...])
            lines.append(line)
        }
        return lines
    }
}
