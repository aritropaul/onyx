import SwiftUI

struct AIAssistantView: View {
    @Environment(AppState.self) private var appState
    let tabId: String
    @FocusState private var isInputFocused: Bool

    private var viewModel: AIAssistantViewModel {
        if let existing = appState.aiViewModels[tabId] {
            return existing
        }
        let vm = AIAssistantViewModel()
        vm.tabId = tabId
        appState.aiViewModels[tabId] = vm
        return vm
    }

    private var inputTextBinding: Binding<String> {
        Binding(
            get: { viewModel.inputText },
            set: { viewModel.inputText = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.messages.isEmpty {
                emptyState
            } else {
                messageList
            }

            inputArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if appState.aiViewModels[tabId] == nil {
                let vm = AIAssistantViewModel()
                vm.tabId = tabId
                appState.aiViewModels[tabId] = vm
            }
            viewModel.tabId = tabId
            viewModel.loadIfNeeded()
            viewModel.onFirstMessage = { [tabId] title in
                if let idx = appState.openTabs.firstIndex(where: { $0.id == tabId }) {
                    appState.openTabs[idx].title = title
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(OnyxTheme.Colors.textTertiary.opacity(0.5))
            VStack(spacing: 6) {
                Text("Claude")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(OnyxTheme.Colors.textSecondary)
                Text("Ask anything about your vault")
                    .font(.system(size: 13))
                    .foregroundStyle(OnyxTheme.Colors.textTertiary)
            }
            // Tool capabilities badge
            HStack(spacing: 6) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 9))
                Text("Can read, write & search vault files")
                    .font(.system(size: 10))
            }
            .foregroundStyle(OnyxTheme.Colors.textTertiary.opacity(0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(OnyxTheme.Colors.surface, in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        messageRow(for: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 64)
                .padding(.vertical, 24)
                .frame(maxWidth: 800)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.messages.last?.content) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.messages.last?.state) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            if let lastId = viewModel.messages.last?.id {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func messageRow(for message: ChatMessage) -> some View {
        if message.role == .user {
            UserMessageView(message: message)
        } else {
            AssistantMessageView(message: message)
        }
    }

    // MARK: - Input

    private var inputArea: some View {
        VStack(spacing: 0) {
            // Context panel
            if viewModel.showContextPanel && !viewModel.lastRetrievedContext.isEmpty {
                ContextPanel(results: viewModel.lastRetrievedContext, ragEngine: appState.ragEngine)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 10) {
                // Context toggle
                Button {
                    withAnimation(OnyxTheme.Animation.quick) {
                        viewModel.showContextPanel.toggle()
                    }
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(
                            viewModel.showContextPanel
                                ? OnyxTheme.Colors.accent
                                : OnyxTheme.Colors.textTertiary.opacity(0.5)
                        )
                }
                .buttonStyle(.plain)
                .help("Show RAG context")

                TextField("Ask anything...", text: inputTextBinding, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(OnyxTheme.Colors.textPrimary)
                    .lineLimit(1...8)
                    .focused($isInputFocused)
                    .onSubmit {
                        viewModel.sendMessage(vaultURL: appState.vaultURL, ragEngine: appState.ragEngine)
                    }

                Group {
                    if viewModel.isLoading {
                        Button { viewModel.cancel() } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(OnyxTheme.Colors.destructive.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            viewModel.sendMessage(vaultURL: appState.vaultURL, ragEngine: appState.ragEngine)
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(
                                    viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                        ? OnyxTheme.Colors.textTertiary.opacity(0.3)
                                        : OnyxTheme.Colors.accent
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: viewModel.isLoading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: Capsule())
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Context Panel

private struct ContextPanel: View {
    let results: [RAGResult]
    let ragEngine: RAGEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 10))
                Text("Retrieved Context")
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                Text("\(results.count) chunks")
                    .font(.system(size: 9))
            }
            .foregroundStyle(OnyxTheme.Colors.textTertiary)

            ForEach(results, id: \.chunk.id) { result in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(result.chunk.documentTitle)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(OnyxTheme.Colors.textSecondary)
                                .lineLimit(1)
                            if let heading = result.chunk.heading {
                                Text("> \(heading)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(OnyxTheme.Colors.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        Text(result.chunk.content.prefix(80) + (result.chunk.content.count > 80 ? "..." : ""))
                            .font(.system(size: 9))
                            .foregroundStyle(OnyxTheme.Colors.textTertiary.opacity(0.7))
                            .lineLimit(1)
                    }

                    Spacer()

                    // Pin button
                    Button { ragEngine.togglePin(result.chunk.documentId) } label: {
                        Image(systemName: ragEngine.pinnedDocIds.contains(result.chunk.documentId) ? "pin.fill" : "pin")
                            .font(.system(size: 9))
                            .foregroundStyle(
                                ragEngine.pinnedDocIds.contains(result.chunk.documentId)
                                    ? OnyxTheme.Colors.accent
                                    : OnyxTheme.Colors.textTertiary
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Pin — always include in context")

                    // Exclude button
                    Button { ragEngine.toggleExclude(result.chunk.documentId) } label: {
                        Image(systemName: ragEngine.excludedDocIds.contains(result.chunk.documentId) ? "eye.slash.fill" : "eye.slash")
                            .font(.system(size: 9))
                            .foregroundStyle(
                                ragEngine.excludedDocIds.contains(result.chunk.documentId)
                                    ? OnyxTheme.Colors.destructive
                                    : OnyxTheme.Colors.textTertiary
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Exclude — never include in context")
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
        .background(OnyxTheme.Colors.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - User Message

private struct UserMessageView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            Spacer(minLength: 80)
            Text(message.content)
                .font(.system(size: 12))
                .lineSpacing(4)
                .foregroundStyle(OnyxTheme.Colors.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.08))
                )
        }
    }
}

// MARK: - Assistant Message

private struct AssistantMessageView: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Avatar
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(OnyxTheme.Colors.accent)
                Text("Claude")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OnyxTheme.Colors.textTertiary)
            }

            // Tool use — compact status line
            if !message.toolUses.isEmpty && message.state != .complete {
                HStack(spacing: 5) {
                    Image(systemName: toolIcon(message.toolUses.last!.name))
                        .font(.system(size: 9))
                        .foregroundStyle(OnyxTheme.Colors.accent.opacity(0.7))
                    Text(toolSummary(message.toolUses))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(OnyxTheme.Colors.textTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(OnyxTheme.Colors.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }

            // Content based on state
            Group {
                switch message.state {
                case .thinking:
                    ThinkingDots()
                case .streaming:
                    streamingBody
                case .complete:
                    completeBody
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var streamingBody: some View {
        HStack(alignment: .lastTextBaseline, spacing: 1) {
            Text(markdownAttributed(message.content))
                .font(.system(size: 12))
                .lineSpacing(4)
                .foregroundStyle(OnyxTheme.Colors.textPrimary)
                .textSelection(.enabled)
            BlinkingCursor()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var completeBody: some View {
        Group {
            if !message.content.isEmpty {
                Text(markdownAttributed(message.content))
                    .font(.system(size: 12))
                    .lineSpacing(4)
                    .foregroundStyle(OnyxTheme.Colors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func toolSummary(_ tools: [ToolUseInfo]) -> String {
        let counts = Dictionary(grouping: tools, by: \.name).mapValues(\.count)
        let parts = counts.sorted(by: { $0.key < $1.key }).map { name, count in
            count > 1 ? "\(name) ×\(count)" : name
        }
        let current = tools.last?.name ?? ""
        if parts.count <= 3 {
            return parts.joined(separator: " → ")
        }
        return "\(tools.count) actions · \(current)"
    }

    private func toolIcon(_ name: String) -> String {
        switch name {
        case "Read": return "doc.text"
        case "Write": return "square.and.pencil"
        case "Edit": return "pencil"
        case "Bash": return "terminal"
        case "Glob": return "magnifyingglass"
        case "Grep": return "text.magnifyingglass"
        default: return "hammer"
        }
    }

    private func markdownAttributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        guard var attributed = try? AttributedString(markdown: text, options: options) else {
            return AttributedString(text)
        }
        for run in attributed.runs {
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) {
                attributed[run.range].font = .system(size: 11, design: .monospaced)
            } else if intent.contains(.stronglyEmphasized) && intent.contains(.emphasized) {
                attributed[run.range].font = .system(size: 12, weight: .bold).italic()
            } else if intent.contains(.stronglyEmphasized) {
                attributed[run.range].font = .system(size: 12, weight: .bold)
            } else if intent.contains(.emphasized) {
                attributed[run.range].font = .system(size: 12).italic()
            } else {
                attributed[run.range].font = .system(size: 12)
            }
        }
        return attributed
    }
}

// MARK: - Thinking Dots

private struct ThinkingDots: View {
    @State private var activeDot = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(OnyxTheme.Colors.accent.opacity(i == activeDot ? 0.9 : 0.25))
                    .frame(width: 6, height: 6)
                    .scaleEffect(i == activeDot ? 1.0 : 0.75)
                    .animation(.easeInOut(duration: 0.3), value: activeDot)
            }
        }
        .padding(.vertical, 4)
        .onReceive(timer) { _ in
            activeDot = (activeDot + 1) % 3
        }
    }
}

// MARK: - Blinking Cursor

private struct BlinkingCursor: View {
    @State private var on = true
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(OnyxTheme.Colors.accent)
            .frame(width: 2, height: 13)
            .opacity(on ? 1 : 0)
            .onReceive(timer) { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    on.toggle()
                }
            }
    }
}
