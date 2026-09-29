import AppKit
import PhelsumaCore

@MainActor public final class MarkdownTextView: NSTextView {
    public var baseFontSize: CGFloat = 13

    public convenience init() {
        self.init(frame: .zero)
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        textContainerInset = NSSize(width: 7, height: 7)
        font = NSFont.systemFont(ofSize: baseFontSize)
        textColor = .black
        drawsBackground = false
        setAccessibilityLabel("Note text")
    }

    @objc public func toggleBold(_ sender: Any?) { apply(Markdown.toggle("**", text: string, selection: selectedRange())) }
    @objc public func toggleItalic(_ sender: Any?) { apply(Markdown.toggle("*", text: string, selection: selectedRange())) }
    @objc public func toggleCode(_ sender: Any?) { apply(Markdown.toggle("`", text: string, selection: selectedRange())) }
    @objc public func makeList(_ sender: Any?) { apply(Markdown.startList(text: string, selection: selectedRange())) }

    public func apply(_ edit: TextEdit) {
        breakUndoCoalescing()
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(edit.selection)
        scrollRangeToVisible(edit.selection)
        breakUndoCoalescing()
    }

    public override func insertNewline(_ sender: Any?) {
        if let edit = Markdown.continueList(text: string, selection: selectedRange()) { apply(edit) }
        else { super.insertNewline(sender) }
    }

    public override func insertTab(_ sender: Any?) {
        if let edit = Markdown.indentList(text: string, selection: selectedRange(), outdent: false) { apply(edit) }
        else { super.insertTab(sender) }
    }

    public override func insertBacktab(_ sender: Any?) {
        if let edit = Markdown.indentList(text: string, selection: selectedRange(), outdent: true) { apply(edit) }
        else { super.insertBacktab(sender) }
    }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option {
            makeList(nil)
        } else { super.keyDown(with: event) }
    }

    public override func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let selection = selectedRange()
        apply(TextEdit(range: selection, replacement: text,
                       selection: NSRange(location: selection.location + (text as NSString).length, length: 0)))
    }

    public func highlight() {
        guard !hasMarkedText(), let storage = textStorage else { return }
        let selection = selectedRanges
        let full = NSRange(location: 0, length: storage.length)
        let regular = NSFont.systemFont(ofSize: baseFontSize)
        let normal: [NSAttributedString.Key: Any] = [.font: regular, .foregroundColor: NSColor.black]
        storage.beginEditing()
        storage.setAttributes(normal, range: full)
        func style(_ pattern: String, _ attributes: [NSAttributedString.Key: Any]) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
            for match in regex.matches(in: string, range: full) { storage.addAttributes(attributes, range: match.range) }
        }
        style("^#{1,6} .+$", [.font: NSFont.boldSystemFont(ofSize: baseFontSize + 2)])
        style("\\*\\*[^\\n]+?\\*\\*", [.font: NSFont.boldSystemFont(ofSize: baseFontSize)])
        style("(?<!\\*)\\*(?!\\*)[^*\\n]+\\*(?!\\*)", [.font: NSFontManager.shared.convert(regular, toHaveTrait: .italicFontMask)])
        style("`[^`\\n]+`", [.font: NSFont.monospacedSystemFont(ofSize: baseFontSize, weight: .regular),
                            .foregroundColor: NSColor.darkGray])
        style("\\[[^\\]\\n]+\\]\\([^\\n)]+\\)", [.foregroundColor: NSColor(calibratedRed: 0.12, green: 0.24, blue: 0.48, alpha: 1)])
        storage.endEditing()
        selectedRanges = selection
        typingAttributes = normal
    }

    public func loadBody(_ body: String) {
        guard string != body else { return }
        let selection = selectedRange()
        let origin = enclosingScrollView?.contentView.bounds.origin
        string = body
        // An external replacement starts a new undo history; undo must not restore stale remote text.
        undoManager?.removeAllActions()
        let location = min(selection.location, (body as NSString).length)
        setSelectedRange(NSRange(location: location, length: min(selection.length, (body as NSString).length - location)))
        highlight()
        if let origin { enclosingScrollView?.contentView.scroll(to: origin) }
    }
}
