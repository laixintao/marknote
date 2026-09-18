import AppKit
import WebKit
import UniformTypeIdentifiers
import MarknoteCore

final class EditorWindowController: NSWindowController, NSTextViewDelegate, NSTextStorageDelegate, NSTableViewDataSource, NSTableViewDelegate, NSToolbarDelegate, WKNavigationDelegate, NSMenuItemValidation {
    let editor = MarkdownTextView()
    let preview: WKWebView
    let renderer = MarkdownRenderer()
    private let documentModel: MarkdownDocument
    private let rootSplit = NSSplitView()
    private let contentSplit = NSSplitView()
    private let sidebar = NSVisualEffectView()
    private let sourcePane = NSView()
    private let previewPane = NSView()
    private let outline = NSTableView()
    private let outlineEmpty = PaddedLabel(.outlineHint, size: 11)
    private let statistics = PaddedLabel("")
    private let position = PaddedLabel("")
    private let saveStatus = PaddedLabel(.unsaved, color: .tertiaryLabelColor)
    private let outlineCount = PaddedLabel("0", size: 10, weight: .medium, color: .tertiaryLabelColor)
    private let editorToggle = NSButton(title: "", target: nil, action: nil)
    private let previewToggle = NSButton(title: "", target: nil, action: nil)
    private var headings: [Heading] = []
    private var pendingUpdate: DispatchWorkItem?
    private var mode = 1
    private var previousMode = 1
    private var previousSidebar = true
    private var focused = false
    private var previewScroll: Double = 0
    private var previewRevision = 0
    var previewReady = false
    var isEditorVisible: Bool { !sourcePane.isHidden }
    var isPreviewVisible: Bool { !previewPane.isHidden }

    init(document: MarkdownDocument) {
        documentModel = document
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        preview = WKWebView(frame: .zero, configuration: configuration)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1220, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 780, height: 480)
        window.title = L10n.text(.appName)
        window.subtitle = L10n.text(.tagline)
        window.tabbingMode = .automatic
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.setFrameAutosaveName("MarknoteEditor")
        buildWindow()
        buildToolbar()
        reloadDocument()
        updatePosition()
        NotificationCenter.default.addObserver(self, selector: #selector(applyLocalization), name: LocalizationStore.didChange, object: L10n.shared)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func applyLocalization() {
        // Update labels in place; retain the NSTextView, composition, undo stack and selection.
        func updateLabels(_ view: NSView) {
            (view as? PaddedLabel)?.refreshLocalization()
            view.subviews.forEach(updateLabels)
        }
        if let content = window?.contentView { updateLabels(content) }
        window?.subtitle = L10n.text(.tagline)
        synchronizeWindowTitleWithDocumentName()
        outline.setAccessibilityLabel(L10n.text(.outline))
        editor.setAccessibilityLabel(L10n.text(.editorAccessibility))
        preview.setAccessibilityLabel(L10n.text(.previewAccessibility))
        buildToolbar()
        updateMetadata()
        updatePosition()
        refreshPreview()
    }

