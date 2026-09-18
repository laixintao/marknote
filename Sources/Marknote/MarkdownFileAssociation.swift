import AppKit
import UniformTypeIdentifiers

@MainActor enum MarkdownFileAssociation {
    static let extensions = ["md", "markdown", "mdown", "mkd"]
    static var contentTypes: [UTType] {
        let known = ["net.daringfireball.markdown", "net.marknote.markdown"]
        let candidates = known.compactMap(UTType.init) + extensions.compactMap { UTType(filenameExtension: $0) }
        var seen = Set<String>()
        return candidates.filter { type in
            // General text types must keep their existing default application.
            (known.contains(type.identifier) || extensions.contains(type.preferredFilenameExtension ?? ""))
                && seen.insert(type.identifier).inserted
        }
    }

    static var isDefault: Bool {
        guard let type = UTType(filenameExtension: "md"),
              let application = NSWorkspace.shared.urlForApplication(toOpen: type) else { return false }
        return application.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    typealias Setter = (URL, UTType) async throws -> Void

    static func setDefault(applicationURL: URL = Bundle.main.bundleURL,
                           setter: Setter = { try await NSWorkspace.shared.setDefaultApplication(at: $0, toOpen: $1) }) async throws {
        for type in contentTypes {
            try await setter(applicationURL, type)
        }
    }
}
