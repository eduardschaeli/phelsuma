import AppKit
import PhelsumaCore

extension NoteColor {
    public var background: NSColor {
        switch self {
        case .yellow: NSColor(calibratedRed: 1, green: 0.97, blue: 0.62, alpha: 1)
        case .blue: NSColor(calibratedRed: 0.70, green: 0.88, blue: 1, alpha: 1)
        case .green: NSColor(calibratedRed: 0.76, green: 0.96, blue: 0.70, alpha: 1)
        case .pink: NSColor(calibratedRed: 1, green: 0.79, blue: 0.85, alpha: 1)
        case .purple: NSColor(calibratedRed: 0.86, green: 0.79, blue: 0.98, alpha: 1)
        case .gray: NSColor(calibratedWhite: 0.88, alpha: 1)
        }
    }
    public var strip: NSColor {
        switch self {
        case .yellow: NSColor(calibratedRed: 1, green: 0.91, blue: 0.25, alpha: 1)
        case .blue: NSColor(calibratedRed: 0.46, green: 0.76, blue: 1, alpha: 1)
        case .green: NSColor(calibratedRed: 0.54, green: 0.84, blue: 0.40, alpha: 1)
        case .pink: NSColor(calibratedRed: 1, green: 0.59, blue: 0.70, alpha: 1)
        case .purple: NSColor(calibratedRed: 0.72, green: 0.61, blue: 0.93, alpha: 1)
        case .gray: NSColor(calibratedWhite: 0.74, alpha: 1)
        }
    }
}

@MainActor final class StickyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor final class TitleStrip: NSView {
    var doubleClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { doubleClick?() }
        else { window?.performDrag(with: event) }
    }
    override var mouseDownCanMoveWindow: Bool { true }
}

