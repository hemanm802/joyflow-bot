import Foundation

/// Bookmarks that work whether the host app is sandboxed or not.
/// `.withSecurityScope` throws on unsandboxed macOS; fall back to a plain bookmark.
public enum FolderBookmark {
    public static func create(for url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        #if os(macOS)
        if let data = try? url.bookmarkData(
            options: BookmarkAccess.creation,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return data
        }
        if let data = try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return data
        }
        #endif
        if let data = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return data
        }
        throw JoyflowStoreError.io("Could not remember that folder.")
    }

    public static func resolve(_ data: Data) -> URL? {
        let optionSets: [URL.BookmarkResolutionOptions] = [
            BookmarkAccess.resolution,
            [],
        ]
        for options in optionSets {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                return url.standardizedFileURL
            }
        }
        return nil
    }

    public static func resolve(bookmark: Data, path: String?) -> URL? {
        if let url = resolve(bookmark) {
            return existingDirectory(url)
        }
        guard let path, !path.isEmpty else { return nil }
        return existingDirectory(URL(fileURLWithPath: path))
    }

    private static func existingDirectory(_ url: URL) -> URL? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return url.standardizedFileURL
    }
}
