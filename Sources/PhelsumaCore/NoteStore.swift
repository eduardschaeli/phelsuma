import Foundation

public enum StoreError: Error, LocalizedError {
    case folderUnavailable, unknownNote, removedWhileEditing, duplicateID, identityChanged
    public var errorDescription: String? {
        switch self {
        case .folderUnavailable: "The notes folder is unavailable. Your open notes have been kept."
        case .unknownNote: "This note is no longer open."
        case .removedWhileEditing: "The file was removed while you were editing. Your text is saved in Recover Notes."
        case .duplicateID: "Two files have the same note ID. Neither file has been changed."
        case .identityChanged: "The file's note ID changed externally. Your edits remain unsaved; the file was not overwritten."
        }
    }
}

public struct StoreIssue: Identifiable {
    public var id: String { path }
    public let path: String
    public let message: String
}

public enum SaveResult: Equatable {
    case unchanged, saved, conflict(UUID)
}

/// Call from one serialized owner (the app's main actor). No background save races.
public final class NoteStore {
    private struct Session {
        var note: Note
        var base: Note
        var bytes: Data
        var url: URL
        var dirty: Bool { !note.hasSameContent(as: base) }
    }

    public let directory: URL
    public let recovery: RecoveryStore
    public private(set) var issues: [StoreIssue] = []
    private var sessions: [UUID: Session] = [:]
    private var duplicateIDs: Set<UUID> = []
    private let fm = FileManager.default
    /// Injectable replacement for deterministic failure and race tests.
    private let write: (Data, URL) throws -> Void

    public init(directory: URL, recovery: RecoveryStore,
                write: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) throws {
        self.directory = directory
        self.recovery = recovery
        self.write = write
        try ensureDirectory()
    }

    public var notes: [Note] { sessions.values.map(\.note).sorted { $0.createdAt < $1.createdAt } }
    public var dirtyIDs: [UUID] { sessions.filter { $0.value.dirty }.map(\.key) }
    public func note(_ id: UUID) -> Note? { sessions[id]?.note }

