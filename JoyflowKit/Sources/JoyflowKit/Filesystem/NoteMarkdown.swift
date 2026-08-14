import Foundation

enum NoteMarkdown {
    static func write(_ note: NoteRecord, to url: URL) throws {
        let tags = note.tags.joined(separator: ",")
        let header = "<!-- joyflow id=\(note.id.uuidString) tags=\(tags) -->\n"
        let body = note.body.trimmingCharacters(in: .newlines)
        let text = header + "# \(note.title)\n\n" + body + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func read(from url: URL) throws -> NoteRecord {
        let raw = try String(contentsOf: url, encoding: .utf8)
        var id = UUID()
        var tags: [String] = []
        var lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let first = lines.first, first.hasPrefix("<!-- joyflow") || first.hasPrefix("<!-- cairn") {
            if let parsed = parseHeader(first) {
                id = parsed.id
                tags = parsed.tags
            }
            lines.removeFirst()
            if lines.first == "" { lines.removeFirst() }
        }
        var title = url.deletingPathExtension().lastPathComponent
        if let heading = lines.first, heading.hasPrefix("# ") {
            title = String(heading.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            lines.removeFirst()
            if lines.first == "" { lines.removeFirst() }
        }
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        return NoteRecord(
            id: id,
            title: title,
            slug: url.deletingPathExtension().lastPathComponent,
            body: body,
            tags: tags,
            updatedAt: values.contentModificationDate ?? Date()
        )
    }

    static func loadAll(in directory: URL) throws -> [NoteRecord] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return try items
            .filter { $0.pathExtension == "md" && $0.lastPathComponent != "memories.md" }
            .map { try read(from: $0) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func parseHeader(_ line: String) -> (id: UUID, tags: [String])? {
        let trimmed = line.replacingOccurrences(of: "<!--", with: "")
            .replacingOccurrences(of: "-->", with: "")
            .trimmingCharacters(in: .whitespaces)
        var id = UUID()
        var tags: [String] = []
        for part in trimmed.split(separator: " ") {
            let piece = String(part)
            if piece.hasPrefix("id="), let parsed = UUID(uuidString: String(piece.dropFirst(3))) {
                id = parsed
            } else if piece.hasPrefix("tags=") {
                let raw = String(piece.dropFirst(5))
                tags = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
        }
        return (id, tags)
    }

    static func slug(from title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let dashed = title.lowercased().replacingOccurrences(of: " ", with: "-")
        let scalars = dashed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let slug = String(scalars)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "note" : slug
    }
}

enum MemoryMarkdown {
    static func append(_ memory: MemoryRecord, to url: URL) throws {
        var existing = (try? String(contentsOf: url, encoding: .utf8)) ?? "# Memories\n\n"
        if !existing.hasSuffix("\n") { existing += "\n" }
        let stamp = ISO8601DateFormatter().string(from: memory.createdAt)
        existing += "## \(stamp) (\(memory.source))\n\n\(memory.text)\n\n"
        try existing.write(to: url, atomically: true, encoding: .utf8)
    }

    static func load(from url: URL) throws -> [MemoryRecord] {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var records: [MemoryRecord] = []
        let blocks = raw.components(separatedBy: "\n## ")
        for (index, block) in blocks.enumerated() {
            if index == 0 { continue }
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let header = lines.first else { continue }
            let body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let stamp = header.split(separator: " ").first.map(String.init) ?? ""
            let source: String
            if header.contains("(model)") {
                source = "model"
            } else {
                source = "user"
            }
            let date = ISO8601DateFormatter().date(from: stamp) ?? Date()
            if !body.isEmpty {
                records.append(MemoryRecord(text: body, createdAt: date, source: source))
            }
        }
        return records
    }
}
