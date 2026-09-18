import AppKit
import MarknoteCore

final class MarkdownTextView: NSTextView {
    var fontSize: CGFloat = 14
    var onAppearanceChange: (() -> Void)?
    var onImages: (([ImageAttachment], NSRange) -> Void)?
    var onImportError: ((Error) -> Void)?
    var paragraphFocus = false { didSet { updateWritingFocus() } }
    var typewriterScrolling = false { didSet { updateWritingFocus() } }

    override func paste(_ sender: Any?) {
        if !paste(from: .general) { super.paste(sender) }
    }

    @discardableResult func paste(from pasteboard: NSPasteboard) -> Bool {
        guard !hasMarkedText() else { return false }
        if ImageImport.canRead(pasteboard), let onImages {
            do { onImages(try ImageImport.read(pasteboard), selectedRange()) }
            catch { onImportError?(error) }
            return true
        }
        if let value = pasteboard.string(forType: .string), let edit = SmartLink.edit(string, selection: selectedRange(), clipboard: value) {
            apply(edit, name: L10n.text(.insertLink))
            return true
        }
        return false
    }

    override func pasteAsPlainText(_ sender: Any?) {
        if let value = NSPasteboard.general.string(forType: .string) { insertText(value, replacementRange: selectedRange()) }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        ImageImport.canRead(sender.draggingPasteboard) ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        ImageImport.canRead(sender.draggingPasteboard) ? .copy : super.draggingUpdated(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        ImageImport.canRead(sender.draggingPasteboard) || super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !hasMarkedText(), ImageImport.canRead(sender.draggingPasteboard), let onImages else { return super.performDragOperation(sender) }
        do {
            let location = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
            onImages(try ImageImport.read(sender.draggingPasteboard), NSRange(location: min(location, string.utf16.count), length: 0))
        } catch { onImportError?(error) }
        return true
    }

    override func insertTab(_ sender: Any?) {
        if !navigateTable(backwards: false) { super.insertTab(sender) }
    }

    override func insertBacktab(_ sender: Any?) {
        if !navigateTable(backwards: true) { super.insertBacktab(sender) }
    }

    private func navigateTable(backwards: Bool) -> Bool {
        guard !hasMarkedText(), let edit = MarkdownTable.navigate(string, selection: selectedRange(), backwards: backwards) else { return false }
        if edit.range.length == 0 && edit.replacement.isEmpty {
            setSelectedRange(edit.selection)
            scrollRangeToVisible(edit.selection)
        } else { apply(edit, name: L10n.text(.table)) }
        return true
    }

    func updateWritingFocus() {
        guard let manager = layoutManager, let container = textContainer, !hasMarkedText() else { return }
        let source = string as NSString
        let whole = NSRange(location: 0, length: source.length)
        manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
        if paragraphFocus, source.length > 0 {
            let active = source.paragraphRange(for: selectedRange())
            manager.addTemporaryAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, forCharacterRange: whole)
            manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: active)
        }
        guard let scroll = enclosingScrollView else { return }
        let inset = typewriterScrolling ? max(32, (scroll.contentSize.height - fontSize * 1.5) / 2) : 32
        if abs(textContainerInset.height - inset) > 1 { textContainerInset = NSSize(width: 27, height: inset) }
        guard typewriterScrolling, selectedRange().length == 0,
              NSApp.currentEvent?.type != .leftMouseDragged, NSApp.currentEvent?.type != .leftMouseDown else { return }
        manager.ensureLayout(for: container)
        let location = min(selectedRange().location, source.length)
        let rect: NSRect
        if location == source.length && (source.length == 0 || string.hasSuffix("\n")) {
            rect = manager.extraLineFragmentRect
        } else {
            let glyph = manager.glyphIndexForCharacter(at: min(location, source.length - 1))
            rect = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        }
        let y = max(0, min(frame.height - scroll.contentSize.height, textContainerOrigin.y + rect.midY - scroll.contentSize.height / 2))
        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        highlight()
        onAppearanceChange?()
    }

    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText(), let edit = MarkdownText.newline(string, selection: selectedRange()) else {
            super.insertNewline(sender)
            return
        }
        apply(edit, name: L10n.text(.continueList))
    }

    func apply(_ edit: TextEdit, name: String) {
        breakUndoCoalescing()
        insertText(edit.replacement, replacementRange: edit.range)
        breakUndoCoalescing()
        setSelectedRange(edit.selection)
        scrollRangeToVisible(edit.selection)
        undoManager?.setActionName(name)
    }

    func highlight() {
        guard let storage = textStorage, !hasMarkedText() else { return }
        let range = NSRange(location: 0, length: storage.length)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        paragraph.tabStops = []
        paragraph.defaultTabInterval = fontSize * 2.4
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraph
        ]
        storage.beginEditing()
        storage.setAttributes(base, range: range)
        func style(_ pattern: String, _ attributes: [NSAttributedString.Key: Any]) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
            for match in regex.matches(in: string, range: range) { storage.addAttributes(attributes, range: match.range) }
        }
        style(#"^ {0,3}#{1,6}(?:\s+.*|$)"#, [.foregroundColor: NSColor.systemTeal, .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)])
        style(#"\*\*[^\n]+?\*\*|__[^\n]+?__"#, [.font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)])
        style(#"(?<!\*)\*[^*\n]+\*(?!\*)"#, [.foregroundColor: NSColor.secondaryLabelColor])
        style(#"!?\[[^\]\n]*\]\([^\n)]*\)"#, [.foregroundColor: NSColor.systemBlue])
        style(#"^\s*(?:[-+*]|\d+[.)])\s+(?:\[[ xX]\])?|^>+"#, [.foregroundColor: NSColor.systemTeal])
        style(#"`[^`\n]+`"#, [.foregroundColor: NSColor.systemBrown, .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.07)])
        style(#"(?s)^ {0,3}(`{3,}|~{3,})[^\n]*\n.*?^ {0,3}\1[ \t]*$"#, [.foregroundColor: NSColor.secondaryLabelColor])
        storage.endEditing()
        typingAttributes = base
        updateWritingFocus()
    }
}

final class PaddedLabel: NSTextField {
    private var localizationKey: L10n.Key?

    convenience init(_ key: L10n.Key, size: CGFloat = 11, weight: NSFont.Weight = .regular, color: NSColor = .secondaryLabelColor) {
        self.init(L10n.text(key), size: size, weight: weight, color: color)
        localizationKey = key
    }

    func refreshLocalization() {
        if let key = localizationKey { stringValue = L10n.text(key) }
    }

    init(_ text: String, size: CGFloat = 11, weight: NSFont.Weight = .regular, color: NSColor = .secondaryLabelColor) {
        super.init(frame: .zero)
        stringValue = text
        font = .systemFont(ofSize: size, weight: weight)
        textColor = color
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        lineBreakMode = .byTruncatingTail
    }
    required init?(coder: NSCoder) { fatalError() }
}
