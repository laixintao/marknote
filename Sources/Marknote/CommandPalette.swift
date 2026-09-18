import AppKit
import MarknoteCore

@MainActor final class CommandPalette: NSWindowController, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    struct Entry {
        let id: String
        let title: String
        let detail: String
        let keywords: String
        let shortcut: String
        let perform: () -> Void
    }
    let search = NSSearchField()
    let table = NSTableView()
    private let empty = PaddedLabel(.noMatches, size: 13)
    private let entries: [Entry]
    private(set) var results: [Entry] = []
    private var completion: ((Entry?) -> Void)?

    init(title: String, placeholder: String, entries: [Entry]) {
        self.entries = entries
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 570, height: 400), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = title
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        panel.delegate = self
        search.placeholderString = placeholder
        search.setAccessibilityLabel(placeholder)
        search.delegate = self
        search.sendsSearchStringImmediately = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 47
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.style = .fullWidth
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(accept(_:))
        table.setAccessibilityLabel(title)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let hint = PaddedLabel(.paletteHint, size: 11)
        let button = NSButton(title: L10n.text(.paletteRun), target: self, action: #selector(accept(_:)))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        let footer = NSStackView(views: [hint, NSView(), button])
        let content = panel.contentView!
        for view in [search, scroll, empty, footer] { content.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: content.topAnchor, constant: 18), search.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18), search.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12), scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12), scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -10),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor), empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18), footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18), footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
        filter("")
    }
    required init?(coder: NSCoder) { fatalError() }

    func present(on parent: NSWindow, completion: @escaping (Entry?) -> Void) {
        self.completion = completion
        parent.beginSheet(window!)
        window?.makeFirstResponder(search)
    }

    func filter(_ query: String) {
        // Do not reset the field editor while an input method is composing a query.
        if search.stringValue != query { search.stringValue = query }
        results = entries.enumerated().compactMap { index, entry -> (Int, Int, Entry)? in
            guard let score = SearchMatcher.score(query, in: entry.title + " " + entry.keywords + " " + entry.detail) else { return nil }
            return (score, index, entry)
        }.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.prefix(100).map { $0.2 }
        table.reloadData()
        empty.isHidden = !results.isEmpty
        if !results.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false); table.scrollRowToVisible(0) }
        else { table.deselectAll(nil) }
    }

    func controlTextDidChange(_ obj: Notification) { filter(search.stringValue) }
    func numberOfRows(in tableView: NSTableView) -> Int { results.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = results[row]
        let title = PaddedLabel(entry.title, size: 13, weight: .medium, color: .labelColor)
        let detail = PaddedLabel(entry.detail, size: 10)
        let labels = NSStackView(views: [title, detail])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        let shortcut = PaddedLabel(entry.shortcut, size: 11)
        shortcut.setContentHuggingPriority(.required, for: .horizontal)
        let stack = NSStackView(views: [labels, NSView(), shortcut])
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 10)
        return stack
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveUp(_:)):
            guard !results.isEmpty else { return true }
            let row = min(results.count - 1, max(0, table.selectedRow + (selector == #selector(NSResponder.moveDown(_:)) ? 1 : -1)))
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        case #selector(NSResponder.insertNewline(_:)): accept(nil)
        case #selector(NSResponder.cancelOperation(_:)): dismiss(nil)
        default: return false
        }
        return true
    }

    @objc func accept(_ sender: Any?) {
        guard results.indices.contains(table.selectedRow) else { NSSound.beep(); return }
        dismiss(results[table.selectedRow])
    }
    func dismiss(_ entry: Entry?) {
        if let window { window.sheetParent?.endSheet(window); window.orderOut(nil) }
        let done = completion
        completion = nil
        done?(entry)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { dismiss(nil); return false }
}
