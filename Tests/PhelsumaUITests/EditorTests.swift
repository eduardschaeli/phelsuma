import AppKit
import Testing
import PhelsumaCore
@testable import PhelsumaUI

@Test @MainActor func highlightingDoesNotChangeTextSelectionOrUndo() {
    let view = MarkdownTextView()
    view.string = "# Heading\n**bold** and *italic* `code` 🦎"
    let selection = NSRange(location: 4, length: 7)
    view.setSelectedRange(selection)
    let before = view.string
    view.highlight()
    #expect(view.string == before)
    #expect(view.selectedRange() == selection)
    #expect(view.undoManager?.canUndo != true)
    #expect(view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == NSFont.boldSystemFont(ofSize: 15))
}

@Test @MainActor func externalReloadPreservesValidSelection() {
    let view = MarkdownTextView()
    view.string = "old long text"
    view.setSelectedRange(NSRange(location: 10, length: 3))
    view.loadBody("new")
    #expect(view.string == "new")
    #expect(view.selectedRange() == NSRange(location: 3, length: 0))
}
