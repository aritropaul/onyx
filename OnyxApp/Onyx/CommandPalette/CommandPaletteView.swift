import SwiftUI

struct CommandPaletteView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool

    private var results: [CommandItem] {
        let items = buildCommandItems()
        if searchText.isEmpty { return items }
        return items.filter { fuzzyMatch(query: searchText, target: $0.title) }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search documents, commands...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($isFocused)
                        .onSubmit { executeSelected() }
                }
                .padding(12)

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                            CommandItemRow(item: item, isSelected: index == selectedIndex)
                                .onTapGesture {
                                    selectedIndex = index
                                    executeSelected()
                                }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .frame(width: 480)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
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
        appState.isCommandPaletteVisible = false
    }

    private func executeSelected() {
        guard selectedIndex < results.count else { return }
        results[selectedIndex].action()
        dismiss()
    }

    private func buildCommandItems() -> [CommandItem] {
        var items: [CommandItem] = []

        let docs = (try? appState.database.allDocuments()) ?? []
        for doc in docs {
            items.append(CommandItem(
                id: "doc-\(doc.id)",
                title: doc.title,
                subtitle: "Document",
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
                if let projectId = appState.selectedProjectId {
                    appState.createDocument(projectId: projectId)
                }
            }
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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.callout)
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }
}
