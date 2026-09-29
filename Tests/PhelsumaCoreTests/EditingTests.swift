import Foundation
import CoreGraphics
import Testing
@testable import PhelsumaCore

private func applying(_ edit: TextEdit, to text: String) -> String {
    (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
}

@Test func markdownTogglesPreserveUnicodeSelection() {
    let text = "a 🦎 café"
    let selection = (text as NSString).range(of: "🦎 café")
    let bold = Markdown.toggle("**", text: text, selection: selection)
    let formatted = applying(bold, to: text)
    #expect(formatted == "a **🦎 café**")
    let unbold = Markdown.toggle("**", text: formatted, selection: bold.selection)
    #expect(applying(unbold, to: formatted) == text)
    #expect(unbold.selection == selection)
    let empty = Markdown.toggle("*", text: "", selection: NSRange(location: 0, length: 0))
    #expect(empty.replacement == "**")
    #expect(empty.selection == NSRange(location: 1, length: 0))
}

@Test func selectedDelimitersAreRemoved() {
    let text = "**selected**"
    let edit = Markdown.toggle("**", text: text, selection: NSRange(location: 0, length: 12))
    #expect(applying(edit, to: text) == "selected")
}

@Test func listsContinueIndentAndEnd() throws {
    let text = "- first"
    let end = NSRange(location: 7, length: 0)
    let next = try #require(Markdown.continueList(text: text, selection: end))
    #expect(applying(next, to: text) == "- first\n- ")
    let finished = try #require(Markdown.continueList(text: "- first\n- ", selection: next.selection))
    #expect(applying(finished, to: "- first\n- ") == "- first\n")
    let ordered = try #require(Markdown.continueList(text: "9. item", selection: end))
    #expect(ordered.replacement == "\n10. ")
    let indent = try #require(Markdown.indentList(text: text, selection: end, outdent: false))
    let indented = applying(indent, to: text)
    #expect(indented == "  - first")
    let outdent = try #require(Markdown.indentList(text: indented, selection: indent.selection, outdent: true))
    #expect(applying(outdent, to: indented) == text)
    #expect(Markdown.continueList(text: "normal", selection: NSRange(location: 6, length: 0)) == nil)
}

@Test func layoutsStayLocalAndFitAvailableScreens() throws {
    let f = try Fixture()
    let note = try f.store.create(body: "do not change")
    let original = try Data(contentsOf: f.url(note.id))
    let url = f.root.appendingPathComponent("layout.json")
    let layout = try LayoutStore(url: url)
    let state = WindowState(x: 4000, y: -200, width: 1800, height: 900, collapsed: true)
    let fitted = state.fitted(to: [CGRect(x: 0, y: 0, width: 1000, height: 700)])
    #expect(fitted.frame == CGRect(x: 0, y: 0, width: 1000, height: 700))
    #expect(fitted.collapsed)
    try layout.set(fitted, for: note.id)
    #expect(try LayoutStore(url: url).states[note.id] == fitted)
    #expect(try Data(contentsOf: f.url(note.id)) == original)
}
