import Foundation

enum BookmarkManager {
    private static let bookmarkKey = "com.onyx.vault.bookmark"
    private static let pathKey = "com.onyx.vault.path"

    static func saveBookmark(for url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
        UserDefaults.standard.set(url.path, forKey: pathKey)
    }

    static func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale {
            // Re-save if stale
            try? saveBookmark(for: url)
        }

        return url
    }

    static func startAccessing() -> URL? {
        guard let url = resolveBookmark() else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        return url
    }

    static func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    static var hasBookmark: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    static var savedPath: String? {
        UserDefaults.standard.string(forKey: pathKey)
    }

    static func clearBookmark() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: pathKey)
    }
}
