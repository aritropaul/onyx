import SwiftUI

struct CommandPaletteView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool

    private var results: [CommandItem] {
        let items = buildCommandItems()
        if searchText.isEmpty { return items }
        return items
            .map { item in (item: item, score: fuzzyScore(query: searchText, target: item.title)) }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .map(\.item)
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .transition(.opacity)
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                // Search input
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(OnyxTheme.Colors.textTertiary)

                    TextField("Search documents, commands...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .foregroundStyle(OnyxTheme.Colors.textPrimary)
                        .focused($isFocused)
                        .onSubmit { executeSelected() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                // Subtle divider
                Rectangle()
                    .fill(OnyxTheme.Colors.border)
                    .frame(height: 1)

                // Results
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                CommandItemRow(item: item, isSelected: index == selectedIndex)
                                    .id(index)
                                    .onTapGesture {
                                        selectedIndex = index
                                        executeSelected()
                                    }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 340)
                    .onChange(of: selectedIndex) { _, idx in
                        withAnimation(OnyxTheme.Animation.quick) {
                            proxy.scrollTo(idx, anchor: .center)
                        }
                    }
                }
            }
            .frame(width: 520)
            .background(Color(white: 0.11))
            .clipShape(RoundedRectangle(cornerRadius: OnyxTheme.Radius.xl))
            .overlay(
                RoundedRectangle(cornerRadius: OnyxTheme.Radius.xl)
                    .stroke(OnyxTheme.Colors.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
            .padding(.top, 100)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear { isFocused = true }
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(results.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onChange(of: searchText) { _, _ in selectedIndex = 0 }
    }

    private func dismiss() {
        withAnimation(OnyxTheme.Animation.standard) {
            appState.isCommandPaletteVisible = false
        }
    }

    private func executeSelected() {
        guard selectedIndex < results.count else { return }
        let item = results[selectedIndex]
        // Set highlight for document opens
        if item.id.hasPrefix("doc-") && !searchText.isEmpty {
            appState.pendingSearchHighlight = searchText
        }
        item.action()
        dismiss()
    }

    private func buildCommandItems() -> [CommandItem] {
        var items: [CommandItem] = []

        // Use provider documents (vault-aware) instead of database-only
        let docs = appState.documents
        for doc in docs {
            items.append(CommandItem(
                id: "doc-\(doc.id)",
                title: doc.title.isEmpty ? "Untitled" : doc.title,
                subtitle: doc.projectId.isEmpty ? "Document" : doc.projectId,
                icon: "doc.text",
                action: { appState.openDocument(id: doc.id) }
            ))
        }

        items.append(CommandItem(
            id: "cmd-new-doc",
            title: "New Document",
            subtitle: "Command",
            icon: "plus",
            action: {
                if let projectId = appState.selectedProjectId ?? appState.projects.first?.id {
                    appState.createDocument(projectId: projectId)
                }
            }
        ))

        items.append(CommandItem(
            id: "cmd-new-ai",
            title: "New Claude Chat",
            subtitle: "Command",
            icon: "sparkles",
            action: { appState.openAITab() }
        ))

        items.append(CommandItem(
            id: "cmd-settings",
            title: "Settings",
            subtitle: "Command",
            icon: "gearshape",
            action: { appState.openSettings() }
        ))

        return items
    }
}

struct CommandItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void
}

struct CommandItemRow: View {
    let item: CommandItem
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? OnyxTheme.Colors.accent : OnyxTheme.Colors.textTertiary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: OnyxTheme.Radius.sm)
                        .fill(isSelected ? OnyxTheme.Colors.accentSubtle : .clear)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(OnyxTheme.Colors.textPrimary)
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(OnyxTheme.Colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            if isSelected {
                Text("↵")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OnyxTheme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: OnyxTheme.Radius.md)
                .fill(isSelected ? OnyxTheme.Colors.surfaceSelected :
                      isHovered ? OnyxTheme.Colors.surfaceHover : .clear)
                .animation(OnyxTheme.Animation.quick, value: isHovered)
        )
        .padding(.horizontal, 6)
        .contentShape(RoundedRectangle(cornerRadius: OnyxTheme.Radius.md))
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
