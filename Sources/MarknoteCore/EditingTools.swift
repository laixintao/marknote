import Foundation

public enum SearchMatcher {
    /// Lower scores rank first. Exact/prefix matches win over subsequences.
    public static func score(_ query: String, in candidate: String) -> Int? {
        let needle = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace).map(String.init)
        let haystack = candidate.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !needle.isEmpty else { return 0 }
        var total = 0
        for word in needle {
            if haystack == word { continue }
            if haystack.hasPrefix(word) { total += 1; continue }
            if let range = haystack.range(of: word) { total += 10 + haystack.distance(from: haystack.startIndex, to: range.lowerBound); continue }
            var cursor = haystack.startIndex
            var gaps = 0
            for character in word {
                guard let found = haystack[cursor...].firstIndex(of: character) else { return nil }
                gaps += haystack.distance(from: cursor, to: found)
                cursor = haystack.index(after: found)
            }
            total += 100 + gaps
        }
        return total
    }
}

public enum SmartLink {
    public static func edit(_ source: String, selection: NSRange, clipboard: String) -> TextEdit? {
        let text = source as NSString
        guard selection.length > 0, selection.location <= text.length,
              selection.length <= text.length - selection.location else { return nil }
        let label = text.substring(with: selection)
        let value = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.contains("\n"), !value.contains(where: \.isWhitespace),
              let url = URLComponents(string: value), let scheme = url.scheme?.lowercased(),
              (["http", "https"].contains(scheme) && !(url.host ?? "").isEmpty) || (scheme == "mailto" && url.path.contains("@")) else { return nil }
        let escaped = label.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        let destination = value.replacingOccurrences(of: "<", with: "%3C").replacingOccurrences(of: ">", with: "%3E")
            .replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
            .replacingOccurrences(of: "\\", with: "%5C")
        let replacement = "[\(escaped)](\(destination))"
        return TextEdit(range: selection, replacement: replacement,
                        selection: NSRange(location: selection.location + 1, length: escaped.utf16.count))
    }
}

public enum MarkdownTable {
    private struct Cell { let text: String; let range: NSRange }
    private struct Row { let cells: [Cell]; let range: NSRange; let indent: String; let newline: String }
    private struct Table { let rows: [Row]; let row: Int; let column: Int }

