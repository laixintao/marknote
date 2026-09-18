import Foundation
import MarknoteCore

final class EditingToolsTests {
    func testSmartLinks() {
        let source = "Before 中文🌱 [label] after"
        let selection = (source as NSString).range(of: "中文🌱 [label]")
        let edit = SmartLink.edit(source, selection: selection, clipboard: "https://example.com/a(b)?q=中文")!
        expectEqual(edit.range, selection)
        expect(edit.replacement.contains("[中文🌱 \\[label\\]]"))
        expect(edit.replacement.contains("a%28b%29"))
        let changed = (source as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        expectEqual((changed as NSString).substring(with: edit.selection), "中文🌱 \\[label\\]")
        expect(MarkdownRenderer().body(changed).contains("<a href="))
        for value in ["javascript:alert(1)", "file:///etc/passwd", "data:text/html,x", "not a URL", "https://", "https://example.com two"] {
            expectNil(SmartLink.edit(source, selection: selection, clipboard: value))
        }
        expect(SmartLink.edit(source, selection: selection, clipboard: "mailto:writer@example.com") != nil)
        expectNil(SmartLink.edit(source, selection: NSRange(location: 0, length: 0), clipboard: "https://example.com"))
        expectNil(SmartLink.edit("two\nlines", selection: NSRange(location: 0, length: 9), clipboard: "https://example.com"))
        expectNil(SmartLink.edit(source, selection: NSRange(location: NSNotFound, length: 9), clipboard: "https://example.com"))
    }

    func testSearchMatching() {
        expectEqual(SearchMatcher.score("", in: "anything"), 0)
        expect(SearchMatcher.score("PrEv", in: "Preview Only") != nil)
        expect(SearchMatcher.score("cafe", in: "Café notes") != nil)
        expect(SearchMatcher.score("命面", in: "命令面板") != nil)
        expect(SearchMatcher.score("ex pdf", in: "Export as PDF") != nil)
        expectNil(SearchMatcher.score("absent", in: "Preview"))
        expect(SearchMatcher.score("save", in: "Save")! < SearchMatcher.score("save", in: "Save As")!)
        expect(SearchMatcher.score("preview", in: "Preview mode")! < SearchMatcher.score("preview", in: "Show preview")!)
        expect(SearchMatcher.score("sf", in: "Save file") != nil)
    }

    func testTableFormatting() {
        let source = "Intro 🌱\n\n| Name | 中文 |\n| :--- | ---: |\n| longer 🌱 | a\\|b |\n| x | 尾 |\n\nEnd"
        let selected = (source as NSString).range(of: "中文")
        let edit = MarkdownTable.format(source, selection: selected)!
        let changed = (source as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        expect(changed.hasPrefix("Intro 🌱\n\n"))
        expect(changed.hasSuffix("\n\nEnd"))
        expect(changed.contains("a\\|b"))
        expectEqual((changed as NSString).substring(with: edit.selection), "中文")
        expectEqual(MarkdownTable.format(changed, selection: edit.selection)!.replacement, edit.replacement)
        expect(MarkdownRenderer().body(changed).contains("align=\"left\""))
        expect(MarkdownRenderer().body(changed).contains("align=\"right\""))
        expect(MarkdownRenderer().body(changed).contains("a|b"))
        let centered = "a | b\r\n:---: | ---\r\nx | y"
        let formatted = MarkdownTable.format(centered, selection: NSRange(location: 0, length: 0))!
        expect(formatted.replacement.contains("\r\n"))
        expectFalse(formatted.replacement.hasSuffix("\n"))
        expect(formatted.replacement.contains(":---:"))
        let escaped = "a | b\\|\n--- | ---\nx | y\n"
        expect(MarkdownTable.format(escaped, selection: NSRange(location: 0, length: 0))!.replacement.contains("b\\|"))
        let ragged = "a | b\n--- | ---\nx | y | extra\n"
        expect(MarkdownTable.format(ragged, selection: NSRange(location: 0, length: 0))!.replacement.contains("extra"))
    }

    func testTableNavigation() {
        let source = "| A | 中文 |\n| --- | --- |\n| 1 | 🌱 |\n"
        let first = MarkdownTable.navigate(source, selection: (source as NSString).range(of: "A"))!
        expectEqual((source as NSString).substring(with: first.selection), "中文")
        expectEqual(first.replacement, "")
        let next = MarkdownTable.navigate(source, selection: first.selection)!
        expectEqual((source as NSString).substring(with: next.selection), "1")
        let previous = MarkdownTable.navigate(source, selection: next.selection, backwards: true)!
        expectEqual(previous.selection, first.selection)
        let append = MarkdownTable.navigate(source, selection: (source as NSString).range(of: "🌱"))!
        let changed = (source as NSString).replacingCharacters(in: append.range, with: append.replacement)
        expectEqual(changed.components(separatedBy: "\n").count, 5)
        expectEqual(append.selection.length, 0)
        expectEqual((changed as NSString).substring(with: NSRange(location: append.selection.location - 2, length: 2)), "| ")
        expectNil(MarkdownTable.navigate(source, selection: NSRange(location: source.utf16.count, length: 0)))
        let code = "```md\n" + source + "```\n"
        expectNil(MarkdownTable.format(code, selection: (code as NSString).range(of: "A")))
        expectNil(MarkdownTable.navigate("one | two\nplain text", selection: NSRange(location: 2, length: 0)))
        let indented = source.split(separator: "\n").map { "    " + $0 }.joined(separator: "\n")
        expectNil(MarkdownTable.format(indented, selection: (indented as NSString).range(of: "A")))
    }

    func testAttachmentStorage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let image = ImageAttachment(data: Data([1, 2, 3]), fileExtension: "PNG", name: "截图 [一]\n🌱")
        let document = root.appendingPathComponent("中文 note.md")
        let links = try AttachmentStore.store([image, image], beside: document)
        expectEqual(links.count, 2)
        expectFalse(links[0] == links[1])
        expect(links[0].hasPrefix("![截图 \\[一\\] 🌱](assets/"))
        let assets = root.appendingPathComponent("assets")
        let files = try FileManager.default.contentsOfDirectory(at: assets, includingPropertiesForKeys: nil)
        expectEqual(files.count, 2)
        for file in files { expectEqual(try Data(contentsOf: file), image.data) }
        do { _ = try AttachmentStore.store([image], beside: nil); expect(false, "Untitled documents must be saved first") } catch { expect(error is AttachmentStore.Failure) }
        do {
            _ = try AttachmentStore.store([image, ImageAttachment(data: Data([1]), fileExtension: "../txt", name: "bad")], beside: document)
            expect(false, "Unsupported image accepted")
        } catch { expectEqual(try FileManager.default.contentsOfDirectory(atPath: assets.path).count, 2) }
        try FileManager.default.removeItem(at: assets)
        try FileManager.default.createSymbolicLink(at: assets, withDestinationURL: outside)
        do { _ = try AttachmentStore.store([image], beside: document); expect(false, "Escaping symlink accepted") }
        catch { expect(error is AttachmentStore.Failure) }
        expectEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path).count, 0)
    }
}
