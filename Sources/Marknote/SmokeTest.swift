import AppKit
import WebKit
import PDFKit
import MarknoteCore

/// Invoked explicitly by Scripts/smoke-test.sh; uses the same document, editor and WebKit as the app.
@MainActor enum SmokeTest {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func run(in directory: URL) async {
        setbuf(stdout, nil)
        DispatchQueue.global().asyncAfter(deadline: .now() + 90) {
            fputs("FAIL: Native integration test exceeded 90 seconds\n", stderr)
            let sample = Process()
            sample.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
            sample.arguments = [String(ProcessInfo.processInfo.processIdentifier), "1", "1", "-file", directory.appendingPathComponent("timeout.log").path]
            if (try? sample.run()) != nil { sample.waitUntilExit() }
            exit(1)
        }
        var checks: [String] = []
        func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
            guard condition() else { throw Failure(message: name) }
            checks.append(name)
            print("PASS: \(name)")
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            L10n.shared.select(.simplifiedChinese)
            UserDefaults.standard.set(false, forKey: "paragraphFocus")
            UserDefaults.standard.set(false, forKey: "typewriterScrolling")
            let markdownTypes = MarkdownFileAssociation.contentTypes
            try check(!markdownTypes.isEmpty && markdownTypes.allSatisfy { !["public.plain-text", "public.text", "public.data"].contains($0.identifier) }, "默认打开方式只针对 Markdown 类型")
            var requestedTypes: [String] = []
            try await MarkdownFileAssociation.setDefault { application, type in
                try check(application == Bundle.main.bundleURL, "默认打开方式使用当前应用路径")
                requestedTypes.append(type.identifier)
            }
            try check(requestedTypes == markdownTypes.map(\.identifier), "默认打开方式依次设置去重后的 Markdown 类型")
            var caughtFailure = false
            do {
                try await MarkdownFileAssociation.setDefault { _, _ in throw Failure(message: "Simulated system refusal") }
            } catch { caughtFailure = true }
            try check(caughtFailure, "系统拒绝更改默认应用时向界面传递错误")
            var document = try documentController.makeUntitledDocument(ofType: MarkdownDocument.typeName) as! MarkdownDocument
            document.text = "# 验证文稿\n\n中文与 emoji 🌱\n\n- [ ] 任务\n"
            documentController.addDocument(document)
            document.makeWindowControllers()
            document.showWindows()
            var controller = document.windowControllers.first as! EditorWindowController
            var editor = controller.editor
            controller.window?.makeKeyAndOrderFront(nil)
            try await Task.sleep(nanoseconds: 300_000_000)
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            controller.window?.orderFrontRegardless()
            controller.window?.makeMain()
            controller.window?.makeKey()
            controller.window?.makeFirstResponder(editor)
            try check(editor.string == document.text, "原生编辑器载入中文与 emoji")
            let range = (editor.string as NSString).range(of: "中文与 emoji 🌱")
            editor.setSelectedRange(range)
            try check(editor.tryToPerform(#selector(EditorWindowController.toggleBold), with: nil), "当前窗口响应链调用格式命令")
            try check(document.text.contains("**中文与 emoji 🌱**"), "加粗操作同步至文档模型")
            editor.breakUndoCoalescing()
            try await Task.sleep(nanoseconds: 250_000_000)
            try check(editor.undoManager?.canUndo == true, "编辑操作可撤销")
            editor.undoManager?.undo()
            try check(!document.text.contains("**"), "撤销恢复原始文本")
            try check(!document.isDocumentEdited, "撤销回初始内容后恢复未修改状态")
            editor.undoManager?.redo()
            try check(document.text.contains("**中文与 emoji 🌱**"), "重做恢复格式")
            let task = (editor.string as NSString).range(of: "- [ ] 任务")
            editor.setSelectedRange(NSRange(location: NSMaxRange(task), length: 0))
            editor.insertNewline(nil)
            try check(document.text.contains("- [ ] 任务\n- [ ] "), "待办列表自动续写")
            editor.insertNewline(nil)
            try check(!document.text.contains("\n- [ ] \n"), "空列表回车退出列表")
            try await settleEditing(editor, document: document)
            let url = directory.appendingPathComponent("roundtrip.md")
            try await save(document, to: url)
            let saved = try String(contentsOf: url, encoding: .utf8)
            try check(saved == document.text, "NSDocument 保存 UTF-8 文件")
            try check(!document.isDocumentEdited, "保存后清除未保存标记")
            document.close()
            document = try await openDocument(url)
            controller = document.windowControllers.first as! EditorWindowController
            editor = controller.editor
            try check(document.text == saved, "通过系统文档控制器重新打开文件内容完全一致")
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
            editor.insertText("\n自动保存验证", replacementRange: editor.selectedRange())
            try await settleEditing(editor, document: document)
            try await autosave(document)
            let autosaved = try String(contentsOf: url, encoding: .utf8)
            try check(autosaved == document.text, "系统原位自动保存写入最新编辑")
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
            editor.setMarkedText("zhongwen", selectedRange: NSRange(location: 8, length: 0), replacementRange: editor.selectedRange())
            try await Task.sleep(nanoseconds: 250_000_000)
            try check(editor.hasMarkedText(), "语法高亮不会中断输入法组合文本")
            editor.insertText("中文输入🌱", replacementRange: editor.markedRange())
            try check(!editor.hasMarkedText() && document.text.hasSuffix("中文输入🌱"), "输入法提交中文与 emoji 后同步文稿")
            try await verifyLanguageAndPanes(document: document, controller: controller, directory: directory) { try check($0, $1) }
            try await verifyOutlineNavigation { try check($0, $1) }
            try await verifyWritingTools(in: directory) { try check($0, $1) }
            controller.showEditor()
            controller.showPreview()
            controller.showSplit()
            controller.toggleFocus()
            controller.toggleFocus()
            controller.toggleSidebar()
            controller.toggleSidebar()
            try check(controller.window?.isVisible == true, "显示模式与专注模式切换后窗口正常")
            document.text = welcomeMarkdown
            controller.reloadDocument()
            try await waitForPreview(controller)
            let result = try await controller.preview.evaluateJavaScript("({headings:document.querySelectorAll('h1,h2,h3').length,table:document.querySelectorAll('table').length,tasks:document.querySelectorAll('input[type=checkbox]').length,text:document.body.innerText})") as? [String: Any]
            try check((result?["headings"] as? Int) == 5, "WebKit 真实渲染各级标题")
            try check((result?["table"] as? Int) == 1 && (result?["tasks"] as? Int) == 3, "WebKit 真实渲染表格与任务列表")
            try check((result?["text"] as? String)?.contains("留一点空间") == true, "预览显示中文内容")
            let html = controller.renderer.page(document.text)
            try html.write(to: directory.appendingPathComponent("preview.html"), atomically: true, encoding: .utf8)
            let pdf = try await controller.preview.pdf(configuration: WKPDFConfiguration())
            try pdf.write(to: directory.appendingPathComponent("preview.pdf"))
            try check(pdf.starts(with: Data("%PDF".utf8)), "WebKit 导出有效 PDF")
            let pdfText = PDFDocument(data: pdf)?.string?.precomposedStringWithCompatibilityMapping ?? ""
            try check(pdfText.contains("留一点空间") && pdfText.contains("文字属于你"), "PDF 包含完整可读取的中文文稿内容")
            controller.window?.appearance = NSAppearance(named: .aqua)
            controller.refreshPreview()
            try await waitForPreview(controller)
            try await screenshot(controller, to: directory.appendingPathComponent("window-light.png"))
            controller.window?.appearance = NSAppearance(named: .darkAqua)
            controller.refreshPreview()
            try await waitForPreview(controller)
            try await screenshot(controller, to: directory.appendingPathComponent("window-dark.png"))
            try check(FileManager.default.fileExists(atPath: directory.appendingPathComponent("window-dark.png").path), "浅色和深色窗口截图生成")
            let draft = try documentController.makeUntitledDocument(ofType: MarkdownDocument.typeName) as! MarkdownDocument
            documentController.addDocument(draft)
            draft.makeWindowControllers()
            draft.showWindows()
            let draftController = draft.windowControllers.first as! EditorWindowController
            try await Task.sleep(nanoseconds: 300_000_000)
            draftController.editor.insertText("需要保留的草稿", replacementRange: NSRange(location: 0, length: 0))
            draftController.editor.breakUndoCoalescing()
            while let manager = draft.undoManager, manager.groupingLevel > 0 { manager.endUndoGrouping() }
            // Give AppKit a complete event-loop turn, not only a Swift concurrency yield.
            // NSDocument finishes some editing activities after an NSEvent is dispatched.
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: draftController.window?.windowNumber ?? 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                NSApp.postEvent(event, atStart: false)
            }
            try await Task.sleep(nanoseconds: 300_000_000)
            draftController.window?.performClose(nil)
            try await Task.sleep(nanoseconds: 250_000_000)
            try check(draftController.window?.attachedSheet != nil, "关闭未保存文稿会显示系统保存提示")
            if let window = draftController.window, let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .cancel) }
            try await Task.sleep(nanoseconds: 100_000_000)
            try check(draft.text == "需要保留的草稿", "取消关闭后草稿内容保持完整")
            draft.updateChangeCount(.changeCleared)
            draft.close()
            document.updateChangeCount(.changeCleared)
            document.close()
            let report = "\(checks.count) native application checks passed.\n" + checks.joined(separator: "\n") + "\n"
            try report.write(to: directory.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
            print(report)
            exit(0)
        } catch {
            let message = "FAIL: \(error.localizedDescription)\nCompleted: \(checks.count)\n"
            try? message.write(to: directory.appendingPathComponent("failure.txt"), atomically: true, encoding: .utf8)
            fputs(message, stderr)
            exit(1)
        }
    }

    private static func verifyLanguageAndPanes(document: MarkdownDocument, controller: EditorWindowController, directory: URL, check: (Bool, String) throws -> Void) async throws {
        let editor = controller.editor
        editor.breakUndoCoalescing()
        while let manager = document.undoManager, manager.groupingLevel > 0 { manager.endUndoGrouping() }
        let originalText = document.text
        let originalSelection = editor.selectedRange()
        let originalUndo = editor.undoManager?.undoActionName
        let originalEdited = document.isDocumentEdited
        let originalURL = document.fileURL
        func modeGroup(in window: EditorWindowController) throws -> NSSegmentedControl {
            guard let group = window.window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "mode" })?.view as? NSSegmentedControl else {
                throw Failure(message: "Missing toolbar mode group")
            }
            return group
        }
        func selectMode(_ index: Int, in group: NSSegmentedControl) throws {
            group.selectedSegment = index
            guard let action = group.action, group.sendAction(action, to: group.target) else {
                throw Failure(message: "Mode group did not dispatch")
            }
        }
        func chooseLanguage(_ language: AppLanguage) throws {
            guard let menu = NSApp.mainMenu?.items.first?.submenu?.items.first(where: { $0.identifier?.rawValue == "language" })?.submenu,
                  let item = menu.items.first(where: { $0.representedObject as? String == language.rawValue }),
                  let action = item.action, NSApp.sendAction(action, to: item.target, from: item) else {
                throw Failure(message: "Language menu did not dispatch: \(language)")
            }
        }
        func labels(_ view: NSView) -> [String] {
            let value = (view as? NSTextField).map { [$0.stringValue] } ?? []
            return value + view.subviews.flatMap(labels)
        }
        controller.showSplit()
        let group = try modeGroup(in: controller)
        try check(group.segmentCount == 3 && group.trackingMode == .selectOne && group.selectedSegment == 1, "模式按钮组默认单选分栏模式")
        try selectMode(0, in: group)
        try check(controller.isEditorVisible && !controller.isPreviewVisible && group.selectedSegment == 0, "选择编辑模式只显示编辑器")
        try selectMode(2, in: group)
        try check(!controller.isEditorVisible && controller.isPreviewVisible && group.selectedSegment == 2, "选择预览模式只显示预览")
        try selectMode(2, in: group)
        try check(!controller.isEditorVisible && controller.isPreviewVisible && group.selectedSegment == 2, "重复选择当前模式不会关闭区域或切换模式")
        try selectMode(1, in: group)
        try check(controller.isEditorVisible && controller.isPreviewVisible && group.selectedSegment == 1, "选择分栏模式同时显示编辑器和预览")
        let menuItem = NSMenuItem(title: "", action: #selector(EditorWindowController.showEditor), keyEquivalent: "1")
        try check(editor.tryToPerform(menuItem.action!, with: menuItem), "窗口响应链支持编辑模式命令")
        _ = controller.validateMenuItem(menuItem)
        try check(!controller.isPreviewVisible && menuItem.state == .on && group.selectedSegment == 0, "菜单命令同步按钮组的单选状态")
        controller.showPreview()
        controller.toggleFocus()
        try check(controller.isEditorVisible && !controller.isPreviewVisible && group.selectedSegment == 0, "专注模式显示编辑器并同步按钮组")
        controller.toggleFocus()
        try check(!controller.isEditorVisible && controller.isPreviewVisible && group.selectedSegment == 2, "退出专注模式恢复原有显示模式")
        controller.toggleFocus()
        try selectMode(1, in: group)
        let focusItem = NSMenuItem(title: "", action: #selector(EditorWindowController.toggleFocus), keyEquivalent: "")
        _ = controller.validateMenuItem(focusItem)
        try check(controller.isEditorVisible && controller.isPreviewVisible && focusItem.state == .off, "专注模式中选择分栏后退出专注")

        let blank = try documentController.makeUntitledDocument(ofType: MarkdownDocument.typeName) as! MarkdownDocument
        documentController.addDocument(blank)
        blank.makeWindowControllers()
        blank.showWindows()
        defer { blank.updateChangeCount(.changeCleared); blank.close() }
        let blankController = blank.windowControllers.first as! EditorWindowController
        controller.showPreview()
        try check(blankController.isEditorVisible && blankController.isPreviewVisible, "各窗口独立保存编辑和预览的显示状态")
        try chooseLanguage(.english)
        try check(NSApp.mainMenu?.items.contains(where: { $0.title == "File" }) == true && controller.window?.subtitle == "A little space to think", "语言菜单切换后主菜单与当前窗口立即变为英文")
        try check(try modeGroup(in: blankController).label(forSegment: 0) == "Edit" && group.label(forSegment: 1) == "Split" && group.label(forSegment: 2) == "Preview", "所有已打开窗口的模式按钮组同时切换语言")
        try check(blank.displayName.hasPrefix("Untitled") && labels(blankController.window!.contentView!).contains("Outline"), "未命名文稿标题和侧栏跟随界面语言")
        try check(labels(controller.window!.contentView!).contains(where: { $0.hasPrefix("Words: ") }) && labels(controller.window!.contentView!).contains(where: { $0.hasPrefix("Line ") }), "字数统计和光标位置使用英文格式")
        try check(!controller.isEditorVisible && controller.isPreviewVisible && group.selectedSegment == 2, "语言切换保留窗口布局和模式选择")
        try await waitForPreview(blankController)
        let empty = try await blankController.preview.evaluateJavaScript("({language:document.documentElement.lang,text:document.body.innerText})") as? [String: String]
        try check(empty?["language"] == "en" && empty?["text"]?.contains("It starts with a word.") == true, "空白预览和 HTML 语言属性即时切换为英文")
        try check(welcomeMarkdown.contains("# A little space to think."), "帮助文稿使用当前界面语言")
        try check(controller.editor === editor && editor.string == originalText && document.text == originalText && editor.selectedRange() == originalSelection && document.fileURL == originalURL && document.isDocumentEdited == originalEdited && editor.undoManager?.undoActionName == originalUndo, "语言及区域切换保留编辑器、文稿、选区、保存状态和撤销记录")
        controller.showSplit()
        editor.undoManager?.undo()
        try check(document.text != originalText, "切换后原有编辑仍可撤销")
        editor.undoManager?.redo()
        try check(document.text == originalText, "切换后重做可完整恢复文稿")
        blankController.insertTable()
        let selected = (blankController.editor.string as NSString).substring(with: blankController.editor.selectedRange())
        try check(selected == "Heading" && blank.text.contains("| Content | Content |"), "英文表格占位文案和选区长度正确")
        controller.window?.appearance = NSAppearance(named: .aqua)
        try await waitForPreview(controller)
        try await screenshot(controller, to: directory.appendingPathComponent("window-english.png"))
        try chooseLanguage(.simplifiedChinese)
        try check(NSApp.mainMenu?.items.contains(where: { $0.title == "文件" }) == true && group.label(forSegment: 0) == "编辑" && group.label(forSegment: 1) == "分栏" && blank.displayName.hasPrefix("未命名"), "切回中文后所有窗口和菜单恢复中文")
        try chooseLanguage(.system)
        try check(L10n.shared.selection == .system, "语言菜单支持恢复跟随系统")
        try chooseLanguage(.simplifiedChinese)
        try check(document.text == originalText, "多次语言切换始终保留原文内容")
    }

    private static func verifyOutlineNavigation(check: (Bool, String) throws -> Void) async throws {
        let document = try documentController.makeUntitledDocument(ofType: MarkdownDocument.typeName) as! MarkdownDocument
        // Include nested and duplicate headings: navigation must find the selected
        // top-level heading, not the first matching text or a heading inside a quote.
        let paragraphs = String(repeating: "正文 paragraph 中文与 emoji 🌱。\n\n", count: 35)
        document.text = "# 重复标题\n\n> ## 引用内标题\n\n" + paragraphs + "## **目标标题**\n\n" + paragraphs + "# 重复标题\n\n" + paragraphs + "Setext heading\n==============\n\n" + paragraphs
        let original = document.text
        documentController.addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
        defer { document.updateChangeCount(.changeCleared); document.close() }
        let controller = document.windowControllers.first as! EditorWindowController
        func table(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView { return table }
            return view.subviews.lazy.compactMap { table(in: $0) }.first
        }
        guard let outline = table(in: controller.window!.contentView!), let action = outline.action else {
            throw Failure(message: "Missing outline table")
        }
        func clickHeading(_ row: Int) throws {
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            try check(outline.sendAction(action, to: outline.target), "目录点击通过真实表格动作跳转")
        }
        func headingIsVisible(_ index: Int) async throws -> Bool {
            let value = try await controller.preview.evaluateJavaScript("(() => { const r = document.querySelectorAll('article > :is(h1,h2,h3,h4,h5,h6)')[\(index)].getBoundingClientRect(); return r.top >= 0 && r.top < 80; })()")
            return value as? Bool == true
        }
        try await waitForPreview(controller)
        let selection = controller.editor.selectedRange()
        controller.showPreview()
        try clickHeading(2)
        try check(!controller.isEditorVisible && controller.isPreviewVisible && controller.editor.selectedRange() == selection, "预览模式点击目录保留布局和隐藏编辑器选区")
        try check(try await headingIsVisible(2), "重复标题跳到预览中的正确位置并跳过引用内标题")
        controller.refreshPreview()
        try clickHeading(3)
        try await waitForPreview(controller)
        try check(try await headingIsVisible(3) && !controller.isEditorVisible, "预览加载期间点击目录会在加载后定位 Setext 标题并保留预览模式")
        controller.showSplit()
        try clickHeading(1)
        let target = MarkdownText.headings(in: original)[1].range.location
        try check(controller.isEditorVisible && controller.isPreviewVisible && controller.editor.selectedRange().location == target, "分栏模式点击目录定位编辑器并保留分栏")
        try check(try await headingIsVisible(1), "分栏模式同时定位对应预览标题")
        controller.showEditor()
        try clickHeading(0)
        try check(controller.isEditorVisible && !controller.isPreviewVisible && controller.editor.selectedRange().location == 0, "编辑模式点击目录保持仅编辑布局")
        try check(document.text == original && !document.isDocumentEdited, "目录导航不修改文稿内容或保存状态")
    }

    private static func verifyWritingTools(in directory: URL, check: (Bool, String) throws -> Void) async throws {
        let url = directory.appendingPathComponent("writing-tools.md")
        try "# 写作工具\n\n中文🌱链接\n".write(to: url, atomically: true, encoding: .utf8)
        let document = try await openDocument(url)
        let controller = document.windowControllers.first as! EditorWindowController
        let editor = controller.editor
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("marknote-tests-" + UUID().uuidString))
        defer {
            pasteboard.releaseGlobally()
            controller.activePalette?.dismiss(nil)
            UserDefaults.standard.set(false, forKey: "paragraphFocus")
            UserDefaults.standard.set(false, forKey: "typewriterScrolling")
            document.updateChangeCount(.changeCleared)
            document.close()
        }
        let original = document.text
        editor.setSelectedRange((editor.string as NSString).range(of: "中文🌱链接"))
        pasteboard.setString("https://example.com/a(b)", forType: .string)
        try check(editor.paste(from: pasteboard), "粘贴网址使用选区生成链接")
        try check(document.text.contains("[中文🌱链接](https://example.com/a%28b%29)"), "智能链接保留 Unicode 文本并转义网址括号")
        try await settleEditing(editor, document: document)
        editor.undoManager?.undo()
        try check(document.text == original, "智能链接可完整撤销")
        editor.undoManager?.redo()
        try check(document.text.contains("[中文🌱链接]"), "智能链接可重做")

        document.text = "| Name | 值 |\n| --- | ---: |\n| row | 中文🌱 |\n"
        controller.reloadDocument()
        editor.undoManager?.removeAllActions()
        editor.setSelectedRange((editor.string as NSString).range(of: "Name"))
        controller.formatTable()
        let formatted = document.text
        try check(formatted.contains("| Name |") && formatted.contains("---:"), "表格整理保持列对齐标记")
        // Formatting and pressing Tab are separate AppKit input events.
        try await settleEditing(editor, document: document)
        editor.insertTab(nil)
        try check((editor.string as NSString).substring(with: editor.selectedRange()) == "值", "Tab 选中下一表格单元格")
        editor.insertTab(nil)
        try check((editor.string as NSString).substring(with: editor.selectedRange()) == "row", "Tab 跳过表格分隔行")
        editor.insertBacktab(nil)
        try check((editor.string as NSString).substring(with: editor.selectedRange()) == "值", "Shift-Tab 返回上一单元格")
        editor.setSelectedRange((editor.string as NSString).range(of: "中文🌱"))
        editor.insertTab(nil)
        try check(document.text != formatted && document.text.hasPrefix(formatted), "最后一格 Tab 自动添加一行")
        try await settleEditing(editor, document: document)
        editor.undoManager?.undo()
        try check(document.text == formatted, "表格增行作为一次操作撤销")

        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        let beforeImage = document.text
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let imageColor = NSColor(srgbRed: 0.1, green: 0.6, blue: 0.6, alpha: 1)
        for x in 0..<2 { for y in 0..<2 { bitmap.setColor(imageColor, atX: x, y: y) } }
        let png = bitmap.representation(using: .png, properties: [:])!
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        try check(editor.paste(from: pasteboard), "原生剪贴板图片插入文稿")
        try check(document.text.contains("](assets/image-") && !document.text.contains(directory.path), "图片使用相对路径而非本机绝对路径")
        let assets = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("assets"), includingPropertiesForKeys: nil)
        try check(assets.count == 1 && (try Data(contentsOf: assets[0])) == png, "图片复制到文稿旁 assets 目录且内容不变")
        controller.refreshPreview()
        try await waitForPreview(controller)
        let rendered = try await controller.preview.evaluateJavaScript("document.querySelector('img')?.naturalWidth") as? Int
        try check(rendered == 2, "插入图片在 WebKit 预览中真实显示")
        try await settleEditing(editor, document: document)
        editor.undoManager?.undo()
        try check(document.text == beforeImage && FileManager.default.fileExists(atPath: assets[0].path), "撤销图片插入保留附件供重做")
        editor.undoManager?.redo()
        try check(document.text.contains(assets[0].lastPathComponent), "重做图片插入恢复原有引用")
        let imported = try ImageImport.read(files: [assets[0]])
        try check(imported.count == 1 && imported[0].data == png, "文件选择和拖放共用图片读取路径")
        let draft = try documentController.makeUntitledDocument(ofType: MarkdownDocument.typeName) as! MarkdownDocument
        documentController.addDocument(draft)
        draft.makeWindowControllers()
        draft.showWindows()
        let draftController = draft.windowControllers.first as! EditorWindowController
        draftController.importImages(imported, at: NSRange(location: 0, length: 0))
        try check(draftController.window?.attachedSheet != nil && draft.text.isEmpty, "未保存文稿插图先提示保存且不修改正文")
        if let window = draftController.window, let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .alertSecondButtonReturn) }
        try await Task.sleep(nanoseconds: 150_000_000)
        try check(draftController.pendingImageInsertion == nil && draft.text.isEmpty, "取消保存后取消图片插入")
        draft.close()

        document.text = (0..<120).map { "Paragraph \($0) 中文🌱 writing.\n\n" }.joined()
        controller.reloadDocument()
        editor.undoManager?.removeAllActions()
        document.updateChangeCount(.changeCleared)
        controller.window?.makeKeyAndOrderFront(nil)
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).range(of: "Paragraph 60").location, length: 0))
        let beforeFocus = document.text
        controller.toggleParagraphFocus()
        let manager = editor.layoutManager!
        try check(manager.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) != nil && manager.temporaryAttribute(.foregroundColor, atCharacterIndex: editor.selectedRange().location, effectiveRange: nil) == nil, "段落聚焦只淡化非当前段落")
        controller.toggleTypewriterScrolling()
        try await Task.sleep(nanoseconds: 150_000_000)
        editor.updateWritingFocus()
        let glyph = manager.glyphIndexForCharacter(at: editor.selectedRange().location)
        let caret = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: editor.textContainer!)
        let center = editor.enclosingScrollView!.contentView.bounds.midY
        try check(abs(caret.midY + editor.textContainerOrigin.y - center) < 25, "打字机滚动将当前行保持在编辑器中间")
        try check(document.text == beforeFocus && !document.isDocumentEdited, "写作模式不改变正文和修改状态")
        editor.setMarkedText("zhongwen", selectedRange: NSRange(location: 8, length: 0), replacementRange: editor.selectedRange())
        editor.updateWritingFocus()
        try check(editor.hasMarkedText(), "写作模式保留输入法组合文本")
        editor.insertText("写作", replacementRange: editor.markedRange())
        try check(document.text.contains("写作Paragraph 60"), "写作模式正常提交中文输入")
        controller.toggleParagraphFocus()
        controller.toggleTypewriterScrolling()
        try check(editor.textContainerInset.height == 32 && manager.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) == nil, "关闭写作模式恢复普通排版和语法颜色")

        try await settleEditing(editor, document: document)
        let beforePalette = document.text
        let paletteSelection = editor.selectedRange()
        controller.showCommandPalette()
        guard let palette = controller.activePalette else { throw Failure(message: "Command palette did not open") }
        guard let searchEditor = palette.window?.fieldEditor(false, for: palette.search) as? NSTextView else { throw Failure(message: "Command search did not receive focus") }
        searchEditor.setMarkedText("biaoge", selectedRange: NSRange(location: 6, length: 0), replacementRange: searchEditor.selectedRange())
        palette.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: palette.search))
        try check(searchEditor.hasMarkedText(), "命令搜索保留中文输入法组合文本")
        searchEditor.insertText("表格", replacementRange: searchEditor.markedRange())
        palette.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: palette.search))
        try check(palette.results.contains(where: { $0.id == "table" }), "命令面板提交中文后搜索对应命令")
        palette.filter("preview")
        try check(palette.results.first?.id == "preview", "中文界面的命令面板可使用英文关键词搜索")
        try check(palette.control(palette.search, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))), "命令面板响应回车")
        try await Task.sleep(nanoseconds: 200_000_000)
        try check(!controller.isEditorVisible && controller.isPreviewVisible && controller.activePalette == nil, "命令面板执行预览模式并关闭")
        try check(document.text == beforePalette && editor.selectedRange() == paletteSelection, "命令面板切换布局保留正文和选区")
        controller.showCommandPalette()
        let cancelled = controller.activePalette!
        _ = cancelled.control(cancelled.search, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        try check(controller.activePalette == nil && !controller.isEditorVisible, "Escape 关闭命令面板且保持当前布局")
        let sibling = directory.appendingPathComponent("附近 Notes 🌱.md")
        try "# Nearby note".write(to: sibling, atomically: true, encoding: .utf8)
        controller.showQuickOpen()
        let quick = controller.activePalette!
        quick.filter("附近")
        try check(quick.results.count == 1 && quick.results[0].title == sibling.lastPathComponent, "快速打开搜索同目录 Markdown 文件")
        quick.accept(nil)
        for _ in 0..<30 {
            if documentController.documents.contains(where: { $0.fileURL == sibling }) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let opened = documentController.documents.first(where: { $0.fileURL == sibling }) as? MarkdownDocument
        try check(opened?.text == "# Nearby note" && document.text == beforePalette, "快速打开载入所选文件并保留原文稿")
        opened?.close()
    }

    private static func settleEditing(_ editor: NSTextView, document: MarkdownDocument) async throws {
        editor.breakUndoCoalescing()
        while let manager = document.undoManager, manager.groupingLevel > 0 { manager.endUndoGrouping() }
        // AppKit finishes document editing activities after an NSEvent is dispatched.
        // A Swift Task sleep alone may never end that activity on an idle CI desktop.
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: editor.window?.windowNumber ?? 0, context: nil, subtype: 0, data1: 0, data2: 0) {
            NSApp.postEvent(event, atStart: false)
        }
        try await Task.sleep(nanoseconds: 300_000_000)
    }

    private static func save(_ document: MarkdownDocument, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.save(to: url, ofType: MarkdownDocument.typeName, for: .saveOperation) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private static func autosave(_ document: MarkdownDocument) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.autosave(withImplicitCancellability: false) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private static func openDocument(_ url: URL) async throws -> MarkdownDocument {
        try await withCheckedThrowingContinuation { continuation in
            documentController.openDocument(withContentsOf: url, display: true) { document, _, error in
                if let error { continuation.resume(throwing: error) }
                else if let document = document as? MarkdownDocument { continuation.resume(returning: document) }
                else { continuation.resume(throwing: Failure(message: "文档控制器未打开 Markdown 文件")) }
            }
        }
    }

    static func waitForPreview(_ controller: EditorWindowController) async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
        for _ in 0..<100 {
            if controller.previewReady && !controller.preview.isLoading { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw Failure(message: "WebKit preview did not finish within 10 seconds")
    }

    static func screenshot(_ controller: EditorWindowController, to url: URL) async throws {
        guard let root = controller.window?.contentView?.superview,
              let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { throw Failure(message: "无法截取窗口") }
        root.layoutSubtreeIfNeeded()
        root.effectiveAppearance.performAsCurrentDrawingAppearance { root.cacheDisplay(in: root.bounds, to: bitmap) }
        let webImage = controller.isPreviewVisible ? try await controller.preview.takeSnapshot(configuration: nil) : nil
        let image = NSImage(size: root.bounds.size)
        image.lockFocus()
        root.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            root.bounds.fill()
        }
        bitmap.draw(in: root.bounds)
        webImage?.draw(in: controller.preview.convert(controller.preview.bounds, to: root))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { throw Failure(message: "无法编码截图") }
        try png.write(to: url)
    }
}
