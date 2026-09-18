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
        func button(_ id: String, in window: EditorWindowController) throws -> NSButton {
            guard let button = window.window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == id })?.view as? NSButton else {
                throw Failure(message: "Missing toolbar switch: \(id)")
            }
            return button
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
        let editSwitch = try button("editor", in: controller)
        let previewSwitch = try button("preview", in: controller)
        try check(editSwitch.state == .on && previewSwitch.state == .on, "Edit 与 Preview 是默认开启的独立工具栏开关")
        editSwitch.performClick(nil)
        try check(!controller.isEditorVisible && controller.isPreviewVisible && editSwitch.state == .off && previewSwitch.state == .on, "关闭 Edit 后仅显示 Preview 并同步按钮状态")
        previewSwitch.performClick(nil)
        try check(controller.isEditorVisible && !controller.isPreviewVisible && editSwitch.state == .on && previewSwitch.state == .off, "关闭最后一个区域时自动显示另一区域")
        previewSwitch.performClick(nil)
        try check(controller.isEditorVisible && controller.isPreviewVisible, "重新开启 Preview 恢复双栏")
        previewSwitch.performClick(nil)
        try check(controller.isEditorVisible && !controller.isPreviewVisible, "关闭 Preview 后保留 Edit")
        editSwitch.performClick(nil)
        try check(!controller.isEditorVisible && controller.isPreviewVisible, "仅 Edit 可见时关闭 Edit 自动切换到 Preview")
        editSwitch.performClick(nil)
        try check(controller.isEditorVisible && controller.isPreviewVisible, "重新开启 Edit 恢复双栏")
        let menuItem = NSMenuItem(title: "", action: #selector(EditorWindowController.togglePreviewPane), keyEquivalent: "p")
        try check(editor.tryToPerform(menuItem.action!, with: menuItem), "窗口响应链支持 Preview 开关命令")
        _ = controller.validateMenuItem(menuItem)
        try check(!controller.isPreviewVisible && menuItem.state == .off, "显示菜单勾选状态与工具栏开关一致")
        controller.showPreview()
        controller.toggleFocus()
        try check(controller.isEditorVisible && !controller.isPreviewVisible, "专注模式显示编辑器")
        controller.toggleFocus()
        try check(!controller.isEditorVisible && controller.isPreviewVisible, "退出专注模式恢复原有区域状态")
        controller.toggleFocus()
        previewSwitch.performClick(nil)
        let focusItem = NSMenuItem(title: "", action: #selector(EditorWindowController.toggleFocus), keyEquivalent: "")
        _ = controller.validateMenuItem(focusItem)
        try check(controller.isEditorVisible && controller.isPreviewVisible && focusItem.state == .off, "专注模式中开启 Preview 后恢复双栏并退出专注")

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
        try check(try button("editor", in: blankController).title == "Edit" && button("preview", in: controller).title == "Preview", "所有已打开窗口的工具栏同时切换语言")
        try check(blank.displayName.hasPrefix("Untitled") && labels(blankController.window!.contentView!).contains("Outline"), "未命名文稿标题和侧栏跟随界面语言")
        try check(labels(controller.window!.contentView!).contains(where: { $0.hasPrefix("Words: ") }) && labels(controller.window!.contentView!).contains(where: { $0.hasPrefix("Line ") }), "字数统计和光标位置使用英文格式")
        try check(!controller.isEditorVisible && controller.isPreviewVisible && editSwitch.state == .off && previewSwitch.state == .on, "语言切换保留窗口布局和开关状态")
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
        try check(NSApp.mainMenu?.items.contains(where: { $0.title == "文件" }) == true && editSwitch.title == "编辑" && blank.displayName.hasPrefix("未命名"), "切回中文后所有窗口和菜单恢复中文")
        try chooseLanguage(.system)
        try check(L10n.shared.selection == .system, "语言菜单支持恢复跟随系统")
        try chooseLanguage(.simplifiedChinese)
        try check(document.text == originalText, "多次语言切换始终保留原文内容")
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
        let webImage = try await controller.preview.takeSnapshot(configuration: nil)
        let image = NSImage(size: root.bounds.size)
        image.lockFocus()
        root.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            root.bounds.fill()
        }
        bitmap.draw(in: root.bounds)
        webImage.draw(in: controller.preview.convert(controller.preview.bounds, to: root))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { throw Failure(message: "无法编码截图") }
        try png.write(to: url)
    }
}
