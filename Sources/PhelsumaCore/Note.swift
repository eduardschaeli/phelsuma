import Foundation

public enum NoteColor: String, Codable, CaseIterable, Sendable {
    case yellow, blue, green, pink, purple, gray
}

public struct Note: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var color: NoteColor
    public var createdAt: Date
    public var modifiedAt: Date
    public var body: String

    public init(id: UUID = UUID(), color: NoteColor = .yellow, body: String = "", now: Date = Date()) {
        self.id = id
        self.color = color
        self.body = body
        createdAt = now
        modifiedAt = now
    }

    public var title: String {
        let firstLine = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? "New Note"
        return String(firstLine.prefix(80))
    }

    public func hasSameContent(as other: Note) -> Bool {
        id == other.id && color == other.color && body == other.body
    }
}

public enum NoteFormatError: Error, LocalizedError {
    case missingHeader, invalidUTF8, invalidHeader, unsupportedVersion(Int)
    public var errorDescription: String? {
        switch self {
        case .missingHeader: "This file has no Phelsuma header. Use Import Text to add it as a note."
        case .invalidUTF8: "The note is not valid UTF-8 text."
        case .invalidHeader: "The note's metadata is incomplete or invalid."
        case .unsupportedVersion(let version): "This note uses unsupported format version \(version)."
        }
    }
}

public enum NoteCodec {
    private struct Header: Codable {
        var version: Int
        var id: UUID
        var color: NoteColor
        var createdAt: Date
        var modifiedAt: Date
    }
    public static let prefix = "<!-- phelsuma\n"

    public static func encode(_ note: Note) throws -> Data {
        let header = Header(version: 1, id: note.id, color: note.color,
                            createdAt: note.createdAt, modifiedAt: note.modifiedAt)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let json = String(decoding: try encoder.encode(header), as: UTF8.self)
        return Data((prefix + json + "\n-->\n" + note.body).utf8)
    }

    public static func decode(_ data: Data) throws -> Note {
        guard let text = String(data: data, encoding: .utf8) else { throw NoteFormatError.invalidUTF8 }
        guard text.hasPrefix(prefix) else { throw NoteFormatError.missingHeader }
        let start = text.index(text.startIndex, offsetBy: prefix.count)
        guard let end = text.range(of: "\n-->\n", range: start..<text.endIndex) else {
            throw NoteFormatError.invalidHeader
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let headerData = Data(text[start..<end.lowerBound].utf8)
        // Inspect the version before decoding fields a newer schema may have changed.
        guard let object = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let version = object["version"] as? Int else { throw NoteFormatError.invalidHeader }
        guard version == 1 else { throw NoteFormatError.unsupportedVersion(version) }
        guard let header = try? decoder.decode(Header.self, from: headerData) else {
            throw NoteFormatError.invalidHeader
        }
        var note = Note(id: header.id, color: header.color,
                        body: String(text[end.upperBound...]), now: header.createdAt)
        note.modifiedAt = header.modifiedAt
        return note
    }
}