    private func buildWindow() {
        guard let container = window?.contentView else { return }
        rootSplit.isVertical = true
        rootSplit.dividerStyle = .thin
        contentSplit.isVertical = true
        contentSplit.dividerStyle = .thin
        rootSplit.addArrangedSubview(sidebar)
        rootSplit.addArrangedSubview(contentSplit)
        contentSplit.addArrangedSubview(sourcePane)
        contentSplit.addArrangedSubview(previewPane)
        rootSplit.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: 170), sidebar.widthAnchor.constraint(lessThanOrEqualToConstant: 290)])
        container.addSubview(rootSplit)
        let footer = NSView()
        container.addSubview(footer)
        rootSplit.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rootSplit.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor), rootSplit.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            rootSplit.trailingAnchor.constraint(equalTo: container.trailingAnchor), rootSplit.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor), footer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor), footer.heightAnchor.constraint(equalToConstant: 30)
        ])
        let separator = NSBox()
        separator.boxType = .separator
        footer.addSubview(separator)
        separator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([separator.topAnchor.constraint(equalTo: footer.topAnchor), separator.leadingAnchor.constraint(equalTo: footer.leadingAnchor), separator.trailingAnchor.constraint(equalTo: footer.trailingAnchor)])
        let footerStack = NSStackView(views: [statistics, NSView(), saveStatus, PaddedLabel("·"), position, PaddedLabel("·"), PaddedLabel("UTF-8  /  Markdown", size: 10)])
        footerStack.spacing = 12
        footer.addSubview(footerStack)
        pin(footerStack, to: footer, inset: NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16))
        buildSidebar()
        buildEditor()
        buildPreview()
        container.layoutSubtreeIfNeeded()
        rootSplit.setPosition(205, ofDividerAt: 0)
        contentSplit.setPosition(max(280, contentSplit.bounds.width / 2), ofDividerAt: 0)
    }

    private func buildSidebar() {
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        let logo = NSImageView(image: NSImage(systemSymbolName: "leaf", accessibilityDescription: L10n.text(.appName))!)
        logo.contentTintColor = .systemTeal
        let brand = NSStackView(views: [logo, PaddedLabel(.appName, size: 19, weight: .semibold, color: .labelColor), NSView()])
        brand.spacing = 9
        let subtitle = PaddedLabel("M A R K N O T E", size: 9, weight: .medium, color: .tertiaryLabelColor)
        let title = NSStackView(views: [PaddedLabel(.outline, size: 11, weight: .semibold), NSView(), outlineCount])
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("heading"))
        outline.addTableColumn(column)
        outline.headerView = nil
        outline.rowHeight = 34
        outline.backgroundColor = .clear
        outline.style = .sourceList
        outline.intercellSpacing = NSSize(width: 0, height: 2)
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(selectHeading)
        outline.setAccessibilityLabel(L10n.text(.outline))
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let hint = PaddedLabel(.focusHint, size: 10, color: .tertiaryLabelColor)
        for view in [brand, subtitle, title, scroll, outlineEmpty, hint] { sidebar.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            brand.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 27), brand.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 22), brand.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -16),
            logo.widthAnchor.constraint(equalToConstant: 24), logo.heightAnchor.constraint(equalToConstant: 26),
            subtitle.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 7), subtitle.leadingAnchor.constraint(equalTo: brand.leadingAnchor),
            title.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 36), title.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 20), title.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12), scroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 10), scroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -10), scroll.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -20),
            outlineEmpty.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 10), outlineEmpty.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18), outlineEmpty.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            hint.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -18), hint.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 20)
        ])
    }

    private func paneHeader(_ title: L10n.Key, detail: L10n.Key, parent: NSView) -> NSView {
        let header = NSView()
        parent.addSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([header.topAnchor.constraint(equalTo: parent.topAnchor), header.leadingAnchor.constraint(equalTo: parent.leadingAnchor), header.trailingAnchor.constraint(equalTo: parent.trailingAnchor), header.heightAnchor.constraint(equalToConstant: 42)])
        let stack = NSStackView(views: [PaddedLabel(title, size: 10, weight: .medium), NSView(), PaddedLabel(detail, size: 10, color: .tertiaryLabelColor)])
        header.addSubview(stack)
        pin(stack, to: header, inset: NSEdgeInsets(top: 0, left: 24, bottom: 0, right: 24))
        let line = NSBox()
        line.boxType = .separator
        header.addSubview(line)
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([line.bottomAnchor.constraint(equalTo: header.bottomAnchor), line.leadingAnchor.constraint(equalTo: header.leadingAnchor), line.trailingAnchor.constraint(equalTo: header.trailingAnchor)])
        return header
    }

    private func buildEditor() {
        let header = paneHeader(.sourceHeader, detail: .sourceDetail, parent: sourcePane)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 27, height: 32)
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.usesFindBar = true
        editor.isIncrementalSearchingEnabled = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.fontSize = CGFloat(UserDefaults.standard.double(forKey: "editorFontSize").clamped(to: 12...24, fallback: 14))
        editor.backgroundColor = .textBackgroundColor
        editor.insertionPointColor = .systemTeal
        editor.delegate = self
        editor.textStorage?.delegate = self
        editor.setAccessibilityLabel(L10n.text(.editorAccessibility))
        editor.onAppearanceChange = { [weak self] in self?.refreshPreview() }
        scroll.documentView = editor
        sourcePane.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: header.bottomAnchor), scroll.bottomAnchor.constraint(equalTo: sourcePane.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: sourcePane.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: sourcePane.trailingAnchor)])
    }

    private func buildPreview() {
        let header = paneHeader(.previewHeader, detail: .previewDetail, parent: previewPane)
        preview.navigationDelegate = self
        preview.setAccessibilityLabel(L10n.text(.previewAccessibility))
        previewPane.addSubview(preview)
        preview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([preview.topAnchor.constraint(equalTo: header.bottomAnchor), preview.bottomAnchor.constraint(equalTo: previewPane.bottomAnchor), preview.leadingAnchor.constraint(equalTo: previewPane.leadingAnchor), preview.trailingAnchor.constraint(equalTo: previewPane.trailingAnchor)])
    }

    private func pin(_ child: NSView, to parent: NSView, inset: NSEdgeInsets = NSEdgeInsetsZero) {
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset.top), child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset.bottom), child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset.left), child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset.right)])
    }

    private func buildToolbar() {
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        ["sidebar", .flexibleSpace, "bold", "italic", "link", "insert", .flexibleSpace, "editor", "preview", "focus", "export"]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        if identifier.rawValue == "editor" || identifier.rawValue == "preview" {
            let isEditor = identifier.rawValue == "editor"
            let button = isEditor ? editorToggle : previewToggle
            let action = isEditor ? #selector(toggleEditorPane) : #selector(togglePreviewPane)
            button.title = L10n.text(isEditor ? .editorToggle : .previewToggle)
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .texturedRounded
            button.image = NSImage(systemSymbolName: isEditor ? "square.and.pencil" : "eye", accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.target = self
            button.action = action
            button.state = (isEditor ? isEditorVisible : isPreviewVisible) ? .on : .off
            button.toolTip = L10n.text(isEditor ? .editorToggleHelp : .previewToggleHelp)
            button.setAccessibilityLabel(button.title)
            item.view = button
            item.label = button.title
            item.toolTip = button.toolTip
            let menuItem = NSMenuItem(title: button.title, action: action, keyEquivalent: "")
            menuItem.target = self
            item.menuFormRepresentation = menuItem
            return item
        }
        if identifier.rawValue == "insert" || identifier.rawValue == "export" {
            let menuItem = NSMenuToolbarItem(itemIdentifier: identifier)
            menuItem.image = NSImage(systemSymbolName: identifier.rawValue == "insert" ? "plus.square" : "square.and.arrow.up", accessibilityDescription: nil)
            menuItem.label = identifier.rawValue == "insert" ? L10n.text(.insert) : L10n.text(.export)
            menuItem.toolTip = menuItem.label
            menuItem.menu = NSMenu()
            let entries: [(String, Selector)] = identifier.rawValue == "insert" ? [
                (L10n.text(.heading), #selector(insertHeading)), (L10n.text(.list), #selector(insertList)), (L10n.text(.task), #selector(insertTask)),
                (L10n.text(.quote), #selector(insertQuote)), (L10n.text(.code), #selector(insertCode)), (L10n.text(.table), #selector(insertTable))
            ] : [(L10n.text(.exportHTML), #selector(exportHTML)), (L10n.text(.exportPDF), #selector(exportPDF))]
            for (title, action) in entries {
                let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
                entry.target = self
                menuItem.menu.addItem(entry)
            }
            return menuItem
        }
        let values: [String: (String, String, Selector)] = [
            "sidebar": ("sidebar.left", L10n.text(.sidebarHelp), #selector(toggleSidebar)),
            "bold": ("bold", L10n.text(.boldHelp), #selector(toggleBold)),
            "italic": ("italic", L10n.text(.italicHelp), #selector(toggleItalic)),
            "link": ("link", L10n.text(.linkHelp), #selector(insertLink)),
            "focus": ("viewfinder", L10n.text(.focusHelp), #selector(toggleFocus))
        ]
        guard let (symbol, title, action) = values[identifier.rawValue] else { return nil }
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.label = title
        item.toolTip = title
        item.target = self
        item.action = action
        return item
    }

    func reloadDocument() {
        editor.string = documentModel.text
        editor.highlight()
        updateMetadata()
        refreshPreview()
    }

    func textDidChange(_ notification: Notification) {
        synchronizeText()
    }

    func undoManager(for view: NSTextView) -> UndoManager? { documentModel.undoManager }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        if editedMask.contains(.editedCharacters) { synchronizeText() }
    }

    private func synchronizeText() {
        documentModel.text = editor.string
        // NSDocument tracks edits via its shared undo manager, including undo and redo.
        saveStatus.stringValue = L10n.text(.modified)
        pendingUpdate?.cancel()
        let update = DispatchWorkItem { [weak self] in
            guard let self, !self.editor.hasMarkedText() else { return }
            self.editor.highlight()
            self.updateMetadata()
            self.refreshPreview()
        }
        pendingUpdate = update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: update)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updatePosition()
    }

    private func updatePosition() {
        let source = editor.string as NSString
        let location = min(editor.selectedRange().location, source.length)
        let before = source.substring(to: location)
        let line = before.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        let column = (before.split(separator: "\n", omittingEmptySubsequences: false).last?.count ?? 0) + 1
        position.stringValue = L10n.text(.position, line, column)
    }

    private func updateMetadata() {
        headings = MarkdownText.headings(in: editor.string)
        outline.reloadData()
        outlineCount.stringValue = "\(headings.count)"
        outlineEmpty.isHidden = !headings.isEmpty
        let words = MarkdownText.wordCount(editor.string)
        statistics.stringValue = L10n.text(.statistics, words, editor.string.count, max(1, (words + 299) / 300))
    }

    func refreshPreview() {
        previewRevision += 1
        let revision = previewRevision
        previewReady = false
        let dark = window?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let html = renderer.page(documentModel.text, title: documentModel.displayName, relativeTo: documentModel.fileURL?.deletingLastPathComponent(), dark: dark)
        preview.evaluateJavaScript("window.scrollY") { [weak self] value, _ in
            guard let self, self.previewRevision == revision else { return }
            if let y = value as? Double { self.previewScroll = y }
            self.previewReady = false
            self.preview.loadHTMLString(html, baseURL: nil)
        }
        saveStatus.stringValue = documentModel.isDocumentEdited ? L10n.text(.modified) : (documentModel.fileURL == nil ? L10n.text(.unsaved) : L10n.text(.saved))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        previewReady = true
        webView.evaluateJavaScript("window.scrollTo(0, \(previewScroll))", completionHandler: nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated else { decisionHandler(.allow); return }
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "about", url.fragment != nil { decisionHandler(.allow); return }
        if ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        decisionHandler(.cancel)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { headings.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let heading = headings[row]
        let label = PaddedLabel(String(repeating: "   ", count: min(heading.level - 1, 3)) + heading.title, size: 12, weight: heading.level == 1 ? .medium : .regular, color: heading.level == 1 ? .labelColor : .secondaryLabelColor)
        label.toolTip = heading.title
        let cell = NSTableCellView()
        cell.addSubview(label)
        pin(label, to: cell, inset: NSEdgeInsets(top: 8, left: 8, bottom: 6, right: 4))
        return cell
    }

    @objc func selectHeading() {
        guard headings.indices.contains(outline.selectedRow) else { return }
        if mode == 2 { setMode(1) }
        let range = headings[outline.selectedRow].range
        window?.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: range.location, length: 0))
        editor.scrollRangeToVisible(range)
        editor.showFindIndicator(for: range)
    }

    @objc func toggleSidebar() {
        sidebar.isHidden.toggle()
        rootSplit.adjustSubviews()
        if !sidebar.isHidden { rootSplit.setPosition(205, ofDividerAt: 0) }
    }
    @objc func toggleEditorPane() {
        setMode(isEditorVisible ? 2 : 1)
    }
    @objc func togglePreviewPane() {
        setMode(isPreviewVisible ? 0 : 1)
    }
    @objc func showEditor() { setMode(0) }
    @objc func showSplit() { setMode(1) }
    @objc func showPreview() { setMode(2) }
    func setMode(_ value: Int) {
        if focused && value != 0 {
            focused = false
            sidebar.isHidden = !previousSidebar
            rootSplit.adjustSubviews()
            if !sidebar.isHidden { rootSplit.setPosition(205, ofDividerAt: 0) }
        }
        mode = value
        sourcePane.isHidden = value == 2
        previewPane.isHidden = value == 0
        editorToggle.state = isEditorVisible ? .on : .off
        previewToggle.state = isPreviewVisible ? .on : .off
        contentSplit.adjustSubviews()
        if value == 1 { contentSplit.setPosition(contentSplit.bounds.width / 2, ofDividerAt: 0) }
        if value != 2 { window?.makeFirstResponder(editor) }
        else { window?.makeFirstResponder(preview) }
    }
    @objc func toggleFocus() {
        if focused {
            focused = false
            sidebar.isHidden = !previousSidebar
            setMode(previousMode)
        } else {
            previousMode = mode
            previousSidebar = !sidebar.isHidden
            sidebar.isHidden = true
            setMode(0)
            focused = true
        }
        rootSplit.adjustSubviews()
        if !sidebar.isHidden { rootSplit.setPosition(205, ofDividerAt: 0) }
    }
    private func apply(_ edit: TextEdit, name: String) {
        if mode == 2 { setMode(1) }
        window?.makeFirstResponder(editor)
        editor.apply(edit, name: name)
    }
    @objc func toggleBold() { apply(MarkdownText.wrap(editor.string, selection: editor.selectedRange(), marker: "**", placeholder: L10n.text(.boldPlaceholder)), name: L10n.text(.bold)) }
    @objc func toggleItalic() { apply(MarkdownText.wrap(editor.string, selection: editor.selectedRange(), marker: "*", placeholder: L10n.text(.italicPlaceholder)), name: L10n.text(.italic)) }
    @objc func insertHeading() { prefix("# ", name: L10n.text(.heading)) }
    @objc func insertList() { prefix("- ", name: L10n.text(.list)) }
    @objc func insertTask() { prefix("- [ ] ", name: L10n.text(.task)) }
    @objc func insertQuote() { prefix("> ", name: L10n.text(.quote)) }
    private func prefix(_ prefix: String, name: String) { apply(MarkdownText.prefixLines(editor.string, selection: editor.selectedRange(), prefix: prefix), name: name) }
    @objc func insertLink() {
        let range = editor.selectedRange()
        let label = range.length == 0 ? L10n.text(.linkPlaceholder) : (editor.string as NSString).substring(with: range)
        let text = "[\(label)](https://example.com)"
        apply(TextEdit(range: range, replacement: text, selection: NSRange(location: range.location + label.utf16.count + 3, length: 19)), name: L10n.text(.insertLink))
    }
    @objc func insertCode() {
        let range = editor.selectedRange()
        let code = range.length == 0 ? L10n.text(.codePlaceholder) : (editor.string as NSString).substring(with: range)
        let lead = range.location > 0 && (editor.string as NSString).substring(with: NSRange(location: range.location - 1, length: 1)) != "\n" ? "\n" : ""
        apply(TextEdit(range: range, replacement: lead + "```\n" + code + "\n```\n", selection: NSRange(location: range.location + lead.utf16.count + 4, length: code.utf16.count)), name: L10n.text(.code))
    }
    @objc func insertTable() {
        let range = editor.selectedRange()
        let heading = L10n.text(.tableHeading)
        let cell = L10n.text(.tableCell)
        let value = "\n| \(heading) | \(heading) |\n| --- | --- |\n| \(cell) | \(cell) |\n"
        apply(TextEdit(range: range, replacement: value, selection: NSRange(location: range.location + 3, length: heading.utf16.count)), name: L10n.text(.table))
    }
    @objc func increaseFont() { changeFontSize(1) }
    @objc func decreaseFont() { changeFontSize(-1) }
    private func changeFontSize(_ delta: CGFloat) {
        editor.fontSize = min(24, max(12, editor.fontSize + delta))
        UserDefaults.standard.set(editor.fontSize, forKey: "editorFontSize")
        editor.highlight()
    }

    @objc func findInDocument(_ sender: Any?) {
        if mode == 2 { setMode(1) }
        window?.makeFirstResponder(editor)
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        editor.performFindPanelAction(item)
    }

    @objc func exportHTML() {
        exportPanel(ext: "html") { [weak self] url in
            guard let self else { return }
            do {
                let html = self.renderer.page(self.documentModel.text, title: self.documentModel.displayName, relativeTo: self.documentModel.fileURL?.deletingLastPathComponent())
                try html.write(to: url, atomically: true, encoding: .utf8)
            } catch { self.documentModel.presentError(error) }
        }
    }

    @objc func exportPDF() {
        // Always render current text first, including edits still waiting for the debounce.
        pendingUpdate?.cancel()
        updateMetadata()
        refreshPreview()
        exportPanel(ext: "pdf") { [weak self] url in self?.writePDF(to: url) }
    }

    private func writePDF(to url: URL, attempts: Int = 0) {
        guard previewReady else {
            guard attempts < 100 else { documentModel.presentError(NSError(domain: "Marknote", code: 3, userInfo: [NSLocalizedDescriptionKey: L10n.text(.previewNotReady)])); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.writePDF(to: url, attempts: attempts + 1) }
            return
        }
        preview.createPDF(configuration: WKPDFConfiguration()) { [weak self] result in
            do { try result.get().write(to: url, options: .atomic) }
            catch { self?.documentModel.presentError(error) }
        }
    }

    private func exportPanel(ext: String, completion: @escaping (URL) -> Void) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ext)!]
        panel.nameFieldStringValue = ((documentModel.displayName ?? L10n.text(.untitled)) as NSString).deletingPathExtension + "." + ext
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url { completion(url) }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleEditorPane): menuItem.state = isEditorVisible ? .on : .off
        case #selector(togglePreviewPane): menuItem.state = isPreviewVisible ? .on : .off
        case #selector(showEditor): menuItem.state = mode == 0 ? .on : .off
        case #selector(showSplit): menuItem.state = mode == 1 ? .on : .off
        case #selector(showPreview): menuItem.state = mode == 2 ? .on : .off
        case #selector(toggleFocus): menuItem.state = focused ? .on : .off
        case #selector(toggleSidebar): menuItem.state = sidebar.isHidden ? .off : .on
        default: break
        }
        return true
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>, fallback: Double) -> Double {
        range.contains(self) ? self : fallback
    }
}

extension NSToolbarItem.Identifier: @retroactive ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.init(value) }
}