@MainActor public final class NoteWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    public let id: UUID
    public let editor = MarkdownTextView()
    public private(set) var state: WindowState
    public var onEdit: ((UUID, String) -> Void)?
    public var onDelete: ((UUID) -> Void)?
    public var onLayout: ((UUID, WindowState) -> Void)?
    public var onResign: (() -> Void)?
    private let scroll = NSScrollView()
    private let strip = TitleStrip()
    private let caption = NSTextField(labelWithString: "")
    private var updatingFrame = false
    private var zoomedFrame: NSRect?
    private var collapseButton: NSButton!

    public init(note: Note, state: WindowState) {
        self.id = note.id
        self.state = state.fitted(to: NSScreen.screens.map(\.visibleFrame))
        let window = StickyWindow(contentRect: self.state.frame,
                                  styleMask: [.borderless, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
        super.init(window: window)
        window.isReleasedWhenClosed = false
        window.hasShadow = true
        window.minSize = NSSize(width: 180, height: 100)
        window.delegate = self
        window.title = note.title
        window.setAccessibilityLabel(note.title)
        window.appearance = NSAppearance(named: .aqua)
        window.collectionBehavior = [.managed]
        buildContent()
        editor.baseFontSize = state.fontSize
        editor.loadBody(note.body)
        editor.highlight()
        update(note)
        applyAppearance()
        if self.state.collapsed { applyCollapsedFrame() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        strip.translatesAutoresizingMaskIntoConstraints = false
        strip.wantsLayer = true
        content.addSubview(strip)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        editor.frame = NSRect(x: 0, y: 0, width: state.width, height: state.height - 16)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: state.width, height: CGFloat.greatestFiniteMagnitude)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.delegate = self
        scroll.documentView = editor
        content.addSubview(scroll)
        caption.font = NSFont.systemFont(ofSize: 10)
        caption.textColor = .black
        caption.lineBreakMode = .byTruncatingTail
        caption.translatesAutoresizingMaskIntoConstraints = false
        caption.isHidden = true
        strip.addSubview(caption)
        let close = button("×", label: "Delete note", action: #selector(deleteNote))
        let zoom = button("△", label: "Zoom note", action: #selector(zoomNote))
        collapseButton = button("−", label: "Collapse note", action: #selector(toggleCollapse))
        strip.doubleClick = { [weak self] in self?.toggleCollapse(nil) }
        NSLayoutConstraint.activate([
            strip.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            strip.topAnchor.constraint(equalTo: content.topAnchor), strip.heightAnchor.constraint(equalToConstant: 16),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: strip.bottomAnchor), scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            close.leadingAnchor.constraint(equalTo: strip.leadingAnchor, constant: 6),
            zoom.trailingAnchor.constraint(equalTo: collapseButton.leadingAnchor, constant: -2),
            collapseButton.trailingAnchor.constraint(equalTo: strip.trailingAnchor, constant: -6),
            caption.leadingAnchor.constraint(equalTo: close.trailingAnchor, constant: 6),
            caption.trailingAnchor.constraint(equalTo: zoom.leadingAnchor, constant: -4),
            caption.centerYAnchor.constraint(equalTo: strip.centerYAnchor)
        ])
    }

    private func button(_ title: String, label: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 12)
        button.contentTintColor = NSColor.black.withAlphaComponent(0.55)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setAccessibilityLabel(label)
        button.toolTip = label
        strip.addSubview(button)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 14), button.heightAnchor.constraint(equalToConstant: 14),
            button.centerYAnchor.constraint(equalTo: strip.centerYAnchor)
        ])
        return button
    }

    public func update(_ note: Note) {
        window?.title = note.title
        window?.setAccessibilityLabel(note.title)
        caption.stringValue = note.title
        strip.toolTip = "Created \(note.createdAt.formatted())\nEdited \(note.modifiedAt.formatted())"
        window?.backgroundColor = note.color.background
        strip.layer?.backgroundColor = note.color.strip.cgColor
        editor.loadBody(note.body)
    }

    public func focus() {
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        if !state.collapsed { window?.makeFirstResponder(editor) }
    }

    public func textDidChange(_ notification: Notification) {
        editor.highlight()
        caption.stringValue = String(editor.string.split(whereSeparator: \.isNewline).first ?? "New Note")
        window?.title = caption.stringValue
        onEdit?(id, editor.string)
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool { onDelete?(id); return false }
    @objc public func deleteNote(_ sender: Any?) { onDelete?(id) }

    @objc public func toggleCollapse(_ sender: Any?) {
        guard let window else { return }
        if !state.collapsed { recordFrame() }
        state.collapsed.toggle()
        updatingFrame = true
        if state.collapsed { applyCollapsedFrame() }
        else {
            window.minSize = NSSize(width: 180, height: 100)
            window.setFrame(state.frame, display: true)
            scroll.isHidden = false
            caption.isHidden = true
            window.makeFirstResponder(editor)
        }
        collapseButton.setAccessibilityLabel(state.collapsed ? "Expand note" : "Collapse note")
        collapseButton.toolTip = state.collapsed ? "Expand note" : "Collapse note"
        updatingFrame = false
        onLayout?(id, state)
    }

    private func applyCollapsedFrame() {
        guard let window else { return }
        updatingFrame = true
        scroll.isHidden = true
        caption.isHidden = false
        window.minSize = NSSize(width: 180, height: 16)
        window.setFrame(NSRect(x: state.x, y: state.y + state.height - 16, width: state.width, height: 16), display: true)
        collapseButton.setAccessibilityLabel("Expand note")
        updatingFrame = false
    }

    @objc public func toggleFloating(_ sender: Any?) {
        state.floating.toggle(); applyAppearance(); onLayout?(id, state)
    }
    @objc public func toggleTranslucent(_ sender: Any?) {
        state.translucent.toggle(); applyAppearance(); onLayout?(id, state)
    }
    private func applyAppearance() {
        window?.level = state.floating ? .floating : .normal
        window?.alphaValue = state.translucent ? 0.72 : 1
    }
    @objc public func zoomNote(_ sender: Any?) {
        guard let window else { return }
        if state.collapsed { toggleCollapse(nil) }
        if let previous = zoomedFrame {
            window.setFrame(previous, display: true); zoomedFrame = nil
        } else {
            zoomedFrame = window.frame
            if let frame = window.screen?.visibleFrame { window.setFrame(frame, display: true) }
        }
        recordFrame()
    }
    public func changeFontSize(by amount: CGFloat) {
        state.fontSize = min(max(state.fontSize + amount, 9), 36)
        editor.baseFontSize = state.fontSize
        editor.highlight()
        onLayout?(id, state)
    }
    public func place(at origin: NSPoint) {
        window?.setFrameOrigin(origin)
        recordFrame()
    }
    public func windowDidMove(_ notification: Notification) { recordFrame() }
    public func windowDidResize(_ notification: Notification) { recordFrame() }
    public func windowDidResignKey(_ notification: Notification) { onResign?() }
    private func recordFrame() {
        guard !updatingFrame, let frame = window?.frame else { return }
        state.x = frame.minX
        state.y = state.collapsed ? frame.minY + 16 - state.height : frame.minY
        state.width = frame.width
        if !state.collapsed { state.height = frame.height }
        onLayout?(id, state)
    }
}