    private func ensureDirectory() throws {
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw StoreError.folderUnavailable
        }
    }

    @discardableResult public func create(body: String = "", color: NoteColor = .yellow) throws -> Note {
        try ensureDirectory()
        let note = Note(color: color, body: body)
        let data = try NoteCodec.encode(note)
        let url = directory.appendingPathComponent("\(note.id).md")
        try recovery.retain(note, reason: "Created")
        try write(data, url)
        sessions[note.id] = Session(note: note, base: note, bytes: data, url: url)
        return note
    }

    public func edit(_ id: UUID, body: String? = nil, color: NoteColor? = nil) {
        guard var session = sessions[id] else { return }
        if let body { session.note.body = body }
        if let color { session.note.color = color }
        sessions[id] = session
    }

    @discardableResult public func save(_ id: UUID) throws -> SaveResult {
        guard var session = sessions[id] else { throw StoreError.unknownNote }
        guard !duplicateIDs.contains(id) else { throw StoreError.duplicateID }
        guard session.dirty else { return .unchanged }
        try ensureDirectory()
        let disk: Data
        do { disk = try Data(contentsOf: session.url) }
        catch {
            if (error as NSError).code == NSFileReadNoSuchFileError {
                try recovery.retain(session.note, reason: "Preserved edit after deletion")
                sessions.removeValue(forKey: id)
                throw StoreError.removedWhileEditing
            }
            throw error
        }
        if disk != session.bytes {
            let incoming = try NoteCodec.decode(disk)
            guard incoming.id == id else { throw StoreError.identityChanged }
            if incoming.hasSameContent(as: session.note) {
                sessions[id] = Session(note: incoming, base: incoming, bytes: disk, url: session.url)
                return .unchanged
            }
            return try preserveConflict(id, incoming: incoming, data: disk)
        }
        session.note.modifiedAt = Date()
        let data = try NoteCodec.encode(session.note)
        try recovery.retain(session.base, reason: "Before edit")
        try recovery.retain(session.note, reason: "Saved edit")
        try write(data, session.url)
        session.base = session.note
        session.bytes = data
        sessions[id] = session
        return .saved
    }

    private func preserveConflict(_ id: UUID, incoming: Note, data: Data) throws -> SaveResult {
        guard let session = sessions[id] else { throw StoreError.unknownNote }
        try recovery.retain(session.note, reason: "Preserved conflicting edit")
        // A new identity makes the second copy an independent sticky on all devices.
        let copy = try create(body: session.note.body, color: session.note.color)
        sessions[id] = Session(note: incoming, base: incoming, bytes: data, url: session.url)
        return .conflict(copy.id)
    }

    /// A failed directory enumeration never implies an empty folder.
    @discardableResult public func refresh() throws -> [UUID] {
        try ensureDirectory()
        let urls = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                             options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "md" }
        var found: [UUID: [(Note, Data, URL)]] = [:]
        var unreadable = Set<String>()
        duplicateIDs = []
        issues = []
        for url in urls {
            do {
                let data = try Data(contentsOf: url)
                let note = try NoteCodec.decode(data)
                found[note.id, default: []].append((note, data, url))
            } catch {
                unreadable.insert(url.standardizedFileURL.path)
                issues.append(StoreIssue(path: url.path, message: error.localizedDescription))
            }
        }
        var conflicts: [UUID] = []
        for (id, items) in found {
            guard items.count == 1, let (incoming, data, url) = items.first else {
                duplicateIDs.insert(id)
                issues.append(StoreIssue(path: items[0].2.path, message: StoreError.duplicateID.localizedDescription))
                continue
            }
            if let current = sessions[id] {
                if current.bytes == data {
                    sessions[id]?.url = url
                    continue
                }
                if current.dirty && !current.note.hasSameContent(as: incoming) {
                    // Use the discovered location in case the file was renamed.
                    sessions[id]?.url = url
                    if case .conflict(let newID) = try preserveConflict(id, incoming: incoming, data: data) {
                        conflicts.append(newID)
                    }
                    continue
                }
                try recovery.retain(current.note, reason: "Before external update")
            }
            sessions[id] = Session(note: incoming, base: incoming, bytes: data, url: url)
            try recovery.retain(incoming, reason: "Loaded")
        }
        // New conflict copies were created during this scan and aren't in `found`.
        let created = Set(conflicts)
        for (id, session) in Array(sessions) where found[id] == nil && !created.contains(id) {
            guard !unreadable.contains(session.url.standardizedFileURL.path) else { continue }
            // A file whose ID was externally changed still exists; don't discard pending edits.
            if urls.contains(where: { $0.standardizedFileURL.path == session.url.standardizedFileURL.path }) { continue }
            try recovery.retain(session.note, reason: "Preserved externally deleted note")
            if session.dirty {
                issues.append(StoreIssue(path: session.url.path, message: StoreError.removedWhileEditing.localizedDescription))
            }
            sessions.removeValue(forKey: id)
        }
        return conflicts
    }

    public func delete(_ id: UUID) throws {
        guard !duplicateIDs.contains(id) else { throw StoreError.duplicateID }
        guard let session = sessions[id] else { throw StoreError.unknownNote }
        try ensureDirectory()
        let data = try Data(contentsOf: session.url)
        let disk = try NoteCodec.decode(data)
        guard disk.id == id else { throw StoreError.identityChanged }
        try recovery.retain(disk, reason: "Preserved deleted note")
        try recovery.retain(session.note, reason: "Preserved deleted note")
        try fm.removeItem(at: session.url)
        sessions.removeValue(forKey: id)
    }

    public func restore(_ entry: RecoveryEntry) throws -> Note {
        try create(body: entry.note.body, color: entry.note.color)
    }

    public func importText(at url: URL) throws -> Note {
        let data = try Data(contentsOf: url)
        if let note = try? NoteCodec.decode(data) { return try create(body: note.body, color: note.color) }
        guard let text = String(data: data, encoding: .utf8) else { throw NoteFormatError.invalidUTF8 }
        if text.hasPrefix(NoteCodec.prefix) { _ = try NoteCodec.decode(data) }
        return try create(body: text)
    }
}
