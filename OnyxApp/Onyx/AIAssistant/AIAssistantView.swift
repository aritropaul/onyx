import SwiftUI

struct AIAssistantView: View {
    @Environment(AppState.self) private var appState
    let tabId: String
    @FocusState private var isInputFocused: Bool

    private var viewModel: AIAssistantViewModel {
        appState.aiViewModels[tabId] ?? AIAssistantViewModel()
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
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask anything...", text: inputTextBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(OnyxTheme.Colors.textPrimary)
                .lineLimit(1...8)
                .focused($isInputFocused)
                .onSubmit {
                    viewModel.sendMessage(vaultURL: appState.vaultURL)
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
                        viewModel.sendMessage(vaultURL: appState.vaultURL)
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

    private func markdownAttributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        guard var attributed = try? AttributedString(markdown: text, options: options) else {
            return AttributedString(text)
        }
        // Force 12px base font, then re-apply bold/italic/code on matching runs
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
