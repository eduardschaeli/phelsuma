import Foundation

public struct TextEdit: Equatable, Sendable {
    public let range: NSRange
    public let replacement: String
    public let selection: NSRange
    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range; self.replacement = replacement; self.selection = selection
    }
}

public enum Markdown {
    /// Ranges follow NSTextView's UTF-16 indexing, including emoji and composed text.
    public static func toggle(_ delimiter: String, text: String, selection: NSRange) -> TextEdit {
        let source = text as NSString
        let length = (delimiter as NSString).length
        let selected = source.substring(with: selection)
        if selection.length >= length * 2 && selected.hasPrefix(delimiter) && selected.hasSuffix(delimiter) {
            let body = (selected as NSString).substring(with: NSRange(location: length, length: selection.length - length * 2))
            return TextEdit(range: selection, replacement: body,
                            selection: NSRange(location: selection.location, length: (body as NSString).length))
        }
        if selection.location >= length && NSMaxRange(selection) + length <= source.length,
           source.substring(with: NSRange(location: selection.location - length, length: length)) == delimiter,
           source.substring(with: NSRange(location: NSMaxRange(selection), length: length)) == delimiter {
            return TextEdit(range: NSRange(location: selection.location - length, length: selection.length + length * 2),
                            replacement: selected, selection: NSRange(location: selection.location - length, length: selection.length))
        }
        return TextEdit(range: selection, replacement: delimiter + selected + delimiter,
                        selection: NSRange(location: selection.location + length, length: selection.length))
    }

    public static func startList(text: String, selection: NSRange) -> TextEdit {
        let source = text as NSString
        let line = source.lineRange(for: selection)
        return TextEdit(range: NSRange(location: line.location, length: 0), replacement: "- ",
                        selection: NSRange(location: selection.location + 2, length: selection.length))
    }

    /// Continue a Markdown list on Return; an empty item ends the list.
    public static func continueList(text: String, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let source = text as NSString
        let lineRange = source.lineRange(for: selection)
        let line = source.substring(with: lineRange)
        let regex = try! NSRegularExpression(pattern: "^([ \\t]*)([-+*]|[0-9]+\\.)( )")
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { return nil }
        let prefix = (line as NSString).substring(with: match.range)
        guard selection.location >= lineRange.location + match.range.length else { return nil }
        let rest = (line as NSString).substring(from: match.range.length).trimmingCharacters(in: .whitespacesAndNewlines)
        if rest.isEmpty {
            return TextEdit(range: NSRange(location: lineRange.location, length: match.range.length), replacement: "",
                            selection: NSRange(location: lineRange.location, length: 0))
        }
        let marker = (line as NSString).substring(with: match.range(at: 2))
        var next = prefix
        if let number = Int(marker.dropLast()), number < Int.max {
            let indent = (line as NSString).substring(with: match.range(at: 1))
            next = "\(indent)\(number + 1). "
        }
        return TextEdit(range: selection, replacement: "\n" + next,
                        selection: NSRange(location: selection.location + 1 + (next as NSString).length, length: 0))
    }

    public static func indentList(text: String, selection: NSRange, outdent: Bool) -> TextEdit? {
        let source = text as NSString
        let line = source.lineRange(for: selection)
        let contents = source.substring(with: line)
        guard contents.range(of: "^[ \\t]*([-+*]|[0-9]+\\.) ", options: .regularExpression) != nil else { return nil }
        if outdent {
            let removed = contents.hasPrefix("\t") ? 1 : (contents.hasPrefix("  ") ? 2 : 0)
            guard removed > 0 else { return nil }
            return TextEdit(range: NSRange(location: line.location, length: removed), replacement: "",
                            selection: NSRange(location: max(line.location, selection.location - removed), length: selection.length))
        }
        return TextEdit(range: NSRange(location: line.location, length: 0), replacement: "  ",
                        selection: NSRange(location: selection.location + 2, length: selection.length))
    }
}
