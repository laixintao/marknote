import AppKit
import MarknoteCore

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    static let typeName = "net.daringfireball.markdown"
    var text = ""

    override var displayName: String! {
        get {
            guard fileURL == nil else { return super.displayName }
            let original = super.displayName ?? ""
            let suffix = original.range(of: #"\s+\d+$"#, options: .regularExpression).map { String(original[$0]) } ?? ""
            return L10n.text(.untitled) + suffix
        }
        set { super.displayName = newValue }
    }

    override class var autosavesInPlace: Bool { true }
    override var autosavingFileType: String? { Self.typeName }

    override func makeWindowControllers() {
        guard windowControllers.isEmpty else { return }
        addWindowController(EditorWindowController(document: self))
    }

    override func data(ofType typeName: String) throws -> Data {
        Data(text.utf8)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard var value = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "Marknote", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.text(.unreadableFile)])
        }
        if value.hasPrefix("\u{feff}") { value.removeFirst() }
        text = value
        for controller in windowControllers {
            (controller as? EditorWindowController)?.reloadDocument()
        }
    }

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            completionHandler(error)
            if error == nil {
                // Let NSDocument complete its serialized save activity before reading its
                // file properties or touching windows again (especially for new drafts).
                DispatchQueue.main.async { [weak self] in
                    for controller in self?.windowControllers ?? [] {
                        (controller as? EditorWindowController)?.refreshPreview()
                    }
                }
            }
        }
    }
}

final class MarkdownDocumentController: NSDocumentController {
    override var defaultType: String? { MarkdownDocument.typeName }
    override func documentClass(forType typeName: String) -> AnyClass? { MarkdownDocument.self }
}
