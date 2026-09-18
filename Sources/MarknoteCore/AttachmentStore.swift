import Foundation

public struct ImageAttachment {
    public let data: Data
    public let fileExtension: String
    public let name: String
    public init(data: Data, fileExtension: String, name: String) {
        self.data = data; self.fileExtension = fileExtension.lowercased(); self.name = name
    }
}

public enum AttachmentStore {
    public static let maximumBytes = 20_000_000
    public static let extensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp"]

    public enum Failure: LocalizedError {
        case saveFirst, invalidFolder, unsupportedImage, tooLarge
        public var errorDescription: String? {
            switch self {
            case .saveFirst: return L10n.text(.imageSaveFirst)
            case .invalidFolder: return L10n.text(.imageFolderError)
            case .unsupportedImage: return L10n.text(.imageTypeError)
            case .tooLarge: return L10n.text(.imageSizeError)
            }
        }
    }

    /// Copies rather than moves; a failed batch removes only files created by this call.
    public static func store(_ images: [ImageAttachment], beside document: URL?) throws -> [String] {
        guard let document, document.isFileURL else { throw Failure.saveFirst }
        guard !images.isEmpty else { return [] }
        for image in images {
            guard extensions.contains(image.fileExtension), !image.data.isEmpty else { throw Failure.unsupportedImage }
            guard image.data.count <= maximumBytes else { throw Failure.tooLarge }
        }
        let root = document.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        let directory = root.appendingPathComponent("assets", isDirectory: true)
        guard directory.resolvingSymlinksInPath().path.hasPrefix(root.path + "/") else { throw Failure.invalidFolder }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var created: [URL] = []
        do {
            return try images.map { image in
                let filename = "image-\(UUID().uuidString.lowercased()).\(image.fileExtension)"
                let destination = directory.appendingPathComponent(filename)
                try image.data.write(to: destination, options: .withoutOverwriting)
                created.append(destination)
                let label = image.name.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
                    .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
                return "![\(label)](assets/\(filename))"
            }
        } catch {
            for url in created { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }
}
