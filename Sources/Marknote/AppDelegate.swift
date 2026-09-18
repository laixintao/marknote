import AppKit
import MarknoteCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private var changingDefaultEditor = false
    func applicationWillFinishLaunching(_ notification: Notification) {
        buildMenus()
        NotificationCenter.default.addObserver(self, selector: #selector(languageDidChange), name: LocalizationStore.didChange, object: L10n.shared)
    }

    @objc private func languageDidChange() { buildMenus() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        if let index = CommandLine.arguments.firstIndex(of: "--screenshots"), CommandLine.arguments.count > index + 1 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            Task { @MainActor in await ProductScreenshots.run(in: directory) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--smoke-test"), CommandLine.arguments.count > index + 1 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            Task { @MainActor in await SmokeTest.run(in: directory) }
            return
        }
        if documentController.documents.isEmpty {
            if !UserDefaults.standard.bool(forKey: "hasOpenedMarknote") {
                openWelcome()
                UserDefaults.standard.set(true, forKey: "hasOpenedMarknote")
            } else { documentController.newDocument(nil) }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { documentController.newDocument(nil) }
        return true
    }

    private func buildMenus() {
        let main = NSMenu()
        NSApp.mainMenu = main
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            item.submenu = submenu
            main.addItem(item)
            return submenu
        }
        func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = target
            menu.addItem(item)
        }
        let application = menu(L10n.text(.appName))
        add(application, L10n.text(.about), #selector(showAbout), target: self)
        let languageItem = NSMenuItem(title: L10n.text(.language), action: nil, keyEquivalent: "")
        languageItem.identifier = NSUserInterfaceItemIdentifier("language")
        let languageMenu = NSMenu(title: L10n.text(.language))
        for (choice, title) in [(AppLanguage.system, L10n.text(.languageSystem)), (.simplifiedChinese, "简体中文"), (.english, "English")] {
            let item = NSMenuItem(title: title, action: #selector(changeLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.rawValue
            item.state = L10n.shared.selection == choice ? .on : .off
            languageMenu.addItem(item)
        }
        languageMenu.addItem(.separator())
        let note = NSMenuItem(title: L10n.text(.languageNote), action: nil, keyEquivalent: "")
        note.isEnabled = false
        languageMenu.addItem(note)
        languageItem.submenu = languageMenu
        application.addItem(languageItem)
        add(application, L10n.text(.defaultEditor), #selector(makeDefaultMarkdownEditor), target: self)
        application.addItem(.separator())
        let services = NSMenuItem(title: L10n.text(.services), action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: L10n.text(.services))
        application.addItem(services)
        NSApp.servicesMenu = services.submenu
        application.addItem(.separator())
        add(application, L10n.text(.hideApp), #selector(NSApplication.hide(_:)), "h")
        add(application, L10n.text(.hideOthers), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(application, L10n.text(.showAll), #selector(NSApplication.unhideAllApplications(_:)))
        application.addItem(.separator())
        add(application, L10n.text(.quit), #selector(NSApplication.terminate(_:)), "q")

        let file = menu(L10n.text(.menuFile))
        add(file, L10n.text(.newDocument), #selector(NSDocumentController.newDocument(_:)), "n", target: documentController)
        add(file, L10n.text(.open), #selector(NSDocumentController.openDocument(_:)), "o", target: documentController)
        add(file, L10n.text(.quickOpen), #selector(EditorWindowController.showQuickOpen), "o", [.command, .shift])
        let recent = NSMenuItem(title: L10n.text(.openRecent), action: nil, keyEquivalent: "")
        recent.submenu = NSMenu(title: L10n.text(.openRecent))
        recent.submenu?.delegate = self
        file.addItem(recent)
        file.addItem(.separator())
        add(file, L10n.text(.close), #selector(NSWindow.performClose(_:)), "w")
        add(file, L10n.text(.save), #selector(NSDocument.save(_:)), "s")
        add(file, L10n.text(.saveAs), #selector(NSDocument.saveAs(_:)), "s", [.command, .shift])
        add(file, L10n.text(.revert), #selector(NSDocument.revertToSaved(_:)))
        file.addItem(.separator())
        add(file, L10n.text(.exportHTML), #selector(EditorWindowController.exportHTML))
        add(file, L10n.text(.exportPDF), #selector(EditorWindowController.exportPDF), "e", [.command, .shift])

        let edit = menu(L10n.text(.menuEdit))
        add(edit, L10n.text(.undo), Selector(("undo:")), "z")
        add(edit, L10n.text(.redo), Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        add(edit, L10n.text(.cut), #selector(NSText.cut(_:)), "x")
        add(edit, L10n.text(.copy), #selector(NSText.copy(_:)), "c")
        add(edit, L10n.text(.paste), #selector(NSText.paste(_:)), "v")
        add(edit, L10n.text(.pastePlainText), #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift])
        add(edit, L10n.text(.selectAll), #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator())
        add(edit, L10n.text(.find), #selector(EditorWindowController.findInDocument(_:)), "f")

        let format = menu(L10n.text(.menuFormat))
        add(format, L10n.text(.bold), #selector(EditorWindowController.toggleBold), "b")
        add(format, L10n.text(.italic), #selector(EditorWindowController.toggleItalic), "i")
        add(format, L10n.text(.insertLink), #selector(EditorWindowController.insertLink), "k")
        format.addItem(.separator())
        add(format, L10n.text(.heading), #selector(EditorWindowController.insertHeading), "1", [.command, .option])
        add(format, L10n.text(.list), #selector(EditorWindowController.insertList), "l", [.command, .shift])
        add(format, L10n.text(.task), #selector(EditorWindowController.insertTask), "t", [.command, .shift])
        add(format, L10n.text(.quote), #selector(EditorWindowController.insertQuote))
        add(format, L10n.text(.code), #selector(EditorWindowController.insertCode))
        add(format, L10n.text(.table), #selector(EditorWindowController.insertTable))
        add(format, L10n.text(.formatTable), #selector(EditorWindowController.formatTable), "t", [.command, .option])
        add(format, L10n.text(.insertImage), #selector(EditorWindowController.insertImage), "i", [.command, .shift])

        let view = menu(L10n.text(.menuView))
        add(view, L10n.text(.commandPalette), #selector(EditorWindowController.showCommandPalette), "p", [.command, .shift])
        view.addItem(.separator())
        add(view, L10n.text(.editorToggle), #selector(EditorWindowController.toggleEditorPane), "e", [.command, .option])
        add(view, L10n.text(.previewToggle), #selector(EditorWindowController.togglePreviewPane), "p", [.command, .option])
        view.addItem(.separator())
        add(view, L10n.text(.outline), #selector(EditorWindowController.toggleSidebar), "0", [.command, .option])
        add(view, L10n.text(.editorOnly), #selector(EditorWindowController.showEditor), "1", [.command, .control])
        add(view, L10n.text(.splitView), #selector(EditorWindowController.showSplit), "2", [.command, .control])
        add(view, L10n.text(.previewOnly), #selector(EditorWindowController.showPreview), "3", [.command, .control])
        view.addItem(.separator())
        add(view, L10n.text(.focus), #selector(EditorWindowController.toggleFocus), "f", [.command, .shift])
        add(view, L10n.text(.paragraphFocus), #selector(EditorWindowController.toggleParagraphFocus))
        add(view, L10n.text(.typewriterScrolling), #selector(EditorWindowController.toggleTypewriterScrolling))
        add(view, L10n.text(.increaseFont), #selector(EditorWindowController.increaseFont), "+")
        add(view, L10n.text(.decreaseFont), #selector(EditorWindowController.decreaseFont), "-")
        view.addItem(.separator())
        add(view, L10n.text(.fullScreen), #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])

        let window = menu(L10n.text(.menuWindow))
        NSApp.windowsMenu = window
        add(window, L10n.text(.minimize), #selector(NSWindow.performMiniaturize(_:)), "m")
        add(window, L10n.text(.zoom), #selector(NSWindow.performZoom(_:)))
        add(window, L10n.text(.bringAllToFront), #selector(NSApplication.arrangeInFront(_:)))
        let help = menu(L10n.text(.menuHelp))
        NSApp.helpMenu = help
        add(help, L10n.text(.userGuide), #selector(openWelcome), target: self)
    }

    @objc func changeLanguage(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let language = AppLanguage(rawValue: value) else { return }
        L10n.shared.select(language)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(makeDefaultMarkdownEditor) {
            menuItem.state = MarkdownFileAssociation.isDefault ? .on : .off
            return !changingDefaultEditor
        }
        return true
    }

    @objc private func makeDefaultMarkdownEditor() {
        let readOnly = (try? Bundle.main.bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        guard !readOnly else {
            let alert = NSAlert()
            alert.messageText = L10n.text(.installFirst)
            alert.informativeText = L10n.text(.installFirstMessage)
            alert.runModal()
            return
        }
        guard !changingDefaultEditor else { return }
        changingDefaultEditor = true
        Task { @MainActor in
            defer { changingDefaultEditor = false }
            let alert = NSAlert()
            do {
                try await MarkdownFileAssociation.setDefault()
                alert.messageText = L10n.text(.defaultEditorDone)
                alert.informativeText = L10n.text(.defaultEditorMessage)
            } catch {
                alert.alertStyle = .warning
                alert.messageText = L10n.text(.defaultEditorFailed)
                alert.informativeText = error.localizedDescription
            }
            alert.runModal()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for url in documentController.recentDocumentURLs {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.representedObject = url
            item.target = self
            item.toolTip = url.path
            menu.addItem(item)
        }
        if menu.items.isEmpty {
            let item = NSMenuItem(title: L10n.text(.noRecentDocuments), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            menu.addItem(.separator())
            let clear = NSMenuItem(title: L10n.text(.clearRecent), action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
            clear.target = documentController
            menu.addItem(clear)
        }
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        documentController.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }

    @objc func openWelcome() {
        do {
            let document = try documentController.makeUntitledDocument(ofType: MarkdownDocument.typeName) as! MarkdownDocument
            document.text = welcomeMarkdown
            documentController.addDocument(document)
            document.makeWindowControllers()
            document.showWindows()
        } catch { NSApp.presentError(error) }
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: L10n.text(.appName),
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            .credits: NSAttributedString(string: L10n.text(.aboutCredits)),
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): L10n.text(.aboutCopyright)
        ])
    }
}
