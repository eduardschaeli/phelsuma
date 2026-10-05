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

@Test @MainActor func longFirstLineWrapsWithoutResizingSticky() throws {
    let state = WindowState(width: 300, height: 260)
    let controller = NoteWindowController(note: Note(body: "Short"), state: state)
    let window = try #require(controller.window)
    controller.showWindow(nil)
    defer { window.close() }
    window.contentView?.layoutSubtreeIfNeeded()
    let initialWidth = window.frame.width

    controller.editor.string = String(repeating: "A long piece of text ", count: 40)
    controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editor))
    window.contentView?.layoutSubtreeIfNeeded()

    #expect(window.frame.width == initialWidth)
    #expect(controller.editor.frame.width <= window.contentLayoutRect.width)
    #expect(controller.editor.textContainer?.containerSize.width ?? 0 <= window.contentLayoutRect.width)
    let container = try #require(controller.editor.textContainer)
    let layout = try #require(controller.editor.layoutManager)
    layout.ensureLayout(for: container)
    #expect(layout.usedRect(for: container).height > layout.defaultLineHeight(for: controller.editor.font!))

    var resizedFrame = window.frame
    resizedFrame.size.width = 420
    window.setFrame(resizedFrame, display: false)
    window.contentView?.layoutSubtreeIfNeeded()
    let resizedWidth = window.frame.width
    #expect(resizedWidth == 420)
    #expect(controller.editor.frame.width <= window.contentLayoutRect.width)

    controller.editor.string += String(repeating: " more text", count: 40)
    controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editor))
    window.contentView?.layoutSubtreeIfNeeded()
    #expect(window.frame.width == resizedWidth)
    #expect(controller.editor.frame.width <= window.contentLayoutRect.width)
}
