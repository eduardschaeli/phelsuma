import Foundation
import Testing
@testable import PhelsumaCore

final class Fixture {
    let root: URL
    let folder: URL
    let recovery: RecoveryStore
    let store: NoteStore
    init(write: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        folder = root.appendingPathComponent("Notes")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        recovery = try RecoveryStore(directory: root.appendingPathComponent("Recovery"))
        store = try NoteStore(directory: folder, recovery: recovery, write: write)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func url(_ id: UUID) -> URL { folder.appendingPathComponent("\(id).md") }
    func external(_ note: Note, body: String) throws {
        var incoming = note
        incoming.body = body
        try NoteCodec.encode(incoming).write(to: url(note.id), options: .atomic)
    }
}

@Test func codecPreservesBodies() throws {
    for body in ["", "# Heading\n**bold** 🦎 café 日本語\n", "<!-- a comment -->\r\n[link](url)\n~~~unknown"] {
        let note = Note(body: body, now: Date(timeIntervalSince1970: 123))
        #expect(try NoteCodec.decode(NoteCodec.encode(note)) == note)
    }
}

@Test func rejectsUnknownSchemaAndInvalidData() throws {
    let bytes = try NoteCodec.encode(Note(body: "keep me"))
    let changed = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "\"version\":1", with: "\"version\":99")
    #expect(throws: NoteFormatError.self) { try NoteCodec.decode(Data(changed.utf8)) }
    #expect(throws: NoteFormatError.self) { try NoteCodec.decode(Data([0xff])) }
}

@Test func idleSaveNeverRewritesOrOverwritesIncoming() throws {
    let f = try Fixture()
    let note = try f.store.create(body: "original")
    try f.external(note, body: "from other laptop")
    let before = try Data(contentsOf: f.url(note.id))
    let attributes = try FileManager.default.attributesOfItem(atPath: f.url(note.id).path)
    #expect(try f.store.save(note.id) == .unchanged)
    #expect(try Data(contentsOf: f.url(note.id)) == before)
    #expect(try FileManager.default.attributesOfItem(atPath: f.url(note.id).path)[.modificationDate] as? Date == attributes[.modificationDate] as? Date)
    try f.store.refresh()
    #expect(f.store.note(note.id)?.body == "from other laptop")
}

@Test func conflictRetainsBothVersionsAndIsIdempotent() throws {
    let f = try Fixture()
    let note = try f.store.create(body: "base")
    f.store.edit(note.id, body: "local")
    try f.external(note, body: "remote")
    guard case .conflict(let copy) = try f.store.save(note.id) else { Issue.record("Expected conflict"); return }
    #expect(f.store.note(copy)?.body == "local")
    #expect(try NoteCodec.decode(Data(contentsOf: f.url(note.id))).body == "remote")
    try f.store.refresh()
    try f.store.refresh()
    #expect(f.store.notes.count == 2)
    let restarted = try NoteStore(directory: f.folder, recovery: f.recovery)
    try restarted.refresh()
    #expect(Set(restarted.notes.map(\.body)) == ["local", "remote"])
}

@Test func refreshDetectsConflictWithSameSizeAndTimestamp() throws {
    let f = try Fixture()
    let note = try f.store.create(body: "aaaa")
    let attributes = try FileManager.default.attributesOfItem(atPath: f.url(note.id).path)
    f.store.edit(note.id, body: "cccc")
    try f.external(note, body: "bbbb")
    try FileManager.default.setAttributes([.modificationDate: attributes[.modificationDate]!], ofItemAtPath: f.url(note.id).path)
    #expect(try f.store.refresh().count == 1)
    #expect(Set(f.store.notes.map(\.body)) == ["bbbb", "cccc"])
}

@Test func identicalEditsDoNotConflict() throws {
    let f = try Fixture()
    let note = try f.store.create(body: "base")
    f.store.edit(note.id, body: "same")
    try f.external(note, body: "same")
    #expect(try f.store.save(note.id) == .unchanged)
    #expect(f.store.notes.count == 1)
    #expect(f.store.dirtyIDs.isEmpty)
}

