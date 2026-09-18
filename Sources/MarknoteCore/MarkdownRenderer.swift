import Foundation
import JavaScriptCore

public final class MarkdownRenderer {
    private let context: JSContext
    private var baseDirectory: URL?

    public init() {
        context = JSContext()!
        let resources = AppResources.bundle
        let script = try! String(contentsOf: resources.url(forResource: "marked", withExtension: "js")!, encoding: .utf8)
        context.evaluateScript(script)
        let image: @convention(block) (String) -> String = { [weak self] path in self?.localImage(path) ?? "" }
        context.setObject(image, forKeyedSubscript: "localImage" as NSString)
        context.evaluateScript(#"""
        function escapeHTML(s) {
            return String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
        }
        function safeURL(s, image) {
            if (/^(https?:\/\/)/i.test(s)) return s;
            if (!image && (/^mailto:/i.test(s) || /^#[^\s]*$/.test(s))) return s;
            if (image && !/^[a-z][a-z0-9+.-]*:/i.test(s) && !s.startsWith('//')) return localImage(s);
            return '';
        }
        marked.use({gfm:true, breaks:false, renderer: {
            html({text}) { return escapeHTML(text); },
            link({href,title,tokens}) {
                const label = this.parser.parseInline(tokens);
                const url = safeURL(href, false);
                return url ? '<a href="'+escapeHTML(url)+'"'+(title ? ' title="'+escapeHTML(title)+'"' : '')+'>'+label+'</a>' : label;
            },
            image({href,title,text}) {
                const url = safeURL(href, true);
                return url ? '<img src="'+escapeHTML(url)+'" alt="'+escapeHTML(text)+'"'+(title ? ' title="'+escapeHTML(title)+'"' : '')+'>' : '<span class="image-placeholder">▧ '+escapeHTML(text || imageUnavailable)+'</span>';
            },
            heading({tokens,depth,text}) {
                const id = text.toLowerCase().replace(/[^\p{L}\p{N}\s_-]/gu, '').replace(/\s/g, '-');
                return '<h'+depth+' id="'+escapeHTML(id)+'">'+this.parser.parseInline(tokens)+'</h'+depth+'>\n';
            }
        }});
        function renderMarkdown(source) { return marked.parse(source); }
        """#)
    }

    public func body(_ markdown: String, relativeTo directory: URL? = nil) -> String {
        baseDirectory = directory
        context.exception = nil
        context.setObject(L10n.text(.imageUnavailable), forKeyedSubscript: "imageUnavailable" as NSString)
        let result = context.objectForKeyedSubscript("renderMarkdown")?.call(withArguments: [markdown])
        guard context.exception == nil, let output = result?.toString() else {
            return "<pre>" + Self.escape(markdown) + "</pre>"
        }
        return output
    }

    public func page(_ markdown: String, title: String? = nil, relativeTo directory: URL? = nil, dark: Bool? = nil) -> String {
        let content = body(markdown, relativeTo: directory)
        let theme = dark.map { $0 ? "dark" : "light" } ?? "auto"
        return """
        <!doctype html><html lang="\(L10n.shared.language.rawValue)" data-theme="\(theme)"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: http: data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
        <title>\(Self.escape(title ?? L10n.text(.appName)))</title><style>\(Self.css)</style></head>
        <body><article>\(content.isEmpty ? "<div class='empty'><span>" + Self.escape(L10n.text(.emptyTitle)) + "</span><p>" + Self.escape(L10n.text(.emptyMessage)) + "</p></div>" : content)</article></body></html>
        """
    }

    private func localImage(_ path: String) -> String {
        guard let root = baseDirectory?.standardizedFileURL.resolvingSymlinksInPath(),
              let decoded = path.removingPercentEncoding, !decoded.hasPrefix("/") else { return "" }
        let url = root.appendingPathComponent(decoded).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.path + "/") else { return "" }
        let types = ["png":"image/png", "jpg":"image/jpeg", "jpeg":"image/jpeg", "gif":"image/gif", "webp":"image/webp"]
        guard let type = types[url.pathExtension.lowercased()],
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber, size.intValue <= 20_000_000,
              let data = try? Data(contentsOf: url) else { return "" }
        return "data:\(type);base64," + data.base64EncodedString()
    }

    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let css = """
    :root{color-scheme:light dark;--paper:#fff;--ink:#292d32;--muted:#7b8088;--line:#e9e9e7;--soft:#f5f6f4;--accent:#387963}
    @media(prefers-color-scheme:dark){:root:not([data-theme=light]){--paper:#202322;--ink:#dcdedb;--muted:#989f98;--line:#373c38;--soft:#292e2a;--accent:#91bda5}}
    :root[data-theme=dark]{--paper:#202322;--ink:#dcdedb;--muted:#989f98;--line:#373c38;--soft:#292e2a;--accent:#91bda5}
    *{box-sizing:border-box}html{background:var(--paper);color:var(--ink);scroll-behavior:smooth}
    body{margin:0;font:16px/1.9 -apple-system,BlinkMacSystemFont,'PingFang SC',sans-serif;overflow-wrap:break-word}
    article{max-width:800px;margin:0 auto;padding:42px 46px 90px}h1,h2,h3,h4,h5,h6{line-height:1.45;letter-spacing:-.025em;font-weight:650;scroll-margin-top:30px}
    h1{font-size:32px;margin:0 0 25px}h2{font-size:23px;margin:36px 0 16px;padding-bottom:10px;border-bottom:1px solid var(--line)}h3{font-size:19px;margin:28px 0 12px}
    p{margin:16px 0}a{color:var(--accent);text-decoration-thickness:1px;text-underline-offset:3px}strong{font-weight:650}
    blockquote{margin:24px 0;padding:1px 20px;border-left:3px solid var(--accent);color:var(--muted);background:var(--soft);border-radius:0 6px 6px 0}
    ul,ol{padding-left:25px}li{padding-left:4px;margin:5px 0}li>ul,li>ol{margin:4px 0}li:has(>input[type=checkbox]){list-style:none;margin-left:-22px}
    input[type=checkbox]{accent-color:var(--accent);margin-right:8px}code{font:13px/1.7 ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--soft);padding:3px 6px;border-radius:4px}
    pre{padding:20px 22px;overflow:auto;background:var(--soft);border:1px solid var(--line);border-radius:8px;line-height:1.7}pre code{padding:0;background:none;white-space:pre}
    table{width:100%;border-collapse:collapse;margin:24px 0;font-size:14px;display:block;overflow:auto}th,td{border:1px solid var(--line);padding:9px 15px;text-align:left}th{background:var(--soft);font-weight:600}
    img{max-width:100%;height:auto;border-radius:6px}hr{border:0;border-top:1px solid var(--line);margin:32px 0}del{color:var(--muted)}.image-placeholder{color:var(--muted);font-size:14px}
    .empty{padding-top:100px;text-align:center;color:var(--muted)}.empty span{font-size:22px;color:var(--ink)}.empty p{font-size:13px}
    @media(max-width:480px){article{padding:30px 25px 70px}h1{font-size:28px}}
    @media print{html{--paper:#fff;--ink:#222;--muted:#666;--line:#ddd;--soft:#f5f5f5;--accent:#387963;color-scheme:light}article{padding:0;max-width:none}pre,blockquote,img,tr{break-inside:avoid}h1,h2,h3{break-after:avoid}a{color:inherit}}
    """
}
