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

    func testFrontMatterPreservesLinesAndBody() {
        let metadata = """
        ---
        doc_id: DOC-0005
        title: Document Metadata, Preview Layout and Export Settings
        type: spec
        audience: internal
        status: proposed
        owner: Example Author
        approvals: reviewers=pending, editors=pending
        decision_owner: Example Author
        version: 0.2
        related: [DOC-001, DOC-002, DOC-003, DOC-004, DOC-005, DOC-006, DOC-007, DOC-008, DOC-009]
        controls: []
        ---
        """
        let source = metadata + "\n\n# DOC-0005\n\n## Status\n\n**Proposed**"
        let renderer = MarkdownRenderer()
        let html = renderer.body(source)
        expect(html.contains("<pre class=\"frontmatter\"><code>" + metadata))
        expect(html.contains("</code></pre>\n<h1 id=\"doc-0005\">DOC-0005</h1>"))
        expect(html.contains("<h2 id=\"status\">Status</h2>"))
        expect(html.contains("<strong>Proposed</strong>"))
        expectFalse(html.contains("<hr>"))
        expectEqual(html.components(separatedBy: "<h2").count - 1, 1)
        expect(renderer.page(source).contains(html))
        expectEqual(MarkdownText.headings(in: source).map(\.title), ["DOC-0005", "Status"])
    }

    func testFrontMatterIsLiteralAndExcludedFromOutline() {
        let source = "---\n# YAML comment 🌱\ntitle: '**literal**'\nsummary: |\n  # Not a heading\n  <script>alert(1)</script> & text\n\ntags:\n  - first\n  - second\n---\n# 正文 🌱\n\nSection\n---"
        let html = MarkdownRenderer().body(source)
        expect(html.contains("title: '**literal**'"))
        expect(html.contains("summary: |\n  # Not a heading\n  &lt;script&gt;alert(1)&lt;/script&gt; &amp; text"))
        expect(html.contains("\ntags:\n  - first\n  - second\n"))
        expectFalse(html.contains("<script>"))
        expectFalse(html.contains("<strong>"))
        expectFalse(html.contains("<ul>"))
        let headings = MarkdownText.headings(in: source)
        expectEqual(headings.map(\.title), ["正文 🌱", "Section"])
        expectEqual(headings.map(\.level), [1, 2])
        expectEqual(headings.first?.range, (source as NSString).range(of: "# 正文 🌱\n"))
    }

    func testFrontMatterDelimitersAndLineEndings() {
        let renderer = MarkdownRenderer()
        for newline in ["\n", "\r\n", "\r"] {
            for closing in ["---", "..."] {
                for prefix in ["", "\u{FEFF}"] {
                    let metadata = "--- \t" + newline + "title: 中文 🌱" + newline + closing + "\t "
                    let source = prefix + metadata + newline + "# Body"
                    let html = renderer.body(source)
                    expect(html.contains("<pre class=\"frontmatter\"><code>" + metadata))
                    expect(html.contains("<h1 id=\"body\">Body</h1>"))
                    let headings = MarkdownText.headings(in: source)
                    expectEqual(headings.map(\.title), ["Body"])
                    expectEqual(headings.first?.range, (source as NSString).range(of: "# Body"))
                    expect(renderer.body(prefix + metadata).contains("</code></pre>"))
                }
            }
        }
        expect(renderer.body("---\n---").contains("class=\"frontmatter\""))
    }

    func testFrontMatterDoesNotChangeOrdinaryMarkdown() {
        let renderer = MarkdownRenderer()
        for source in ["---", "---\ntitle: unfinished\n# Body", "Intro\n\n---\ntitle: middle\n---", "```yaml\n---\ntitle: example\n---\n```", "> ---\n> title: quote\n> ---", "    ---\n    title: code\n    ---", "----\ntitle: ordinary\n----"] {
            expectFalse(renderer.body(source).contains("class=\"frontmatter\""))
        }
        expect(renderer.body("Title\n---").contains("<h2 id=\"title\">Title</h2>"))
        expectEqual(renderer.body("Before\n\n---\n\nAfter"), "<p>Before</p>\n<hr>\n<p>After</p>\n")
        expectEqual(renderer.body("first\nsecond"), "<p>first\nsecond</p>\n")
        expectEqual(renderer.body("first  \nsecond"), "<p>first<br>second</p>\n")
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

    func testMermaidBlocksAndOfflineExport() {
        let renderer = MarkdownRenderer()
        let source = "```mermaid\ngraph TD\n A[<script>alert(1)</script>] --> B\n```"
        let body = renderer.body(source)
        expect(body.contains("<pre class=\"mermaid\">"))
        expect(body.contains("&lt;script&gt;"))
        expectFalse(body.contains("<script>"))
        let page = renderer.page(source)
        expect(page.contains("window.marknoteReady"))
        expect(page.contains("script-src 'nonce-"))
        expectFalse(page.contains("<script src="))
        expect(renderer.body("```swift\nlet x = 1\n```").contains("language-swift"))
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
