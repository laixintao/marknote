import Foundation
import MarknoteCore

final class MarkdownTests {
    func testCommonMarkAndGFM() {
        let renderer = MarkdownRenderer()
        let html = renderer.body("# 标题\n\n**加粗** and *italic* and ~~deleted~~\n\n> 引用\n\n1. 第一项\n2. 第二项\n\n- [x] 完成\n- [ ] 未完成\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n```swift\nlet a = 1 < 2\n```\n")
        for fragment in ["<h1", "<strong>加粗</strong>", "<em>italic</em>", "<del>deleted</del>", "<blockquote>", "<ol>", "type=\"checkbox\"", "<table>", "language-swift", "1 &lt; 2"] {
            expect(html.contains(fragment), "Missing \(fragment): \(html)")
        }
    }

    func testHTMLAndUnsafeLinksAreInert() {
        let renderer = MarkdownRenderer()
        let html = renderer.body("<script>alert(1)</script>\n\n<img src=x onerror=alert(1)>\n\n[bad](javascript:alert%281%29)\n\n[bad](JaVaScRiPt:evil)\n\n[bad](data:text/html,hello)\n\n![bad](file:///etc/passwd)\n\n[good](https://example.com)")
        expectFalse(html.contains("<script>"))
        expectFalse(html.contains("<img src=x"))
        expectFalse(html.contains("href=\"javascript:"))
        expectFalse(html.contains("href=\"JaVaScRiPt:"))
        expectFalse(html.contains("href=\"data:"))
        expectFalse(html.contains("src=\"file:"))
        expect(html.contains("href=\"https://example.com\""))
        expect(html.contains("&lt;script&gt;"))
    }

    func testNestedListsReferenceLinksAndEscapes() {
        let html = MarkdownRenderer().body("- parent\n  - child\n\n[Apple][apple]\n\n[apple]: https://apple.com\n\n\\*literal\\*\n\nTitle\n=====")
        expectEqual(html.components(separatedBy: "<ul>").count - 1, 2)
        expect(html.contains("href=\"https://apple.com\""))
        expect(html.contains("*literal*"))
        expect(html.contains("<h1"))
    }

    func testImagesStayWithinDocumentDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([137, 80, 78, 71]).write(to: root.appendingPathComponent("image.png"))
        let renderer = MarkdownRenderer()
        expect(renderer.body("![local](image.png)", relativeTo: root).contains("data:image/png;base64,"))
        expectFalse(renderer.body("![bad](../image.png)", relativeTo: root).contains("<img"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape.png"), withDestinationURL: URL(fileURLWithPath: "/etc/passwd"))
        expectFalse(renderer.body("![bad](escape.png)", relativeTo: root).contains("<img"))
        expectFalse(renderer.body("![bad](image.png)").contains("<img"))
    }

    func testOutlineExcludesFencedAndIndentedCode() {
        let text = "# 第一章 🌱\n\n```markdown\n# not a heading\n~~~\n## still fenced\n```\n\n    # indented\n\n## 第二章\n\nSetext title\n---\n"
        let headings = MarkdownText.headings(in: text)
        expectEqual(headings.map(\.title), ["第一章 🌱", "第二章", "Setext title"])
        expectEqual(headings.map(\.level), [1, 2, 2])
        expect((text as NSString).substring(with: headings[1].range).contains("## 第二章"))
    }

    func testUnicodeFormattingAndToggle() {
        let source = "你好 🌱 world"
        let selection = (source as NSString).range(of: "🌱")
        let edit = MarkdownText.wrap(source, selection: selection, marker: "**", placeholder: "文字")
        let formatted = (source as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        expectEqual(formatted, "你好 **🌱** world")
        let undo = MarkdownText.wrap(formatted, selection: edit.selection, marker: "**", placeholder: "文字")
        expectEqual((formatted as NSString).replacingCharacters(in: undo.range, with: undo.replacement), source)
    }

    func testSelectedLineBoundaries() {
        let source = "one\ntwo\nthree\n"
        let edit = MarkdownText.prefixLines(source, selection: NSRange(location: 0, length: 8), prefix: "> ")
        expectEqual((source as NSString).replacingCharacters(in: edit.range, with: edit.replacement), "> one\n> two\nthree\n")
        let empty = MarkdownText.prefixLines("", selection: NSRange(location: 0, length: 0), prefix: "# ")
        expectEqual(empty.replacement, "# ")
    }

    func testListContinuationAndExit() {
        let cases = [("- hello", "\n- "), ("  - [x] 完成", "\n  - [ ] "), ("9. 🌱", "\n10. "), ("> 引用", "\n> ")]
        for (text, expected) in cases {
            let edit = MarkdownText.newline(text, selection: NSRange(location: text.utf16.count, length: 0))
            expectEqual(edit?.replacement, expected)
        }
        let empty = MarkdownText.newline("- [ ] ", selection: NSRange(location: 6, length: 0))
        expectEqual(empty?.replacement, "")
        expectEqual(empty?.range, NSRange(location: 0, length: 6))
        expectNil(MarkdownText.newline("ordinary paragraph", selection: NSRange(location: 4, length: 0)))
    }

    func testWordCountHandlesCJKAndLatin() {
        expectEqual(MarkdownText.wordCount("你好 world 🌱 hello"), 4)
        expectEqual(MarkdownText.wordCount(""), 0)
        expectEqual(MarkdownText.wordCount("中文English混合"), 5)
    }

    func testStandaloneExportAndEmptyPreview() {
        let renderer = MarkdownRenderer()
        let html = renderer.page("# content", title: "<unsafe>")
        expect(html.contains("<title>&lt;unsafe&gt;</title>"))
        expect(html.contains("Content-Security-Policy"))
        expectFalse(html.contains("<script"))
        expect(renderer.page("").contains(L10n.text(.emptyTitle)))
    }
}
