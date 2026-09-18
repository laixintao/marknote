import Foundation
import MarknoteCore

var welcomeMarkdown: String {
    guard let url = L10n.shared.resource("Welcome", extension: "md"),
          let text = try? String(contentsOf: url, encoding: .utf8) else { return "# " + L10n.text(.appName) }
    return text
}
