import Foundation

public struct RecoveryEntry: Codable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var reason: String
    public var note: Note
}

/// Local to this Mac; never placed inside the synchronized notes directory.
public final class RecoveryStore {
    public let directory: URL
    public var limitPerNote = 30
    private let fm = FileManager.default
    private let read: (URL) throws -> Data
    private var cachedEntries: [RecoveryEntry]?

    public convenience init(directory: URL) throws {
        try self.init(directory: directory, read: { try Data(contentsOf: $0) })
    }

    init(directory: URL, read: @escaping (URL) throws -> Data) throws {
        self.directory = directory
        self.read = read
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func entries() throws -> [RecoveryEntry] {
        if let cachedEntries { return cachedEntries }
        let loaded: [RecoveryEntry] = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> RecoveryEntry? in
                guard let data = try? read(url) else { return nil }
                return try? JSONDecoder().decode(RecoveryEntry.self, from: data)
            }
            .sorted { $0.date > $1.date }
        cachedEntries = loaded
        return loaded
    }

    public func retain(_ note: Note, reason: String) throws {
        var all = try entries()
        let previous = all.filter { $0.note.id == note.id }
        if let latest = previous.first, latest.note.hasSameContent(as: note),
           !reason.hasPrefix("Preserved") || latest.reason.hasPrefix("Preserved") { return }
        let entry = RecoveryEntry(id: UUID(), date: Date(), reason: reason, note: note)
        do {
            try JSONEncoder().encode(entry).write(to: url(for: entry.id), options: .atomic)
            all.append(entry)
            // Conflict and deletion snapshots remain until the user explicitly removes them.
            let ordinary = previous.filter { !$0.reason.hasPrefix("Preserved") }
            for old in ordinary.dropFirst(max(0, limitPerNote - 1)) {
                try fm.removeItem(at: url(for: old.id))
                all.removeAll { $0.id == old.id }
            }
            cachedEntries = all.sorted { $0.date > $1.date }
        } catch {
            // Reload on the next access if a partial write or prune changed the directory.
            cachedEntries = nil
            throw error
        }
    }

    private func url(for id: UUID) -> URL { directory.appendingPathComponent("\(id).json") }
}
