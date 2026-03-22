import SwiftUI

// MARK: - Preference keys for tracking tab geometry

private struct ActiveTabFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct VisibleFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct TabBarView: View {
    @Environment(AppState.self) private var appState
    @State private var hoveredTabId: String?
    @State private var activeTabFrame: CGRect = .zero
    @State private var visibleFrame: CGRect = .zero

    private enum StickyEdge {
        case leading, trailing
    }

    private var stickyEdge: StickyEdge? {
        guard activeTabFrame.width > 0, visibleFrame.width > 0 else { return nil }
        if activeTabFrame.maxX < visibleFrame.minX + 1 { return .leading }
        if activeTabFrame.minX > visibleFrame.maxX - 1 { return .trailing }
        return nil
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: stickyEdge == .trailing ? .trailing : .leading) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(appState.openTabs) { tab in
                                let isActiveTab = appState.activeTabId == tab.id
                                tabItem(tab: tab)
                                    .id(tab.id)
                                    .fixedSize()
                                    .opacity(stickyEdge != nil && isActiveTab ? 0 : 1)
                                    .transition(.opacity)
                                    .background(
                                        GeometryReader { geo in
                                            if isActiveTab {
                                                Color.clear.preference(
                                                    key: ActiveTabFrameKey.self,
                                                    value: geo.frame(in: .named("tabBar"))
                                                )
                                            }
                                        }
                                    )
                            }
                        }
                        .animation(OnyxTheme.Animation.quick, value: appState.openTabs)
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: VisibleFrameKey.self,
                                value: geo.frame(in: .named("tabBar"))
                            )
                        }
                    )
                    .onPreferenceChange(ActiveTabFrameKey.self) { activeTabFrame = $0 }
                    .onPreferenceChange(VisibleFrameKey.self) { visibleFrame = $0 }
                    .onChange(of: appState.activeTabId) { _, newId in
                        if let id = newId {
                            withAnimation(OnyxTheme.Animation.quick) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }

                // Sticky active tab pinned to edge
                if stickyEdge != nil,
                   let tab = appState.openTabs.first(where: { $0.id == appState.activeTabId }) {
                    tabItem(tab: tab)
                        .fixedSize()
                        .shadow(color: .black.opacity(0.3), radius: 4, x: stickyEdge == .leading ? 2 : -2)
                }
            }
            .coordinateSpace(name: "tabBar")

            // New tab button
            Button {
                appState.openNewTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(OnyxTheme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .glassEffect(.regular, in: Circle())
            }
            .buttonStyle(.plain)
            .help("New Tab (⌘T)")
            .padding(.trailing, 6)
        }
        .padding(.top, 6)
        .padding(.bottom, 0)
    }

    private func tabItem(tab: TabItem) -> some View {
        let isActive = appState.activeTabId == tab.id
        let isHovered = hoveredTabId == tab.id

        return Button {
            appState.activeTabId = tab.id
        } label: {
            HStack(spacing: 6) {
                if tab.kind == .ai {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isActive ? OnyxTheme.Colors.accent : OnyxTheme.Colors.textTertiary)
                }
                Text(tab.title.isEmpty ? "Untitled" : tab.title)
                    .font(.system(size: 12))
                    .foregroundStyle(isActive ? OnyxTheme.Colors.textPrimary : OnyxTheme.Colors.textTertiary)
                    .lineLimit(1)

                if isActive || isHovered {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(OnyxTheme.Colors.textTertiary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appState.closeTab(id: tab.id)
                        }
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Capsule())
            .glassEffect(.regular, in: Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .onHover { hovering in
            withAnimation(OnyxTheme.Animation.quick) {
                hoveredTabId = hovering ? tab.id : nil
            }
        }
        .animation(OnyxTheme.Animation.quick, value: isActive)
        .contextMenu {
            Button("Close") { appState.closeTab(id: tab.id) }
            Button("Close Others") { appState.closeOtherTabs(except: tab.id) }
        }
    }
}
