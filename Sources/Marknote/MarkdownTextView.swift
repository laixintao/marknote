import AppKit
import MarknoteCore

final class MarkdownTextView: NSTextView {
    var fontSize: CGFloat = 14
    var onAppearanceChange: (() -> Void)?

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
