import AppKit
import MarknoteCore

/// Captures the real application with bundled sample documents in an isolated process.
@MainActor enum ProductScreenshots {
    static func run(in directory: URL) async {
        setbuf(stdout, nil)
        DispatchQueue.global().asyncAfter(deadline: .now() + 45) {
            fputs("Product screenshot capture timed out\n", stderr)
            exit(1)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for language in [AppLanguage.simplifiedChinese, .english] {
                L10n.shared.select(language)
                let name = language == .english ? "Field Notes.md" : "写作手记.md"
                let url = directory.appendingPathComponent(name)
                try welcomeMarkdown.write(to: url, atomically: true, encoding: .utf8)
                let document: MarkdownDocument = try await withCheckedThrowingContinuation { continuation in
                    documentController.openDocument(withContentsOf: url, display: true) { document, _, error in
                        if let error { continuation.resume(throwing: error) }
                        else if let document = document as? MarkdownDocument { continuation.resume(returning: document) }
                        else { continuation.resume(throwing: SmokeTest.Failure(message: "Could not open screenshot sample")) }
                    }
                }
                let controller = document.windowControllers.first as! EditorWindowController
                let window = controller.window!
                window.setContentSize(NSSize(width: 1220, height: 800))
                window.center()
                window.makeKeyAndOrderFront(nil)
                NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                window.orderFrontRegardless()
                window.makeMain()
                window.makeKey()
                window.makeFirstResponder(controller.editor)
                controller.editor.setSelectedRange(NSRange(location: 0, length: 0))
                let shots: [(String, NSAppearance.Name, Bool)] = language == .english
                    ? [("product-english.png", .aqua, false), ("product-preview.png", .aqua, true)]
                    : [("product-light.png", .aqua, false), ("product-dark.png", .darkAqua, false)]
                for (filename, appearance, previewOnly) in shots {
                    window.appearance = NSAppearance(named: appearance)
                    if previewOnly { controller.showPreview() } else { controller.showSplit() }
                    controller.refreshPreview()
                    try await SmokeTest.waitForPreview(controller)
                    try await SmokeTest.screenshot(controller, to: directory.appendingPathComponent(filename))
                    print("Captured: \(filename)")
                }
                document.close()
            }
            try "4 product screenshots captured from the native application.\n".write(to: directory.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
            exit(0)
        } catch {
            fputs("Screenshot capture failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
