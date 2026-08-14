import Foundation

public final class FileProjectStore: @unchecked Sendable {
    public let rootURL: URL
    public let projectsURL: URL
    public let commons: CommonsStore
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let lineEncoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootURL: URL) throws {
        self.rootURL = rootURL
        projectsURL = rootURL.appendingPathComponent("Projects")
        commons = CommonsStore(root: rootURL.appendingPathComponent("Commons"))
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        lineEncoder = JSONEncoder()
        lineEncoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: true)
        try commons.ensure()
    }

    public func createProject(name: String, icon: String = "stone", destination: URL? = nil) throws -> ProjectManifest {
        try lock.withLock {
            let id = UUID()
            let resolvedIcon = ProjectMark.parse(icon) == nil && icon != "avatar"
                ? ProjectMark.assigned(for: id).iconValue
                : icon
            let manifest = ProjectManifest(id: id, name: name, icon: resolvedIcon)
            if let destination {
                let scoped = destination.startAccessingSecurityScopedResource()
                defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
                let dir = try Self.uniqueDirectory(in: destination, name: name)
                try ProjectLayout.create(at: dir, manifest: manifest)
                try rememberLocationUnlocked(id: id, url: dir)
            } else {
                let dir = projectsURL.appendingPathComponent(manifest.id.uuidString)
                try ProjectLayout.create(at: dir, manifest: manifest)
            }
            return manifest
        }
    }

    /// Create a project with a known id so a phone chat can land on the Mac.
    @discardableResult
    public func ensureProject(id: UUID, name: String, icon: String = "stone") throws -> ProjectManifest {
        try lock.withLock {
            if let existing = try? loadManifest(id: id) {
                return existing
            }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = trimmed.isEmpty ? "Phone" : trimmed
            let resolvedIcon = ProjectMark.parse(icon) == nil && icon != "avatar"
                ? ProjectMark.assigned(for: id).iconValue
                : icon
            let manifest = ProjectManifest(id: id, name: resolvedName, icon: resolvedIcon)
            try ProjectLayout.create(
                at: projectsURL.appendingPathComponent(id.uuidString),
                manifest: manifest
            )
            return manifest
        }
    }

    public static func folderName(from name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\").union(.newlines).union(.controlCharacters)
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    public static func uniqueDirectory(in parent: URL, name: String) throws -> URL {
        let base = folderName(from: name)
        var url = parent.appendingPathComponent(base)
        var index = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = parent.appendingPathComponent("\(base) \(index)")
            index += 1
        }
        return url
    }

    public func listProjects() throws -> [ProjectManifest] {
        try lock.withLock {
            try loadManifests().sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    public func project(id: UUID) throws -> ProjectManifest {
        try lock.withLock {
            try loadManifest(id: id)
        }
    }

    public func updateProject(_ manifest: ProjectManifest) throws {
        try lock.withLock {
            var next = manifest
            next.updatedAt = Date()
            try writeManifest(next)
        }
    }

    public func renameProject(id: UUID, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw JoyflowStoreError.io("empty name") }
        var manifest = try project(id: id)
        manifest.name = trimmed
        try updateProject(manifest)
    }

    public func setAvatar(projectID: UUID, data: Data) throws {
        guard !data.isEmpty else { throw JoyflowStoreError.io("empty avatar") }
        try lock.withLock {
            try data.write(to: layoutUnlocked(for: projectID).avatar, options: .atomic)
            var manifest = try loadManifest(id: projectID)
            manifest.icon = "avatar"
            manifest.updatedAt = Date()
            try writeManifest(manifest)
        }
    }

    public func setMark(projectID: UUID, icon: String) throws {
        guard ProjectMark.parse(icon) != nil else {
            throw JoyflowStoreError.io("unknown mark")
        }
        try lock.withLock {
            let url = layoutUnlocked(for: projectID).avatar
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            var manifest = try loadManifest(id: projectID)
            manifest.icon = icon
            manifest.updatedAt = Date()
            try writeManifest(manifest)
        }
    }

    public func clearAvatar(projectID: UUID) throws {
        try lock.withLock {
            let url = layoutUnlocked(for: projectID).avatar
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            var manifest = try loadManifest(id: projectID)
            manifest.icon = ProjectMark.assigned(for: projectID).iconValue
            manifest.updatedAt = Date()
            try writeManifest(manifest)
        }
    }

    public func avatarData(projectID: UUID) -> Data? {
        let url = layout(for: projectID).avatar
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    public func deleteProject(id: UUID) throws {
        try lock.withLock {
            let dir = layoutUnlocked(for: id).root
            guard FileManager.default.fileExists(atPath: dir.path) else {
                throw JoyflowStoreError.notFound("project \(id)")
            }
            try FileManager.default.removeItem(at: dir)
            forgetLocationUnlocked(id: id)
        }
    }

    public func layout(for id: UUID) -> ProjectLayout {
        lock.withLock { layoutUnlocked(for: id) }
    }

    /// Folder the computer jails list/read/write against.
    /// Last attached folder if one still resolves; else chosen destination `workspace/`; else an auto-created default.
    public func writeRoot(for id: UUID) throws -> URL {
        try lock.withLock {
            _ = try loadManifest(id: id)
            let layout = layoutUnlocked(for: id)
            if let attached = ResourceStore(layout: layout).resolvedFolders().last?.1 {
                return attached
            }
            let root = layout.workspace.standardizedFileURL
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            return root
        }
    }

    public func readSoul(projectID: UUID) throws -> String {
        try String(contentsOf: layout(for: projectID).soul, encoding: .utf8)
    }

    public func writeSoul(projectID: UUID, text: String) throws {
        try lock.withLock {
            try text.write(to: layoutUnlocked(for: projectID).soul, atomically: true, encoding: .utf8)
            try touch(projectID)
        }
    }

    public func readInstructions(projectID: UUID) throws -> String {
        try String(contentsOf: layout(for: projectID).instructions, encoding: .utf8)
    }

    public func writeInstructions(projectID: UUID, text: String) throws {
        try lock.withLock {
            try text.write(to: layoutUnlocked(for: projectID).instructions, atomically: true, encoding: .utf8)
            try touch(projectID)
        }
    }

    public func writeNote(projectID: UUID, title: String, body: String, tags: [String] = []) throws -> NoteRecord {
        try lock.withLock {
            let slug = uniqueSlug(NoteMarkdown.slug(from: title), in: layoutUnlocked(for: projectID).knowledge)
            let note = NoteRecord(title: title, slug: slug, body: body, tags: tags)
            try NoteMarkdown.write(note, to: layoutUnlocked(for: projectID).knowledge.appendingPathComponent("\(slug).md"))
            try touch(projectID)
            return note
        }
    }

    public func notes(projectID: UUID) throws -> [NoteRecord] {
        try NoteMarkdown.loadAll(in: layout(for: projectID).knowledge)
    }

    public func appendMemory(projectID: UUID, text: String, source: String = "user") throws -> MemoryRecord {
        try lock.withLock {
            let memory = MemoryRecord(text: text, source: source)
            try MemoryMarkdown.append(memory, to: layoutUnlocked(for: projectID).memories)
            try touch(projectID)
            return memory
        }
    }

    public func memories(projectID: UUID) throws -> [MemoryRecord] {
        try MemoryMarkdown.load(from: layout(for: projectID).memories)
    }

    public func linkedCommons(projectID: UUID) throws -> [String] {
        let data = try Data(contentsOf: layout(for: projectID).commons)
        return try decoder.decode(CommonsFile.self, from: data).linked
    }

    public func linkCommons(projectID: UUID, id: String) throws {
        try lock.withLock {
            var file = CommonsFile()
            if let data = try? Data(contentsOf: layoutUnlocked(for: projectID).commons) {
                file = try decoder.decode(CommonsFile.self, from: data)
            }
            if !file.linked.contains(id) {
                file.linked.append(id)
            }
            try encoder.encode(file).write(to: layoutUnlocked(for: projectID).commons)
            try touch(projectID)
        }
    }

    public func appendMessage(projectID: UUID, threadID: UUID, message: ChatMessageRecord) throws {
        try lock.withLock {
            let url = layoutUnlocked(for: projectID).threads.appendingPathComponent("\(threadID.uuidString).jsonl")
            let line = try lineEncoder.encode(message)
            guard let text = String(data: line, encoding: .utf8) else {
                throw JoyflowStoreError.io("encode message")
            }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: url.path) {
                try "".write(to: url, atomically: true, encoding: .utf8)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((text + "\n").utf8))
            try touch(projectID)
        }
    }

    public func messages(projectID: UUID, threadID: UUID) throws -> [ChatMessageRecord] {
        let url = layout(for: projectID).threads.appendingPathComponent("\(threadID.uuidString).jsonl")
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return raw.split(separator: "\n").compactMap { line in
            let text = String(line)
            guard !text.isEmpty else { return nil }
            return try? decoder.decode(ChatMessageRecord.self, from: Data(text.utf8))
        }
    }

    public func replaceThread(projectID: UUID, threadID: UUID, messages: [ChatMessageRecord]) throws {
        try lock.withLock {
            let url = layoutUnlocked(for: projectID).threads.appendingPathComponent("\(threadID.uuidString).jsonl")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var lines = ""
            for message in messages {
                let data = try lineEncoder.encode(message)
                guard let text = String(data: data, encoding: .utf8) else {
                    throw JoyflowStoreError.io("encode message")
                }
                lines += text + "\n"
            }
            try lines.write(to: url, atomically: true, encoding: .utf8)
            try touch(projectID)
        }
    }

    @discardableResult
    public func editUserMessage(
        projectID: UUID,
        threadID: UUID,
        id: UUID,
        text: String
    ) throws -> [ChatMessageRecord] {
        let rewritten = try ThreadEdit.apply(messages: try messages(projectID: projectID, threadID: threadID), id: id, text: text)
        try replaceThread(projectID: projectID, threadID: threadID, messages: rewritten)
        return rewritten
    }

    @discardableResult
    public func deleteMessage(projectID: UUID, threadID: UUID, id: UUID) throws -> [ChatMessageRecord] {
        let rewritten = try ThreadEdit.delete(messages: try messages(projectID: projectID, threadID: threadID), id: id)
        try replaceThread(projectID: projectID, threadID: threadID, messages: rewritten)
        return rewritten
    }

    public func listThreads(projectID: UUID) throws -> [ThreadSummary] {
        let dir = layout(for: projectID).threads
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        var result: [ThreadSummary] = []
        for file in files where file.pathExtension == "jsonl" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { continue }
            let items = (try? messages(projectID: projectID, threadID: id)) ?? []
            let modified =
                (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? items.last?.createdAt
                ?? Date()
            result.append(
                ThreadSummary(
                    id: id,
                    title: ChatCompaction.title(from: items),
                    preview: ChatCompaction.preview(from: items),
                    createdAt: items.first?.createdAt ?? modified,
                    updatedAt: items.last?.createdAt ?? modified,
                    messageCount: items.count
                )
            )
        }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func activeThreadID(projectID: UUID) -> UUID? {
        let url = layout(for: projectID).threads.appendingPathComponent("active.json")
        guard let data = try? Data(contentsOf: url),
            let file = try? decoder.decode(ActiveThreadFile.self, from: data)
        else { return nil }
        return file.id
    }

    public func setActiveThread(projectID: UUID, threadID: UUID) throws {
        try lock.withLock {
            let dir = layoutUnlocked(for: projectID).threads
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try encoder.encode(ActiveThreadFile(id: threadID))
                .write(to: dir.appendingPathComponent("active.json"), options: .atomic)
        }
    }

    public func clearThread(projectID: UUID, threadID: UUID) throws {
        try replaceThread(projectID: projectID, threadID: threadID, messages: [])
    }

    public func deleteThread(projectID: UUID, threadID: UUID) throws {
        try lock.withLock {
            let url = layoutUnlocked(for: projectID).threads.appendingPathComponent("\(threadID.uuidString).jsonl")
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            if activeThreadIDUnlocked(projectID) == threadID {
                try? FileManager.default.removeItem(
                    at: layoutUnlocked(for: projectID).threads.appendingPathComponent("active.json")
                )
            }
            try touch(projectID)
        }
    }

    public func clearAllThreads(projectID: UUID) throws {
        try lock.withLock {
            let dir = layoutUnlocked(for: projectID).threads
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files {
                try FileManager.default.removeItem(at: file)
            }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try touch(projectID)
        }
    }

    public func resolveThreadID(projectID: UUID, preferred: UUID?) -> UUID {
        if let preferred { return preferred }
        if let active = activeThreadID(projectID: projectID) { return active }
        if let latest = try? listThreads(projectID: projectID).first { return latest.id }
        return UUID()
    }

    private func activeThreadIDUnlocked(_ projectID: UUID) -> UUID? {
        let url = layoutUnlocked(for: projectID).threads.appendingPathComponent("active.json")
        guard let data = try? Data(contentsOf: url),
            let file = try? decoder.decode(ActiveThreadFile.self, from: data)
        else { return nil }
        return file.id
    }

    private func loadManifests() throws -> [ProjectManifest] {
        let fm = FileManager.default
        var seen: Set<UUID> = []
        var result: [ProjectManifest] = []
        let dirs = (try? fm.contentsOfDirectory(at: projectsURL, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for url in dirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let json = url.appendingPathComponent("project.json")
            guard fm.fileExists(atPath: json.path) else { continue }
            guard let manifest = try? decoder.decode(ProjectManifest.self, from: Data(contentsOf: json)) else { continue }
            seen.insert(manifest.id)
            result.append(manifest)
        }
        for location in readLocationsUnlocked() {
            guard !seen.contains(location.id), let url = resolveLocationUnlocked(location) else { continue }
            let json = url.appendingPathComponent("project.json")
            guard let manifest = try? decoder.decode(ProjectManifest.self, from: Data(contentsOf: json)) else { continue }
            seen.insert(manifest.id)
            result.append(manifest)
        }
        return result
    }

    private func layoutUnlocked(for id: UUID) -> ProjectLayout {
        if let location = readLocationsUnlocked().first(where: { $0.id == id }),
            let url = resolveLocationUnlocked(location)
        {
            return ProjectLayout(root: url)
        }
        return ProjectLayout(root: projectsURL.appendingPathComponent(id.uuidString))
    }

    private var locationsURL: URL {
        rootURL.appendingPathComponent("project-locations.json")
    }

    private func readLocationsUnlocked() -> [ProjectLocationRecord] {
        guard let data = try? Data(contentsOf: locationsURL),
            let file = try? decoder.decode(ProjectLocationFile.self, from: data)
        else { return [] }
        return file.items
    }

    private func writeLocationsUnlocked(_ items: [ProjectLocationRecord]) throws {
        try encoder.encode(ProjectLocationFile(items: items)).write(to: locationsURL, options: .atomic)
    }

    private func rememberLocationUnlocked(id: UUID, url: URL) throws {
        let bookmark = try? FolderBookmark.create(for: url)
        var items = readLocationsUnlocked()
        items.removeAll { $0.id == id }
        items.append(ProjectLocationRecord(id: id, path: url.path, bookmark: bookmark))
        try writeLocationsUnlocked(items)
    }

    private func forgetLocationUnlocked(id: UUID) {
        var items = readLocationsUnlocked()
        items.removeAll { $0.id == id }
        try? writeLocationsUnlocked(items)
    }

    private func resolveLocationUnlocked(_ location: ProjectLocationRecord) -> URL? {
        if let bookmark = location.bookmark, let url = FolderBookmark.resolve(bookmark) {
            return url
        }
        let url = URL(fileURLWithPath: location.path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func loadManifest(id: UUID) throws -> ProjectManifest {
        let json = layoutUnlocked(for: id).projectJSON
        guard FileManager.default.fileExists(atPath: json.path) else {
            throw JoyflowStoreError.notFound("project \(id)")
        }
        return try decoder.decode(ProjectManifest.self, from: Data(contentsOf: json))
    }

    private func writeManifest(_ manifest: ProjectManifest) throws {
        try encoder.encode(manifest).write(to: layoutUnlocked(for: manifest.id).projectJSON)
    }

    private func touch(_ id: UUID) throws {
        var manifest = try loadManifest(id: id)
        manifest.updatedAt = Date()
        try writeManifest(manifest)
    }

    private func uniqueSlug(_ base: String, in directory: URL) -> String {
        var slug = base
        var index = 2
        let fm = FileManager.default
        while fm.fileExists(atPath: directory.appendingPathComponent("\(slug).md").path) {
            slug = "\(base)-\(index)"
            index += 1
        }
        return slug
    }
}

struct ProjectLocationRecord: Codable, Sendable, Equatable {
    var id: UUID
    var path: String
    var bookmark: Data?
}

struct ProjectLocationFile: Codable, Sendable, Equatable {
    var items: [ProjectLocationRecord]
}

struct ActiveThreadFile: Codable, Sendable, Equatable {
    var id: UUID
}

