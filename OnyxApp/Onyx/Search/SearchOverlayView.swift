import SwiftUI

enum SearchMode {
    case files
    case content
}

struct SearchOverlayView: View {
    @Environment(AppState.self) private var appState
    @Binding var isVisible: Bool
    @State var mode: SearchMode
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { isVisible = false }

            VStack(spacing: 0) {
                // Search input
                HStack(spacing: 10) {
                    Image(systemName: mode == .files ? "doc.text.magnifyingglass" : "text.magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(OnyxTheme.Colors.textTertiary)

                    TextField(mode == .files ? "Search files..." : "Search content...", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(OnyxTheme.Colors.textPrimary)
                        .focused($isFocused)
                        .onSubmit { selectResult() }

                    // Mode toggle
                    Button {
                        mode = mode == .files ? .content : .files
                        selectedIndex = 0
                    } label: {
                        Text(mode == .files ? "Files" : "Content")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(OnyxTheme.Colors.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(OnyxTheme.Colors.accentSubtle, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Tab to switch mode")

                    Text("esc")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(OnyxTheme.Colors.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(OnyxTheme.Colors.surface, in: RoundedRectangle(cornerRadius: 3))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().opacity(0.2)

                // Results
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if mode == .files {
                                fileResultsList
                            } else {
                                contentResultsList
                            }
                        }
                    }
                    .frame(maxHeight: 400)
                    .onChange(of: selectedIndex) { _, idx in
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
            .frame(width: 560)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
            .padding(.top, 80)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear { isFocused = true }
        .onKeyPress(.escape) { isVisible = false; return .handled }
        .onKeyPress(.upArrow) { selectedIndex = max(0, selectedIndex - 1); return .handled }
        .onKeyPress(.downArrow) {
            let count = mode == .files ? filteredDocuments.count : contentResults.count
            selectedIndex = min(count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.tab) {
            mode = mode == .files ? .content : .files
            selectedIndex = 0
            return .handled
        }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
    }

    // MARK: - File Search

    private var filteredDocuments: [DocumentInfo] {
        let docs = appState.documents
        guard !query.isEmpty else {
            return docs.sorted { $0.updatedAt > $1.updatedAt }
        }
        let q = query.lowercased()
        return docs
            .map { doc -> (doc: DocumentInfo, score: Int) in
                let title = doc.title.lowercased()
                if title == q { return (doc, 100) }
                if title.hasPrefix(q) { return (doc, 80) }
                if title.contains(q) { return (doc, 60) }
                if fuzzyMatch(query: q, target: title) { return (doc, 40) }
                return (doc, 0)
            }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .map(\.doc)
    }

    @ViewBuilder
    private var fileResultsList: some View {
        let matches = filteredDocuments
        if matches.isEmpty && !query.isEmpty {
            noResults
        } else {
            ForEach(Array(matches.prefix(20).enumerated()), id: \.element.id) { index, doc in
                fileRow(doc: doc, isSelected: index == selectedIndex)
                    .id(index)
                    .onTapGesture {
                        appState.pendingSearchHighlight = query
                        appState.openDocument(id: doc.id)
                        isVisible = false
                    }
            }
        }
    }

    private func fileRow(doc: DocumentInfo, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? OnyxTheme.Colors.accent : OnyxTheme.Colors.textTertiary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(doc.title.isEmpty ? "Untitled" : doc.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(OnyxTheme.Colors.textPrimary)
                    .lineLimit(1)

                if !doc.projectId.isEmpty {
                    Text(doc.projectId)
                        .font(.system(size: 10))
                        .foregroundStyle(OnyxTheme.Colors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? OnyxTheme.Colors.accentSubtle : .clear)
        .contentShape(Rectangle())
    }

    // MARK: - Content Search

    private var contentResults: [RAGResult] {
        guard query.count >= 2 else { return [] }
        return appState.ragEngine.search(query: query, topK: 15)
    }

    @ViewBuilder
    private var contentResultsList: some View {
        let results = contentResults
        if results.isEmpty && query.count >= 2 {
            noResults
        } else if query.count < 2 {
            HStack {
                Text("Type at least 2 characters...")
                    .font(.system(size: 12))
                    .foregroundStyle(OnyxTheme.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            ForEach(Array(results.enumerated()), id: \.element.chunk.id) { index, result in
                contentRow(result: result, isSelected: index == selectedIndex)
                    .id(index)
                    .onTapGesture {
                        appState.pendingSearchHighlight = query
                        appState.openDocument(id: result.chunk.documentId)
                        isVisible = false
                    }
            }
        }
    }

    private func contentRow(result: RAGResult, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(OnyxTheme.Colors.accent)
                Text(result.chunk.documentTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OnyxTheme.Colors.textPrimary)
                    .lineLimit(1)
                if let heading = result.chunk.heading {
                    Text("> \(heading)")
                        .font(.system(size: 11))
                        .foregroundStyle(OnyxTheme.Colors.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Text(String(format: "%.0f%%", result.score * 100 * 60))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(OnyxTheme.Colors.textTertiary)
            }

            Text(highlightedPreview(result.chunk.content, query: query))
                .font(.system(size: 11))
                .foregroundStyle(OnyxTheme.Colors.textSecondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? OnyxTheme.Colors.accentSubtle : .clear)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    private var noResults: some View {
        HStack {
            Text("No results for \"\(query)\"")
                .font(.system(size: 12))
                .foregroundStyle(OnyxTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func selectResult() {
        appState.pendingSearchHighlight = query
        if mode == .files {
            let matches = filteredDocuments
            guard selectedIndex < matches.count else { return }
            appState.openDocument(id: matches[selectedIndex].id)
        } else {
            let results = contentResults
            guard selectedIndex < results.count else { return }
            appState.openDocument(id: results[selectedIndex].chunk.documentId)
        }
        isVisible = false
    }

    private func highlightedPreview(_ text: String, query: String) -> AttributedString {
        let preview = String(text.prefix(200))
        var attributed = AttributedString(preview)
        let q = query.lowercased()

        if let range = attributed.range(of: q, options: .caseInsensitive) {
            attributed[range].foregroundColor = NSColor(OnyxTheme.Colors.accent)
            attributed[range].font = .system(size: 11, weight: .semibold)
        }

        return attributed
    }
}
