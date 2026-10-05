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

    public init(directory: URL) throws {
        self.directory = directory
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func entries() throws -> [RecoveryEntry] {
        try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(RecoveryEntry.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }

    public func retain(_ note: Note, reason: String) throws {
        let previous = try entries().filter { $0.note.id == note.id }
        if let latest = previous.first, latest.note.hasSameContent(as: note),
           !reason.hasPrefix("Preserved") || latest.reason.hasPrefix("Preserved") { return }
        let entry = RecoveryEntry(id: UUID(), date: Date(), reason: reason, note: note)
        try JSONEncoder().encode(entry).write(to: url(for: entry.id), options: .atomic)
        // Conflict and deletion snapshots remain until the user explicitly removes them.
        let ordinary = previous.filter { !$0.reason.hasPrefix("Preserved") }
        for old in ordinary.dropFirst(max(0, limitPerNote - 1)) {
            try fm.removeItem(at: url(for: old.id))
        }
    }

    private func url(for id: UUID) -> URL { directory.appendingPathComponent("\(id).json") }
}
