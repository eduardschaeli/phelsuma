import AppKit
import CryptoKit
import UniformTypeIdentifiers
import PhelsumaCore
import PhelsumaUI

@MainActor final class AppController: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var store: NoteStore?
    private var recovery: RecoveryStore!
    private var layout: LayoutStore!
    private var windows: [UUID: NoteWindowController] = [:]
    private var pending: [UUID: Task<Void, Never>] = [:]
    private var pollTimer: Timer?
    private var folderWatch: DispatchSourceFileSystemObject?
    private var listPanel: NoteListPanel?
    private var accessedFolder: URL?
    private var presenting = false
    private var reportedIssues = Set<String>()
    private var arrangementUndo: [UUID: NSPoint] = [:]
    private var support: URL!
    private var preferences: UserDefaults = .standard
    private var defaultColor: NoteColor { NoteColor(rawValue: preferences.string(forKey: "defaultColor") ?? "") ?? .yellow }
    private var active: NoteWindowController? {
        windows.values.first { $0.window === NSApp.keyWindow } ?? windows.values.first { $0.window === NSApp.mainWindow }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenus()
        do {
            if let path = ProcessInfo.processInfo.environment["PHELSUMA_HOME"] {
                support = URL(fileURLWithPath: path, isDirectory: true)
                let digest = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
                preferences = UserDefaults(suiteName: "Phelsuma.Development.\(digest)")!
            } else {
                support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Phelsuma", isDirectory: true)
            }
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            recovery = try RecoveryStore(directory: support.appendingPathComponent("Recovery", isDirectory: true))
            do { layout = try LayoutStore(url: support.appendingPathComponent("layout.json")) }
            catch {
                let damaged = support.appendingPathComponent("layout-damaged-\(UUID()).json")
                try FileManager.default.moveItem(at: support.appendingPathComponent("layout.json"), to: damaged)
                layout = try LayoutStore(url: support.appendingPathComponent("layout.json"))
            }
            let folder: URL
            if let bookmark = preferences.data(forKey: "storageBookmark") {
                var stale = false
                folder = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], bookmarkDataIsStale: &stale)
            } else if let path = preferences.string(forKey: "storagePath") {
                folder = URL(fileURLWithPath: path, isDirectory: true)
            } else {
                folder = support.appendingPathComponent("Notes", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            try openStore(folder)
            if !preferences.bool(forKey: "hasLaunched"), store?.notes.isEmpty == true {
                _ = try store?.create(body: "# Make a note of it!\n\nYour notes are saved as Markdown.\n\n- ⌘N creates a note\n- ⌘B and ⌘I add Markdown\n- Double-click the title strip to fold\n\nChoose a synced folder from the Phelsuma menu. Let your sync tool finish before switching Macs.")
                synchronizeWindows()
                preferences.set(true, forKey: "hasLaunched")
            }
        } catch { report(error) }
        for controller in windows.values { controller.showWindow(nil) }
        windows.values.first?.focus()
        NSApp.activate(ignoringOtherApps: true)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidBecomeActive(_ notification: Notification) { refresh() }
    func applicationWillResignActive(_ notification: Notification) { _ = flush() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        flush() ? .terminateNow : .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
        folderWatch?.cancel()
        accessedFolder?.stopAccessingSecurityScopedResource()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        for controller in windows.values { controller.showWindow(nil) }
        if windows.isEmpty { newNote(nil) }
        return true
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            do { _ = try store?.importText(at: URL(fileURLWithPath: filename)) }
            catch { report(error) }
        }
        synchronizeWindows()
        sender.reply(toOpenOrPrint: .success)
    }
    @objc private func woke() { refresh() }

    private func openStore(_ folder: URL) throws {
        guard let recovery, layout != nil else {
            throw NSError(domain: "Phelsuma", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Local recovery storage could not be initialized. Check available disk space and permissions, then restart Phelsuma."])
        }
        let granted = folder.startAccessingSecurityScopedResource()
        let next: NoteStore
        do {
            next = try NoteStore(directory: folder, recovery: recovery)
            try next.refresh()
        } catch {
            if granted { folder.stopAccessingSecurityScopedResource() }
            throw error
        }
        folderWatch?.cancel()
        accessedFolder?.stopAccessingSecurityScopedResource()
        accessedFolder = granted ? folder : nil
        for controller in windows.values { controller.window?.orderOut(nil); controller.window?.close() }
        windows.removeAll()
        store = next
        reportedIssues = []
        synchronizeWindows()
        let descriptor = open(folder.path, O_EVTONLY)
        if descriptor >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in Task { @MainActor in self?.refresh() } }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            folderWatch = source
        }
    }

    private func synchronizeWindows() {
        guard let store, let layout else { return }
        let ids = Set(store.notes.map(\.id))
        for (id, controller) in windows where !ids.contains(id) {
            pending.removeValue(forKey: id)?.cancel()
            controller.window?.orderOut(nil)
            controller.window?.close()
            windows.removeValue(forKey: id)
        }
        for note in store.notes {
            if let controller = windows[note.id] { controller.update(note); continue }
            var state = layout.states[note.id] ?? WindowState()
            if layout.states[note.id] == nil {
                state.x += Double(windows.count % 8) * 28
                state.y -= Double(windows.count % 8) * 28
                if let data = preferences.data(forKey: "defaultWindow"),
                   let defaults = try? JSONDecoder().decode(WindowState.self, from: data) {
                    state.width = defaults.width; state.height = defaults.height
                    state.floating = defaults.floating; state.translucent = defaults.translucent
                    state.fontSize = defaults.fontSize
                }
            }
            let controller = NoteWindowController(note: note, state: state)
            controller.onEdit = { [weak self] id, body in
                self?.store?.edit(id, body: body)
                self?.scheduleSave(id)
            }
            controller.onDelete = { [weak self] id in self?.deleteNote(id) }
            controller.onLayout = { [weak self] id, state in
                do { try self?.layout.set(state, for: id) } catch { self?.report(error) }
            }
            controller.onResign = { [weak self] in _ = self?.flush() }
            windows[note.id] = controller
            controller.showWindow(nil)
            NSApp.addWindowsItem(controller.window!, title: note.title, filename: false)
        }
        for controller in windows.values {
            if let window = controller.window { NSApp.changeWindowsItem(window, title: window.title, filename: false) }
        }
    }

    private func scheduleSave(_ id: UUID) {
        pending[id]?.cancel()
        pending[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            self.pending.removeValue(forKey: id)
            _ = self.save(id)
        }
    }
    @discardableResult private func save(_ id: UUID) -> Bool {
        guard let store, store.note(id) != nil else { return true }
        do {
            let result = try store.save(id)
            synchronizeWindows()
            if case .conflict(let copy) = result {
                windows[copy]?.focus()
                inform("Both versions were kept", "Another version arrived while you were editing. Your edits are in a separate note; the incoming note is unchanged.")
            }
            return true
        } catch {
            synchronizeWindows()
            report(error)
            return false
        }
    }
    private func flush() -> Bool {
        for task in pending.values { task.cancel() }
        pending.removeAll()
        var success = true
        for id in store?.dirtyIDs ?? [] { if !save(id) { success = false } }
        return success
    }
    private func refresh() {
        guard !presenting, let store else { return }
        // Don't interrupt input-method composition with an external replacement.
        guard !windows.values.contains(where: { $0.editor.hasMarkedText() }) else { return }
        do {
            let conflicts = try store.refresh()
            synchronizeWindows()
            if !conflicts.isEmpty { inform("Both versions were kept", "Incoming changes conflicted with local edits. Each version is available as a separate note.") }
            for issue in store.issues {
                reportMessage(issue.message, key: issue.path + issue.message)
            }
        } catch { report(error) }
    }

    @objc func newNote(_ sender: Any?) {
        guard let store else { chooseFolder(nil); return }
        do {
            let note = try store.create(color: defaultColor)
            synchronizeWindows()
            windows[note.id]?.focus()
        } catch { report(error) }
    }
    @objc func closeNote(_ sender: Any?) { if let id = active?.id { deleteNote(id) } }
    private func deleteNote(_ id: UUID) {
        guard let note = store?.note(id), !presenting else { return }
        presenting = true
        let alert = NSAlert()
        alert.messageText = "Delete this note?"
        alert.informativeText = "\(note.title)\n\nYou can restore it using File → Recover Notes."
        alert.addButton(withTitle: "Delete Note")
        alert.addButton(withTitle: "Cancel")
        let answer = alert.runModal()
        presenting = false
        if answer == .alertFirstButtonReturn {
            pending.removeValue(forKey: id)?.cancel()
            do { try store?.delete(id); synchronizeWindows() } catch { report(error) }
        }
    }
    @objc func closeAll(_ sender: Any?) {
        for id in Array(windows.keys) { deleteNote(id) }
    }
    @objc func chooseFolder(_ sender: Any?) {
        guard flush() else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.message = "Open notes in this folder. Existing notes stay in their current folder; use Finder to move them if needed."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try openStore(url)
            preferences.set(url.path, forKey: "storagePath")
            preferences.removeObject(forKey: "storageBookmark")
            if let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                preferences.set(bookmark, forKey: "storageBookmark")
            }
            refresh()
        } catch { report(error) }
    }
    @objc func revealFolder(_ sender: Any?) {
        if let folder = store?.directory { NSWorkspace.shared.open(folder) }
    }
    @objc func reload(_ sender: Any?) { reportedIssues.removeAll(); refresh() }
    @objc func importNotes(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        panel.message = "Import UTF-8 plain text or Markdown. Each file becomes a new note."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do { _ = try store?.importText(at: url) } catch { report(error) }
        }
        synchronizeWindows()
    }
    @objc func exportNote(_ sender: Any?) {
        guard let controller = active, let note = store?.note(controller.id) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Note.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Data(note.body.utf8).write(to: url, options: .atomic) } catch { report(error) }
    }
    @objc func recoverNotes(_ sender: Any?) {
        do {
            let entries = try recovery.entries()
            listPanel = NoteListPanel(title: "Recover Notes", actionTitle: "Restore as New Note", items: entries.map { entry in
                NoteListItem(title: entry.note.title, detail: "\(entry.date.formatted()) · \(entry.reason)", body: entry.note.body) { [weak self] in
                    do {
                        if let note = try self?.store?.restore(entry) {
                            self?.synchronizeWindows(); self?.windows[note.id]?.focus()
                        }
                    } catch { self?.report(error) }
                }
            })
            listPanel?.present()
        } catch { report(error) }
    }
    @objc func findAll(_ sender: Any?) {
        listPanel = NoteListPanel(title: "Find in All Notes", actionTitle: "Open Note", items: (store?.notes ?? []).map { note in
            NoteListItem(title: note.title, detail: "Edited \(note.modifiedAt.formatted())", body: note.body) { [weak self] in
                guard let controller = self?.windows[note.id] else { return }
                if controller.state.collapsed { controller.toggleCollapse(nil) }
                controller.focus()
            }
        })
        listPanel?.present()
    }
    @objc func changeColor(_ sender: NSMenuItem) {
        guard let id = active?.id, NoteColor.allCases.indices.contains(sender.tag) else { return }
        store?.edit(id, color: NoteColor.allCases[sender.tag])
        _ = save(id)
    }
    @objc func collapse(_ sender: Any?) { active?.toggleCollapse(sender) }
    @objc func collapseAll(_ sender: Any?) {
        let shouldCollapse = !(active?.state.collapsed ?? false)
        for window in windows.values where window.state.collapsed != shouldCollapse { window.toggleCollapse(nil) }
    }
    @objc func floating(_ sender: Any?) { active?.toggleFloating(sender) }
    @objc func translucent(_ sender: Any?) { active?.toggleTranslucent(sender) }
    @objc func zoom(_ sender: Any?) { active?.zoomNote(sender) }
    @objc func useAsDefault(_ sender: Any?) {
        guard let controller = active, let note = store?.note(controller.id) else { return }
        preferences.set(note.color.rawValue, forKey: "defaultColor")
        if let data = try? JSONEncoder().encode(controller.state) { preferences.set(data, forKey: "defaultWindow") }
    }
    @objc func larger(_ sender: Any?) { active?.changeFontSize(by: 1) }
    @objc func smaller(_ sender: Any?) { active?.changeFontSize(by: -1) }
    @objc func printNote(_ sender: Any?) { active?.editor.printView(sender) }
    @objc func arrange(_ sender: NSMenuItem) {
        guard let screen = active?.window?.screen ?? NSScreen.main, let store else { return }
        arrangementUndo = windows.compactMapValues { $0.window?.frame.origin }
        let notes = store.notes.sorted {
            switch sender.tag {
            case 0: return $0.color.rawValue < $1.color.rawValue
            case 1: return $0.body.localizedCaseInsensitiveCompare($1.body) == .orderedAscending
            case 2: return $0.createdAt < $1.createdAt
            default: return (windows[$0.id]?.state.y ?? 0) > (windows[$1.id]?.state.y ?? 0)
            }
        }
        let frame = screen.visibleFrame
        var x = frame.minX + 20, top = frame.maxY - 20, rowHeight: CGFloat = 0
        for note in notes {
            guard let controller = windows[note.id], let window = controller.window else { continue }
            if x + window.frame.width > frame.maxX && x > frame.minX + 20 {
                x = frame.minX + 20; top -= rowHeight + 16; rowHeight = 0
            }
            if top - window.frame.height < frame.minY { top = frame.maxY - 20 }
            controller.place(at: NSPoint(x: x, y: max(frame.minY, top - window.frame.height)))
            x += window.frame.width + 16
            rowHeight = max(rowHeight, window.frame.height)
        }
    }
    @objc func undoArrange(_ sender: Any?) {
        let current = windows.compactMapValues { $0.window?.frame.origin }
        for (id, origin) in arrangementUndo { windows[id]?.place(at: origin) }
        arrangementUndo = current
    }

    private func report(_ error: Error) { reportMessage(error.localizedDescription, key: error.localizedDescription) }
    private func reportMessage(_ message: String, key: String) {
        guard !reportedIssues.contains(key), !presenting else { return }
        reportedIssues.insert(key)
        inform("Phelsuma needs attention", message)
    }
    private func inform(_ title: String, _ detail: String) {
        guard !presenting else { return }
        presenting = true
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.addButton(withTitle: "OK"); alert.runModal()
        presenting = false
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let noteActions: [Selector] = [#selector(closeNote), #selector(exportNote), #selector(changeColor),
            #selector(collapse), #selector(floating), #selector(translucent), #selector(zoom), #selector(useAsDefault),
            #selector(larger), #selector(smaller), #selector(printNote)]
        if item.action == #selector(floating) { item.state = active?.state.floating == true ? .on : .off }
        if item.action == #selector(translucent) { item.state = active?.state.translucent == true ? .on : .off }
        if item.action == #selector(collapse) { item.title = active?.state.collapsed == true ? "Expand" : "Collapse" }
        if item.action == #selector(changeColor), let id = active?.id {
            item.state = store?.note(id)?.color == NoteColor.allCases[item.tag] ? .on : .off
        }
        if noteActions.contains(where: { $0 == item.action }) { return active != nil }
        if item.action == #selector(undoArrange) { return !arrangementUndo.isEmpty }
        if [#selector(importNotes), #selector(recoverNotes), #selector(revealFolder)].contains(where: { $0 == item.action }) { return store != nil }
        return true
    }

    private func buildMenus() {
        let bar = NSMenu()
        NSApp.mainMenu = bar
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title); item.submenu = submenu; bar.addItem(item); return submenu
        }
        @discardableResult func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "",
                                   _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil, tag: Int = 0) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers; item.target = target; item.tag = tag
            menu.addItem(item); return item
        }
        let app = menu("Phelsuma")
        add(app, "About Phelsuma", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        app.addItem(.separator())
        add(app, "Choose Storage Folder…", #selector(chooseFolder), ",", target: self)
        add(app, "Show Storage Folder in Finder", #selector(revealFolder), target: self)
        add(app, "Reload Notes from Disk", #selector(reload), "r", [.command, .shift], target: self)
        let services = NSMenu(); let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services; app.addItem(servicesItem); NSApp.servicesMenu = services
        app.addItem(.separator())
        add(app, "Hide Phelsuma", #selector(NSApplication.hide(_:)), "h")
        add(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        add(app, "Quit Phelsuma", #selector(NSApplication.terminate(_:)), "q")
        let file = menu("File")
        add(file, "New Note", #selector(newNote), "n", target: self)
        add(file, "Close", #selector(closeNote), "w", target: self)
        add(file, "Close All…", #selector(closeAll), "w", [.command, .option], target: self)
        file.addItem(.separator())
        add(file, "Import Text…", #selector(importNotes), "i", [.command, .shift], target: self)
        add(file, "Export Text…", #selector(exportNote), "e", [.command, .shift], target: self)
        add(file, "Recover Notes…", #selector(recoverNotes), target: self)
        file.addItem(.separator())
        add(file, "Print…", #selector(printNote), "p", target: self)
        let edit = menu("Edit")
        add(edit, "Undo", Selector(("undo:")), "z")
        add(edit, "Redo", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        add(edit, "Cut", #selector(NSText.cut(_:)), "x")
        add(edit, "Copy", #selector(NSText.copy(_:)), "c")
        add(edit, "Paste", #selector(NSText.paste(_:)), "v")
        add(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator())
        let find = NSMenu(title: "Find"); let findItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        findItem.submenu = find; edit.addItem(findItem)
        add(find, "Find…", #selector(NSTextView.performTextFinderAction(_:)), "f", tag: NSTextFinder.Action.showFindInterface.rawValue)
        add(find, "Find and Replace…", #selector(NSTextView.performTextFinderAction(_:)), "r", [.command, .option], tag: NSTextFinder.Action.showReplaceInterface.rawValue)
        add(find, "Find Next", #selector(NSTextView.performTextFinderAction(_:)), "g", tag: NSTextFinder.Action.nextMatch.rawValue)
        add(find, "Find Previous", #selector(NSTextView.performTextFinderAction(_:)), "g", [.command, .shift], tag: NSTextFinder.Action.previousMatch.rawValue)
        add(find, "Use Selection for Find", #selector(NSTextView.performTextFinderAction(_:)), "e", tag: NSTextFinder.Action.setSearchString.rawValue)
        add(find, "Find in All Notes…", #selector(findAll), "f", [.command, .shift], target: self)
        let font = menu("Font")
        add(font, "Bold", #selector(MarkdownTextView.toggleBold(_:)), "b")
        add(font, "Italic", #selector(MarkdownTextView.toggleItalic(_:)), "i")
        add(font, "Inline Code", #selector(MarkdownTextView.toggleCode(_:)), "k", [.command, .shift])
        add(font, "Start List", #selector(MarkdownTextView.makeList(_:)), "\t", .option)
        font.addItem(.separator())
        add(font, "Bigger", #selector(larger), "+", target: self)
        add(font, "Smaller", #selector(smaller), "-", target: self)
        let colors = menu("Color")
        for (index, color) in NoteColor.allCases.enumerated() {
            add(colors, color.rawValue.capitalized, #selector(changeColor), String(index + 1), target: self, tag: index)
        }
        let window = menu("Window"); NSApp.windowsMenu = window
        add(window, "Collapse", #selector(collapse), "m", [.command, .option], target: self)
        add(window, "Collapse All", #selector(collapseAll), "m", [.command, .option, .shift], target: self)
        add(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(window, "Zoom", #selector(zoom), target: self)
        window.addItem(.separator())
        add(window, "Float on Top", #selector(floating), "f", [.command, .option], target: self)
        add(window, "Translucent", #selector(translucent), "t", [.command, .option], target: self)
        add(window, "Use as Default", #selector(useAsDefault), target: self)
        window.addItem(.separator())
        add(window, "Undo/Redo Arrange", #selector(undoArrange), target: self)
        let arrangeMenu = NSMenu(title: "Arrange By")
        let arrangeItem = NSMenuItem(title: "Arrange By", action: nil, keyEquivalent: ""); arrangeItem.submenu = arrangeMenu
        window.addItem(arrangeItem)
        for (tag, title) in ["Color", "Content", "Date", "Location on Screen"].enumerated() {
            add(arrangeMenu, title, #selector(arrange), target: self, tag: tag)
        }
        add(window, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
    }
}
