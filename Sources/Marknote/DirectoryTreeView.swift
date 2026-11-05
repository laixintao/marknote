import AppKit
import MarknoteCore

/// Shared by the documents in a tab group; each document retains its own editor and undo history.
@MainActor final class DirectoryWorkspace {
    let rootURL: URL
    var expandedDirectories = Set<URL>()

    init(rootURL: URL) { self.rootURL = rootURL.standardizedFileURL }
}

@MainActor final class DirectoryTreeView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    final class Node {
        let url: URL
        let isDirectory: Bool
        var children: [Node]?
        init(url: URL, isDirectory: Bool) { self.url = url; self.isDirectory = isDirectory }
    }

    private final class Tree: NSOutlineView {
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 || event.keyCode == 76 {
                if let action { sendAction(action, to: target) }
            } else { super.keyDown(with: event) }
        }
    }

    let tree: NSOutlineView = Tree()
    private let folderName = PaddedLabel(.files, size: 11, weight: .semibold)
    private let message = PaddedLabel(.folderHint, size: 11)
    private let openButton = NSButton()
    private let refreshButton = NSButton()
    private var root: Node?
    private var restoring = false
    private(set) var workspace: DirectoryWorkspace?
    var onOpenFolder: (() -> Void)?
    var onOpenFile: ((URL) -> Void)?
    var currentFile: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        tree.addTableColumn(column)
        tree.outlineTableColumn = column
        tree.headerView = nil
        tree.rowHeight = 28
        tree.indentationPerLevel = 14
        tree.style = .sourceList
        tree.backgroundColor = .clear
        tree.dataSource = self
        tree.delegate = self
        tree.target = self
        tree.action = #selector(openSelection)
        tree.allowsEmptySelection = true
        tree.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tree.setAccessibilityIdentifier("directoryTree")
        let scroll = NSScrollView()
        scroll.documentView = tree
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        for (button, symbol, action) in [(openButton, "folder.badge.plus", #selector(chooseFolder)), (refreshButton, "arrow.clockwise", #selector(refresh))] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.imagePosition = .imageOnly
            button.isBordered = false
            button.bezelStyle = .inline
            button.target = self
            button.action = action
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        }
        folderName.lineBreakMode = .byTruncatingMiddle
        folderName.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [folderName, openButton, refreshButton])
        header.spacing = 4
        message.maximumNumberOfLines = 3
        message.lineBreakMode = .byWordWrapping
        let separator = NSBox()
        separator.boxType = .separator
        for view in [header, scroll, message, separator] { addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor), header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10), scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor), scroll.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -10),
            message.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 8), message.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), message.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10), separator.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        applyLocalization()
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyLocalization() {
        folderName.stringValue = workspace?.rootURL.lastPathComponent ?? L10n.text(.files)
        tree.setAccessibilityLabel(L10n.text(.files))
        openButton.toolTip = L10n.text(.openFolder)
        openButton.setAccessibilityLabel(L10n.text(.openFolder))
        refreshButton.toolTip = L10n.text(.refreshFiles)
        refreshButton.setAccessibilityLabel(L10n.text(.refreshFiles))
        message.stringValue = L10n.text(workspace == nil ? .folderHint : .folderEmpty)
    }

    func setWorkspace(_ workspace: DirectoryWorkspace) {
        self.workspace = workspace
        refresh()
    }

    @objc private func chooseFolder() { onOpenFolder?() }

    @objc func refresh() {
        guard let workspace else { return }
        restoring = true
        defer { restoring = false }
        folderName.stringValue = workspace.rootURL.lastPathComponent
        folderName.toolTip = workspace.rootURL.path
        message.stringValue = L10n.text(.folderEmpty)
        root = Node(url: workspace.rootURL, isDirectory: true)
        // Reveal the active file without changing the root when navigating into subfolders.
        let rootPrefix = workspace.rootURL.path == "/" ? "/" : workspace.rootURL.path + "/"
        if let currentFile, currentFile.standardizedFileURL.path.hasPrefix(rootPrefix) {
            var parent = currentFile.deletingLastPathComponent().standardizedFileURL
            while parent != workspace.rootURL && parent.path != "/" {
                workspace.expandedDirectories.insert(parent)
                parent.deleteLastPathComponent()
            }
        }
        tree.reloadData()
        var row = 0
        while row < tree.numberOfRows {
            if let node = tree.item(atRow: row) as? Node, node.isDirectory, workspace.expandedDirectories.contains(node.url) { tree.expandItem(node) }
            row += 1
        }
        tree.deselectAll(nil)
        if let currentFile, let row = (0..<tree.numberOfRows).first(where: { (tree.item(atRow: $0) as? Node)?.url == currentFile.standardizedFileURL }) {
            tree.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tree.scrollRowToVisible(row)
        }
        message.isHidden = tree.numberOfRows > 0 && message.stringValue == L10n.text(.folderEmpty)
    }

    private func children(of node: Node?) -> [Node] {
        guard let node = node ?? root else { return [] }
        if let children = node.children { return children }
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: node.url, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isPackageKey], options: [.skipsHiddenFiles])
            let children = urls.compactMap { url -> Node? in
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isPackageKey]), values.isPackage != true else { return nil }
                if values.isDirectory == true { return Node(url: url.standardizedFileURL, isDirectory: true) }
                guard values.isRegularFile == true, (MarkdownFileAssociation.extensions + ["txt"]).contains(url.pathExtension.lowercased()) else { return nil }
                return Node(url: url.standardizedFileURL, isDirectory: false)
            }.sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
            node.children = children
            return children
        } catch {
            node.children = []
            message.stringValue = error.localizedDescription
            message.isHidden = false
            return []
        }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { children(of: item as? Node).count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { children(of: item as? Node)[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? Node)?.isDirectory == true }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        let cell = NSTableCellView()
        let icon = NSImageView(image: NSImage(systemSymbolName: node.isDirectory ? "folder" : "doc.text", accessibilityDescription: nil)!)
        icon.contentTintColor = node.isDirectory ? .systemTeal : .secondaryLabelColor
        let label = PaddedLabel(node.url.lastPathComponent, size: 12, color: .labelColor)
        label.lineBreakMode = .byTruncatingMiddle
        cell.textField = label
        cell.imageView = icon
        cell.toolTip = node.url.path
        for view in [icon, label] { cell.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7), label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !restoring, let node = notification.userInfo?["NSObject"] as? Node else { return }
        workspace?.expandedDirectories.insert(node.url)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !restoring, let node = notification.userInfo?["NSObject"] as? Node else { return }
        workspace?.expandedDirectories.remove(node.url)
    }

    @objc private func openSelection() {
        guard let node = tree.item(atRow: tree.selectedRow) as? Node else { return }
        if node.isDirectory {
            if tree.isItemExpanded(node) { tree.collapseItem(node) } else { tree.expandItem(node) }
        } else { onOpenFile?(node.url) }
    }
}
