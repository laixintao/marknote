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
            UserDefaults.standard.set(false, forKey: "paragraphFocus")
            UserDefaults.standard.set(false, forKey: "typewriterScrolling")
            UserDefaults.standard.set([], forKey: "recentCommands")
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
                    // Closing the previous sample can finish asynchronously while WebKit
                    // loads; restore the new window's active appearance before capturing.
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                    try await Task.sleep(nanoseconds: 200_000_000)
                    try await SmokeTest.screenshot(controller, to: directory.appendingPathComponent(filename))
                    print("Captured: \(filename)")
                }
                if language == .english {
                    controller.showSplit()
                    controller.showCommandPalette()
                    try await Task.sleep(nanoseconds: 250_000_000)
                    guard let paletteWindow = controller.activePalette?.window,
                          let root = paletteWindow.contentView?.superview,
                          let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { throw SmokeTest.Failure(message: "Could not capture command palette") }
                    root.layoutSubtreeIfNeeded()
                    root.effectiveAppearance.performAsCurrentDrawingAppearance { root.cacheDisplay(in: root.bounds, to: bitmap) }
                    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw SmokeTest.Failure(message: "Could not encode command palette") }
                    try png.write(to: directory.appendingPathComponent("product-commands.png"))
                    controller.activePalette?.dismiss(nil)
                    controller.toggleFocus()
                    controller.editor.setSelectedRange(NSRange(location: (controller.editor.string as NSString).range(of: "Keep your hands").location, length: 0))
                    controller.toggleParagraphFocus()
                    controller.toggleTypewriterScrolling()
                    window.makeKeyAndOrderFront(nil)
                    window.makeFirstResponder(controller.editor)
                    try await Task.sleep(nanoseconds: 250_000_000)
                    controller.editor.updateWritingFocus()
                    try await SmokeTest.screenshot(controller, to: directory.appendingPathComponent("product-writing.png"))
                    print("Captured: product-commands.png, product-writing.png")
                }
                document.close()
            }
            try "6 product screenshots captured from the native application.\n".write(to: directory.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
            exit(0)
        } catch {
            fputs("Screenshot capture failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
