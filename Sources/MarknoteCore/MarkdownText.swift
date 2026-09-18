import Foundation

public struct Heading: Equatable {
    public let title: String
    public let level: Int
    public let range: NSRange
}

public struct TextEdit: Equatable {
    public let range: NSRange
    public let replacement: String
    public let selection: NSRange

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }
}

public enum MarkdownText {
    public static func headings(in text: String) -> [Heading] {
        let source = text as NSString
        var result: [Heading] = []
        var offset = 0
        var fence: (Character, Int)?
        var previous: (String, NSRange)?
        while offset < source.length {
            let range = source.lineRange(for: NSRange(location: offset, length: 0))
            let raw = source.substring(with: range).trimmingCharacters(in: .newlines)
            let line = raw.trimmingCharacters(in: .whitespaces)
            let indent = raw.prefix(while: { $0 == " " }).count
            defer { offset = NSMaxRange(range) }
            if indent < 4, let char = line.first, char == "`" || char == "~" {
                let count = line.prefix(while: { $0 == char }).count
                if count >= 3 {
                    if let active = fence {
                        if char == active.0 && count >= active.1 && line.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
                    } else { fence = (char, count) }
                    previous = nil
                    continue
                }
            }
            guard fence == nil, indent < 4 else { previous = nil; continue }
            let count = line.prefix(while: { $0 == "#" }).count
            if (1...6).contains(count), line.count == count || line.dropFirst(count).first?.isWhitespace == true {
                let title = String(line.dropFirst(count)).trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: #"\s+#+\s*$"#, with: "", options: .regularExpression)
                result.append(Heading(title: title.isEmpty ? L10n.text(.untitledHeading) : title, level: count, range: range))
                previous = nil
            } else if let last = previous, !line.isEmpty,
                      line.allSatisfy({ $0 == "=" }) || line.allSatisfy({ $0 == "-" }) {
                result.append(Heading(title: last.0, level: line.first == "=" ? 1 : 2, range: last.1))
                previous = nil
            } else {
                previous = line.isEmpty || line.hasPrefix(">") || line.hasPrefix("-") ? nil : (line, range)
            }
        }
        return result
    }

    public static func wordCount(_ text: String) -> Int {
        let regex = try! NSRegularExpression(pattern: #"[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}]|[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*"#)
        // CJK characters count individually; Latin words count as words.
        let separated = text.replacingOccurrences(of: #"([\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}])"#, with: " $1 ", options: .regularExpression)
        return regex.numberOfMatches(in: separated, range: NSRange(location: 0, length: (separated as NSString).length))
    }

    public static func wrap(_ text: String, selection: NSRange, marker: String, placeholder: String) -> TextEdit {
        let source = text as NSString
        let size = (marker as NSString).length
        let selected = source.substring(with: selection)
        if selection.length >= size * 2, selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let content = (selected as NSString).substring(with: NSRange(location: size, length: selection.length - 2 * size))
            return TextEdit(range: selection, replacement: content, selection: NSRange(location: selection.location, length: (content as NSString).length))
        }
        if selection.location >= size, NSMaxRange(selection) + size <= source.length,
           source.substring(with: NSRange(location: selection.location - size, length: size)) == marker,
           source.substring(with: NSRange(location: NSMaxRange(selection), length: size)) == marker {
            return TextEdit(range: NSRange(location: selection.location - size, length: selection.length + 2 * size), replacement: selected,
                            selection: NSRange(location: selection.location - size, length: selection.length))
        }
        let content = selection.length == 0 ? placeholder : selected
        return TextEdit(range: selection, replacement: marker + content + marker,
                        selection: NSRange(location: selection.location + size, length: (content as NSString).length))
    }

    public static func prefixLines(_ text: String, selection: NSRange, prefix: String) -> TextEdit {
        let source = text as NSString
        let adjusted = NSRange(location: selection.location, length: max(0, selection.length - (selection.length > 0 ? 1 : 0)))
        let range = source.lineRange(for: adjusted)
        let content = source.substring(with: range)
        let hasNewline = content.hasSuffix("\n")
        var lines = content.components(separatedBy: "\n")
        if hasNewline { lines.removeLast() }
        let remove = lines.allSatisfy { $0.hasPrefix(prefix) }
        let replacement = lines.map { remove ? String($0.dropFirst(prefix.count)) : prefix + $0 }.joined(separator: "\n") + (hasNewline ? "\n" : "")
        return TextEdit(range: range, replacement: replacement,
                        selection: NSRange(location: range.location, length: (replacement as NSString).length))
    }

    public static func newline(_ text: String, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let source = text as NSString
        let lineRange = source.lineRange(for: selection)
        let before = source.substring(with: NSRange(location: lineRange.location, length: selection.location - lineRange.location))
        let regex = try! NSRegularExpression(pattern: #"^(\s*)(?:([-+*])(?: \[([ xX])\])? |(\d+)([.)]) |> )(.*)$"#)
        let ns = before as NSString
        guard let match = regex.firstMatch(in: before, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ n: Int) -> String { match.range(at: n).location == NSNotFound ? "" : ns.substring(with: match.range(at: n)) }
        let indent = group(1)
        if group(6).isEmpty {
            let range = NSRange(location: lineRange.location, length: before.utf16.count)
            return TextEdit(range: range, replacement: "", selection: NSRange(location: range.location, length: 0))
        }
        let prefix: String
        if !group(2).isEmpty { prefix = group(2) + (group(3).isEmpty ? " " : " [ ] ") }
        else if let number = Int(group(4)), number < Int.max { prefix = "\(number + 1)\(group(5)) " }
        else { prefix = "> " }
        let replacement = "\n" + indent + prefix
        return TextEdit(range: selection, replacement: replacement,
                        selection: NSRange(location: selection.location + replacement.utf16.count, length: 0))
    }
}
