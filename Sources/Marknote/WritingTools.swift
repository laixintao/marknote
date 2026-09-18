import AppKit
import UniformTypeIdentifiers
import MarknoteCore

extension EditorWindowController {
    @objc func formatTable() {
        guard !editor.hasMarkedText(), let edit = MarkdownTable.format(editor.string, selection: editor.selectedRange()) else { NSSound.beep(); return }
        apply(edit, name: L10n.text(.formatTable))
    }

    @objc func toggleParagraphFocus() {
        editor.paragraphFocus.toggle()
        UserDefaults.standard.set(editor.paragraphFocus, forKey: "paragraphFocus")
    }

    @objc func toggleTypewriterScrolling() {
        editor.typewriterScrolling.toggle()
        UserDefaults.standard.set(editor.typewriterScrolling, forKey: "typewriterScrolling")
    }

    @objc func insertImage() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.text(.insertImage)
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        let selection = editor.selectedRange()
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            do { self.importImages(try ImageImport.read(files: panel.urls), at: selection) }
            catch { self.documentModel.presentError(error) }
        }
    }

    func importImages(_ images: [ImageAttachment], at selection: NSRange) {
        guard !images.isEmpty, !editor.hasMarkedText() else { return }
        guard documentModel.fileURL != nil else {
            guard let window, pendingImageInsertion == nil else { return }
            pendingImageInsertion = (images, selection)
            let alert = NSAlert()
            alert.messageText = L10n.text(.imageSaveFirst)
            alert.informativeText = L10n.text(.imageSaveDetail)
            alert.addButton(withTitle: L10n.text(.saveAndInsert))
            alert.addButton(withTitle: L10n.text(.cancel))
            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self else { return }
                if response == .alertFirstButtonReturn {
                    self.documentModel.save(withDelegate: self, didSave: #selector(self.finishedSavingForImages(_:didSave:contextInfo:)), contextInfo: nil)
                } else { self.pendingImageInsertion = nil }
            }
            return
        }
        do {
            let references = try AttachmentStore.store(images, beside: documentModel.fileURL)
            let source = editor.string as NSString
            let range = selection.location <= source.length && selection.length <= source.length - selection.location ? selection : editor.selectedRange()
            let lead = range.location > 0 && source.substring(with: NSRange(location: range.location - 1, length: 1)) != "\n" ? "\n" : ""
            let value = lead + references.joined(separator: "\n\n") + "\n"
            apply(TextEdit(range: range, replacement: value, selection: NSRange(location: range.location + value.utf16.count, length: 0)), name: L10n.text(.insertImage))
        } catch { documentModel.presentError(error) }
    }

    @objc private func finishedSavingForImages(_ document: NSDocument, didSave: Bool, contextInfo: UnsafeMutableRawPointer?) {
        let pending = pendingImageInsertion
        pendingImageInsertion = nil
        if didSave, let (images, range) = pending { importImages(images, at: range) }
    }

    @objc func showCommandPalette() {
        var entries: [CommandPalette.Entry] = []
        func command(_ id: String, _ title: L10n.Key, _ group: L10n.Key, _ keywords: String, _ shortcut: String = "", _ action: @escaping (EditorWindowController) -> Void) {
            entries.append(.init(id: id, title: L10n.text(title), detail: L10n.text(group), keywords: keywords, shortcut: shortcut, perform: { [weak self] in if let self { action(self) } }))
        }
        command("quick-open", .quickOpen, .menuFile, "open file switch 打开 文件 切换", "⇧⌘O") { $0.showQuickOpen() }
        command("new", .newDocument, .menuFile, "new document 新建 文稿", "⌘N") { _ in documentController.newDocument(nil) }
        command("save", .save, .menuFile, "save 保存", "⌘S") { $0.documentModel.save(nil) }
        command("find", .find, .menuEdit, "find search replace 查找 搜索 替换", "⌘F") { $0.findInDocument(nil) }
        command("edit", .editorOnly, .menuView, "editor only 编辑 模式", "⌃⌘1") { $0.showEditor() }
        command("split", .splitView, .menuView, "split 分栏 双栏 模式", "⌃⌘2") { $0.showSplit() }
        command("preview", .previewOnly, .menuView, "preview reading 预览 阅读 模式", "⌃⌘3") { $0.showPreview() }
        command("focus", .focus, .menuView, "focus 专注", "⇧⌘F") { $0.toggleFocus() }
        command("paragraph", .paragraphFocus, .menuView, "paragraph focus 段落 聚焦") { $0.toggleParagraphFocus() }
        command("typewriter", .typewriterScrolling, .menuView, "typewriter scrolling 打字机 滚动") { $0.toggleTypewriterScrolling() }
        command("outline", .outline, .menuView, "outline toc sidebar 目录 大纲 侧栏", "⌥⌘0") { $0.toggleSidebar() }
        command("image", .insertImage, .menuFormat, "image picture screenshot 图片 截图", "⇧⌘I") { $0.insertImage() }
        command("table", .table, .menuFormat, "insert table 表格 插入") { $0.insertTable() }
        if MarkdownTable.format(editor.string, selection: editor.selectedRange()) != nil {
            command("format-table", .formatTable, .menuFormat, "format align table 整理 对齐 表格", "⌥⌘T") { $0.formatTable() }
        }
        command("bold", .bold, .menuFormat, "bold 加粗", "⌘B") { $0.toggleBold() }
        command("italic", .italic, .menuFormat, "italic 斜体", "⌘I") { $0.toggleItalic() }
        command("link", .insertLink, .menuFormat, "link url 链接 网址", "⌘K") { $0.insertLink() }
        command("heading", .heading, .menuFormat, "heading 标题", "⌥⌘1") { $0.insertHeading() }
        command("list", .list, .menuFormat, "list 列表", "⇧⌘L") { $0.insertList() }
        command("task", .task, .menuFormat, "task checkbox 待办 任务", "⇧⌘T") { $0.insertTask() }
        command("quote", .quote, .menuFormat, "quote 引用") { $0.insertQuote() }
        command("code", .code, .menuFormat, "code fence 代码") { $0.insertCode() }
        command("html", .exportHTML, .menuFile, "export html 导出") { $0.exportHTML() }
        command("pdf", .exportPDF, .menuFile, "export pdf 导出", "⇧⌘E") { $0.exportPDF() }
        let recent = UserDefaults.standard.stringArray(forKey: "recentCommands") ?? []
        entries = entries.enumerated().sorted { a, b in
            (recent.firstIndex(of: a.element.id) ?? 1000, a.offset) < (recent.firstIndex(of: b.element.id) ?? 1000, b.offset)
        }.map(\.element)
        presentPalette(title: .commandPalette, placeholder: .commandSearch, entries: entries, rememberCommands: true)
    }

    @objc func showQuickOpen() {
        var entries: [CommandPalette.Entry] = []
        var seen = Set<String>()
        for case let document as MarkdownDocument in documentController.documents {
            let path = document.fileURL?.standardizedFileURL.path
            if let path { seen.insert(path) }
            entries.append(.init(id: path ?? "untitled-\(ObjectIdentifier(document))", title: document.displayName,
                                 detail: L10n.text(.openDocumentGroup) + (path.map { " · " + $0 } ?? ""), keywords: "", shortcut: "", perform: { [weak document] in document?.showWindows() }))
        }
        func append(_ url: URL, group: L10n.Key) {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted, FileManager.default.fileExists(atPath: path) else { return }
            entries.append(.init(id: path, title: url.lastPathComponent, detail: L10n.text(group) + " · " + url.deletingLastPathComponent().path, keywords: "", shortcut: "", perform: { [weak self] in
                documentController.openDocument(withContentsOf: url, display: true) { _, _, error in
                    if let error { self?.documentModel.presentError(error) }
                }
            }))
        }
        for url in documentController.recentDocumentURLs { append(url, group: .recentDocumentGroup) }
        if let directory = documentModel.fileURL?.deletingLastPathComponent(),
           let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]) {
            var nearby: [URL] = []
            for case let url as URL in enumerator {
                if MarkdownFileAssociation.extensions.contains(url.pathExtension.lowercased()), (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { nearby.append(url) }
                if nearby.count >= 1000 { break }
            }
            for url in nearby.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) { append(url, group: .nearbyDocumentGroup) }
        }
        presentPalette(title: .quickOpen, placeholder: .fileSearch, entries: entries, rememberCommands: false)
    }

    private func presentPalette(title: L10n.Key, placeholder: L10n.Key, entries: [CommandPalette.Entry], rememberCommands: Bool) {
        guard let window, activePalette == nil, window.attachedSheet == nil else { return }
        let palette = CommandPalette(title: L10n.text(title), placeholder: L10n.text(placeholder), entries: entries)
        activePalette = palette
        palette.present(on: window) { [weak self] entry in
            self?.activePalette = nil
            guard let entry else { return }
            if rememberCommands {
                let recent = UserDefaults.standard.stringArray(forKey: "recentCommands") ?? []
                UserDefaults.standard.set(Array(([entry.id] + recent.filter { $0 != entry.id }).prefix(12)), forKey: "recentCommands")
            }
            DispatchQueue.main.async { entry.perform() }
        }
    }
}
