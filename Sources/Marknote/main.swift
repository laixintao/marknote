import AppKit

let app = NSApplication.shared
let documentController = MarkdownDocumentController()
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.regular)
app.run()
