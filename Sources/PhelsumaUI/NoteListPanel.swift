import AppKit

public struct NoteListItem {
    public let title: String
    public let detail: String
    public let body: String
    public let action: @MainActor () -> Void
    public init(title: String, detail: String, body: String, action: @escaping @MainActor () -> Void) {
        self.title = title; self.detail = detail; self.body = body; self.action = action
    }
}

@MainActor public final class NoteListPanel: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let search = NSSearchField()
    private let table = NSTableView()
    private let preview = NSTextView()
    private let items: [NoteListItem]
    private var filtered: [NoteListItem] = []
    private let choose: NSButton

    public init(title: String, actionTitle: String, items: [NoteListItem]) {
        self.items = items
        self.choose = NSButton(title: actionTitle, target: nil, action: nil)
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 440, height: 360)
        super.init(window: window)
        guard let content = window.contentView else { return }
        let listScroll = NSScrollView()
        listScroll.hasVerticalScroller = true
        listScroll.borderType = .bezelBorder
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note"))
        column.title = "Notes"
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 44
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(activate)
        listScroll.documentView = table
        let previewScroll = NSScrollView()
        previewScroll.hasVerticalScroller = true
        previewScroll.borderType = .bezelBorder
        preview.isEditable = false
        preview.isRichText = false
        preview.font = .systemFont(ofSize: 13)
        preview.autoresizingMask = [.width]
        preview.textContainer?.widthTracksTextView = true
        previewScroll.documentView = preview
        search.placeholderString = "Search notes"
        search.delegate = self
        choose.target = self
        choose.action = #selector(activate)
        choose.bezelStyle = .rounded
        choose.keyEquivalent = "\r"
        for view in [search, listScroll, previewScroll, choose] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            search.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            search.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            listScroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12),
            listScroll.leadingAnchor.constraint(equalTo: search.leadingAnchor),
            listScroll.trailingAnchor.constraint(equalTo: search.trailingAnchor),
            listScroll.heightAnchor.constraint(equalTo: content.heightAnchor, multiplier: 0.40),
            previewScroll.topAnchor.constraint(equalTo: listScroll.bottomAnchor, constant: 12),
            previewScroll.leadingAnchor.constraint(equalTo: search.leadingAnchor),
            previewScroll.trailingAnchor.constraint(equalTo: search.trailingAnchor),
            previewScroll.bottomAnchor.constraint(equalTo: choose.topAnchor, constant: -12),
            choose.trailingAnchor.constraint(equalTo: search.trailingAnchor),
            choose.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
        filter()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    public func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = filtered[row]
        let label = NSTextField(labelWithString: "\(item.title)\n\(item.detail)")
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        return label
    }
    public func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        preview.string = filtered.indices.contains(row) ? filtered[row].body : ""
        choose.isEnabled = filtered.indices.contains(row)
    }
    public func controlTextDidChange(_ obj: Notification) { filter() }
    private func filter() {
        let query = search.stringValue
        filtered = items.filter { query.isEmpty || ($0.title + $0.body + $0.detail).localizedCaseInsensitiveContains(query) }
        table.reloadData()
        if !filtered.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        else { preview.string = items.isEmpty ? "No notes to show." : "No matching notes."; choose.isEnabled = false }
    }
    @objc private func activate(_ sender: Any?) {
        guard filtered.indices.contains(table.selectedRow) else { return }
        filtered[table.selectedRow].action()
        close()
    }
    public func present() { showWindow(nil); window?.makeKeyAndOrderFront(nil); window?.makeFirstResponder(search) }
}