@Test func lateArrivalAfterSaveHasLocalRecovery() throws {
    let f = try Fixture()
    let note = try f.store.create(body: "base")
    f.store.edit(note.id, body: "local saved")
    try f.store.save(note.id)
    try f.external(note, body: "late remote")
    try f.store.refresh()
    #expect(f.store.note(note.id)?.body == "late remote")
    #expect(try f.recovery.entries().contains { $0.note.body == "local saved" })
}

@Test func failureKeepsPendingEditsAndOldFile() throws {
    enum Failure: Error { case diskFull }
    var fail = false
    let f = try Fixture { data, url in
        if fail { throw Failure.diskFull }
        try data.write(to: url, options: .atomic)
    }
    let note = try f.store.create(body: "old")
    f.store.edit(note.id, body: "pending")
    fail = true
    #expect(throws: Failure.self) { try f.store.save(note.id) }
    #expect(f.store.note(note.id)?.body == "pending")
    #expect(f.store.dirtyIDs == [note.id])
    #expect(try NoteCodec.decode(Data(contentsOf: f.url(note.id))).body == "old")
}

@Test func deletionWithPendingEditDoesNotResurrect() throws {
    let f = try Fixture()
    let note = try f.store.create(body: "old")
    f.store.edit(note.id, body: "pending")
    try FileManager.default.removeItem(at: f.url(note.id))
    try f.store.refresh()
    #expect(f.store.note(note.id) == nil)
    #expect(!FileManager.default.fileExists(atPath: f.url(note.id).path))
    #expect(try f.recovery.entries().contains { $0.note.body == "pending" })
}

@Test func unavailableFolderAndMalformedFileRetainState() throws {
    let f = try Fixture()
    let note = try f.store.create(body: "safe")
    try Data("broken".utf8).write(to: f.url(note.id))
    try f.store.refresh()
    #expect(f.store.note(note.id)?.body == "safe")
    #expect(f.store.issues.count == 1)
    let moved = f.root.appendingPathComponent("Away")
    try FileManager.default.moveItem(at: f.folder, to: moved)
    #expect(throws: StoreError.self) { try f.store.refresh() }
    #expect(f.store.notes.count == 1)
}

@Test func duplicateIDsAreNotOverwritten() throws {
    let f = try Fixture()
    let note = try f.store.create(body: "safe")
    try FileManager.default.copyItem(at: f.url(note.id), to: f.folder.appendingPathComponent("duplicate.md"))
    try f.store.refresh()
    #expect(f.store.issues.count == 1)
    #expect(f.store.notes.count == 1)
    f.store.edit(note.id, body: "pending")
    #expect(throws: StoreError.self) { try f.store.save(note.id) }
    #expect(throws: StoreError.self) { try f.store.delete(note.id) }
}

@Test func importAndRecoverDeletion() throws {
    let f = try Fixture()
    let source = f.root.appendingPathComponent("import.md")
    try Data("# Imported\n😀".utf8).write(to: source)
    let note = try f.store.importText(at: source)
    try f.store.delete(note.id)
    #expect(f.store.notes.isEmpty)
    let entry = try #require(f.recovery.entries().first { $0.note.id == note.id })
    let restored = try f.store.restore(entry)
    #expect(restored.id != note.id)
    #expect(restored.body == "# Imported\n😀")
}

@Test func twoFoldersSimulateDeviceHandoff() throws {
    let a = try Fixture()
    let b = try Fixture()
    let note = try a.store.create(body: "base")
    try FileManager.default.copyItem(at: a.url(note.id), to: b.url(note.id))
    try b.store.refresh()
    a.store.edit(note.id, body: "A edit")
    try a.store.save(note.id)
    b.store.edit(note.id, body: "B edit")
    try Data(contentsOf: a.url(note.id)).write(to: b.url(note.id), options: .atomic)
    try b.store.refresh()
    #expect(Set(b.store.notes.map(\.body)) == ["A edit", "B edit"])
}

