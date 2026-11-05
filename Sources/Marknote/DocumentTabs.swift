import AppKit
import MarknoteCore

extension EditorWindowController {
    func updateDirectoryTree() {
        directoryTree.currentFile = documentModel.fileURL
        if directoryTree.workspace == nil, let url = documentModel.fileURL {
            setWorkspace(DirectoryWorkspace(rootURL: url.deletingLastPathComponent()))
        } else { directoryTree.refresh() }
    }

    @objc func refreshDirectoryTree() { updateDirectoryTree() }

    func setWorkspace(_ workspace: DirectoryWorkspace) {
        for tab in window?.tabbedWindows ?? [window].compactMap({ $0 }) {
            guard let controller = tab.windowController as? EditorWindowController else { continue }
            controller.directoryTree.currentFile = controller.documentModel.fileURL
            controller.directoryTree.setWorkspace(workspace)
        }
    }

    @objc func openFolder(_ sender: Any?) {
        guard let window, window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = directoryTree.workspace?.rootURL ?? documentModel.fileURL?.deletingLastPathComponent()
        panel.prompt = L10n.text(.openFolder)
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            self?.setWorkspace(DirectoryWorkspace(rootURL: url))
            self?.revealSidebar()
        }
    }

    @objc func newDocumentTab(_ sender: Any?) {
        do {
            let document = try documentController.makeUntitledDocument(ofType: MarkdownDocument.typeName) as! MarkdownDocument
            documentController.addDocument(document)
            document.makeWindowControllers()
            if let controller = document.windowControllers.first as? EditorWindowController { attachTab(controller) }
        } catch { documentModel.presentError(error) }
    }

    override func newWindowForTab(_ sender: Any?) { newDocumentTab(sender) }

    /// NSDocumentController reuses open documents, preserving unsaved edits and undo stacks.
    @discardableResult func openFileInTab(_ url: URL) async throws -> EditorWindowController {
        let (document, alreadyOpen): (MarkdownDocument, Bool) = try await withCheckedThrowingContinuation { continuation in
            documentController.openDocument(withContentsOf: url, display: false) { document, alreadyOpen, error in
                if let error { continuation.resume(throwing: error) }
                else if let document = document as? MarkdownDocument { continuation.resume(returning: (document, alreadyOpen)) }
                else { continuation.resume(throwing: CocoaError(.fileReadUnknown)) }
            }
        }
        document.makeWindowControllers()
        let controller = document.windowControllers.first as! EditorWindowController
        if alreadyOpen {
            controller.window?.tabGroup?.selectedWindow = controller.window
            controller.showWindowsForTab()
        } else { attachTab(controller) }
        return controller
    }

    private func attachTab(_ controller: EditorWindowController) {
        guard let window, let tab = controller.window else { return }
        controller.directoryTree.currentFile = controller.documentModel.fileURL
        let workspace = directoryTree.workspace ?? controller.directoryTree.workspace
        window.addTabbedWindow(tab, ordered: .above)
        if let workspace { setWorkspace(workspace) }
        tab.tabGroup?.selectedWindow = tab
        controller.showWindowsForTab()
    }

    private func showWindowsForTab() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(editor)
        updateDirectoryTree()
    }
}