    private static func cells(_ line: NSString, offset: Int) -> [Cell]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var edges: [Int] = []
        var escapes = 0
        for i in 0..<line.length {
            let c = line.character(at: i)
            if c == 124 && escapes % 2 == 0 { edges.append(i) }
            escapes = c == 92 ? escapes + 1 : 0
        }
        guard !edges.isEmpty else { return nil }
        var boundaries = [-1] + edges + [line.length]
        if trimmed.hasPrefix("|") { boundaries.removeFirst() }
        if trimmed.hasSuffix("|"), edges.last == line.length - (line as String).reversed().prefix(while: \.isWhitespace).count - 1 { boundaries.removeLast() }
        var result: [Cell] = []
        for (left, right) in zip(boundaries, boundaries.dropFirst()) {
            let raw = line.substring(with: NSRange(location: left + 1, length: right - left - 1))
            let value = raw.trimmingCharacters(in: .whitespaces)
            let leading = raw.prefix(while: \.isWhitespace).utf16.count
            result.append(Cell(text: value, range: NSRange(location: offset + left + 1 + leading, length: value.utf16.count)))
        }
        return result.count >= 2 ? result : nil
    }

    private static func table(in source: String, at location: Int) -> Table? {
        let text = source as NSString
        guard location <= text.length else { return nil }
        var rows: [Row?] = []
        var offset = 0, selected = -1
        var fence: (Character, Int)?
        while offset < text.length {
            let range = text.lineRange(for: NSRange(location: offset, length: 0))
            let full = text.substring(with: range)
            let line = full.trimmingCharacters(in: .newlines)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
            var blocked = fence != nil || indent.count >= 4 || indent.contains("\t")
            if indent.count < 4, let char = trimmed.first, char == "`" || char == "~" {
                let count = trimmed.prefix(while: { $0 == char }).count
                if count >= 3 {
                    blocked = true
                    if let active = fence {
                        if char == active.0 && count >= active.1 && trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
                    } else { fence = (char, count) }
                }
            }
            if location >= range.location && (location < NSMaxRange(range) || location == text.length && !full.hasSuffix("\n") && !full.hasSuffix("\r")) { selected = rows.count }
            let newline = full.hasSuffix("\r\n") ? "\r\n" : full.hasSuffix("\n") ? "\n" : ""
            rows.append(blocked ? nil : cells(line as NSString, offset: offset).map { Row(cells: $0, range: range, indent: indent, newline: newline) })
            offset = NSMaxRange(range)
        }
        guard selected >= 0, rows[selected] != nil else { return nil }
        var start = selected, end = selected
        while start > 0, rows[start - 1] != nil { start -= 1 }
        while end + 1 < rows.count, rows[end + 1] != nil { end += 1 }
        let block = rows[start...end].compactMap { $0 }
        guard block.count >= 2, block[0].cells.count == block[1].cells.count,
              block[1].cells.allSatisfy({ $0.text.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil }) else { return nil }
        let row = selected - start
        let column = block[row].cells.firstIndex(where: { location <= NSMaxRange($0.range) }) ?? block[row].cells.count - 1
        return Table(rows: block, row: row, column: column)
    }

    private static func width(_ text: String) -> Int {
        text.reduce(0) { count, character in
            let wide = character.unicodeScalars.contains { scalar in
                let v = scalar.value
                return scalar.properties.isEmojiPresentation || (0x2E80...0xA4CF).contains(v) || (0xAC00...0xD7A3).contains(v)
                    || (0xF900...0xFAFF).contains(v) || (0xFF01...0xFF60).contains(v) || (0x20000...0x3FFFD).contains(v)
            }
            return count + (wide ? 2 : 1)
        }
    }

    public static func format(_ source: String, selection: NSRange) -> TextEdit? {
        guard let table = table(in: source, at: selection.location) else { return nil }
        let columns = table.rows.map { $0.cells.count }.max()!
        var widths = (0..<columns).map { c in
            let alignment = c < table.rows[1].cells.count ? table.rows[1].cells[c].text : ""
            return 3 + (alignment.hasPrefix(":") ? 1 : 0) + (alignment.hasSuffix(":") ? 1 : 0)
        }
        for (r, row) in table.rows.enumerated() where r != 1 {
            for (c, cell) in row.cells.enumerated() { widths[c] = max(widths[c], width(cell.text)) }
        }
        var replacement = "", selected = NSRange(location: 0, length: 0)
        let start = table.rows[0].range.location
        for (r, row) in table.rows.enumerated() {
            replacement += row.indent + "|"
            for c in 0..<columns {
                let value = c < row.cells.count ? row.cells[c].text : ""
                let content: String
                if r == 1 {
                    content = (value.hasPrefix(":") ? ":" : "") + String(repeating: "-", count: max(3, widths[c] - (value.hasPrefix(":") ? 1 : 0) - (value.hasSuffix(":") ? 1 : 0))) + (value.hasSuffix(":") ? ":" : "")
                } else { content = value + String(repeating: " ", count: max(0, widths[c] - width(value))) }
                replacement += " "
                if r == table.row && c == table.column { selected = NSRange(location: start + replacement.utf16.count, length: value.utf16.count) }
                replacement += content + " |"
            }
            replacement += row.newline
        }
        return TextEdit(range: NSRange(location: start, length: NSMaxRange(table.rows.last!.range) - start), replacement: replacement, selection: selected)
    }

    public static func navigate(_ source: String, selection: NSRange, backwards: Bool = false) -> TextEdit? {
        guard let table = table(in: source, at: selection.location) else { return nil }
        let positions = table.rows.enumerated().filter { $0.offset != 1 }.flatMap { r, row in row.cells.indices.map { (r, $0) } }
        let current = positions.firstIndex { $0.0 == table.row && $0.1 == table.column } ?? 0
        let next = current + (backwards ? -1 : 1)
        if next >= 0 && next < positions.count {
            let (row, column) = positions[next]
            return TextEdit(range: NSRange(location: selection.location, length: 0), replacement: "", selection: table.rows[row].cells[column].range)
        }
        if backwards {
            return TextEdit(range: NSRange(location: selection.location, length: 0), replacement: "", selection: table.rows[0].cells[0].range)
        }
        let last = table.rows.last!
        let newline = table.rows[0].newline.isEmpty ? "\n" : table.rows[0].newline
        let prefix = last.newline.isEmpty ? newline : ""
        let row = table.rows[0].indent + "|" + String(repeating: "   |", count: table.rows[0].cells.count)
        let start = NSMaxRange(last.range)
        return TextEdit(range: NSRange(location: start, length: 0), replacement: prefix + row + newline,
                        selection: NSRange(location: start + prefix.utf16.count + table.rows[0].indent.utf16.count + 2, length: 0))
    }
}