@Test func recoveryDeduplicatesTimestampRoundingButProtectsDeletion() throws {
    let f = try Fixture()
    let note = try f.store.create(body: "same content")
    let reloaded = try NoteCodec.decode(Data(contentsOf: f.url(note.id)))
    try f.recovery.retain(reloaded, reason: "Loaded")
    #expect(try f.recovery.entries().count == 1)
    try f.store.delete(note.id)
    let entries = try f.recovery.entries()
    #expect(entries.count == 2)
    #expect(entries.first?.reason == "Preserved deleted note")
}

@Test func saveAfterExternalDeletionPreservesPendingText() throws {
    let f = try Fixture()
    let note = try f.store.create(body: "base")
    f.store.edit(note.id, body: "unsaved")
    try FileManager.default.removeItem(at: f.url(note.id))
    #expect(throws: StoreError.self) { try f.store.save(note.id) }
    #expect(f.store.note(note.id) == nil)
    #expect(try f.recovery.entries().contains { $0.note.body == "unsaved" })
    #expect(!FileManager.default.fileExists(atPath: f.url(note.id).path))
}

@Test func unrelatedNotesAndRapidEditsDoNotRewriteStaleData() throws {
    let f = try Fixture()
    let first = try f.store.create(body: "one")
    let second = try f.store.create(body: "two")
    let original = try Data(contentsOf: f.url(second.id))
    for number in 0..<50 { f.store.edit(first.id, body: "edit \(number)") }
    try f.store.save(first.id)
    #expect(try NoteCodec.decode(Data(contentsOf: f.url(first.id))).body == "edit 49")
    #expect(try Data(contentsOf: f.url(second.id)) == original)
    #expect(f.store.dirtyIDs.isEmpty)
}

@Test func renamedNoteWithPendingEditsSavesAtNewLocation() throws {
    let f = try Fixture()
    let note = try f.store.create(body: "old")
    f.store.edit(note.id, body: "pending")
    let renamed = f.folder.appendingPathComponent("renamed.md")
    try FileManager.default.moveItem(at: f.url(note.id), to: renamed)
    try f.store.refresh()
    try f.store.save(note.id)
    #expect(try NoteCodec.decode(Data(contentsOf: renamed)).body == "pending")
    #expect(!FileManager.default.fileExists(atPath: f.url(note.id).path))
}

@Test func protectedRecoverySurvivesOrdinaryHistoryPruning() throws {
    let f = try Fixture()
    f.recovery.limitPerNote = 3
    var note = Note(body: "conflicting content")
    try f.recovery.retain(note, reason: "Preserved conflict")
    for index in 0..<10 {
        note.body = "revision \(index)"
        try f.recovery.retain(note, reason: "Saved edit")
    }
    let entries = try f.recovery.entries()
    #expect(entries.filter { !$0.reason.hasPrefix("Preserved") }.count == 3)
    #expect(entries.contains { $0.note.body == "conflicting content" })
    #expect(entries.contains { $0.note.body == "revision 9" })
}

@Test func malformedIncomingFileCannotBeOverwrittenBySave() throws {
    let f = try Fixture()
    let note = try f.store.create(body: "base")
    f.store.edit(note.id, body: "local edits")
    let malformed = Data("<!-- phelsuma\nbroken metadata".utf8)
    try malformed.write(to: f.url(note.id))
    #expect(throws: NoteFormatError.self) { try f.store.save(note.id) }
    #expect(try Data(contentsOf: f.url(note.id)) == malformed)
    #expect(f.store.note(note.id)?.body == "local edits")
    #expect(f.store.dirtyIDs == [note.id])
}

@Test func preSaveComparisonDoesNotClaimToLockOutUnseenWriters() throws {
    var injectRace = false
    let f = try Fixture { data, url in
        if injectRace {
            var unseen = try NoteCodec.decode(Data(contentsOf: url))
            unseen.body = "unseen intervening write"
            try NoteCodec.encode(unseen).write(to: url, options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }
    let note = try f.store.create(body: "base")
    f.store.edit(note.id, body: "known local edit")
    injectRace = true
    try f.store.save(note.id)
    let entries = try f.recovery.entries()
    #expect(entries.contains { $0.note.body == "known local edit" })
    #expect(entries.contains { $0.note.body == "base" })
    // Explicit limitation: the local check is not a lock against a provider's later write.
    #expect(!entries.contains { $0.note.body == "unseen intervening write" })
}
