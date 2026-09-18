import AppKit
import ImageIO
import MarknoteCore

@MainActor enum ImageImport {
    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    static func canRead(_ pasteboard: NSPasteboard) -> Bool {
        let urls = fileURLs(from: pasteboard)
        if !urls.isEmpty { return urls.allSatisfy { AttachmentStore.extensions.contains($0.pathExtension.lowercased()) } }
        return pasteboard.availableType(from: [.png, .tiff]) != nil
    }

    static func read(files: [URL]) throws -> [ImageAttachment] {
        try files.map { url in
            guard url.isFileURL, AttachmentStore.extensions.contains(url.pathExtension.lowercased()) else { throw AttachmentStore.Failure.unsupportedImage }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { throw AttachmentStore.Failure.unsupportedImage }
            guard (values.fileSize ?? Int.max) <= AttachmentStore.maximumBytes else { throw AttachmentStore.Failure.tooLarge }
            let data = try Data(contentsOf: url)
            try validate(data)
            return ImageAttachment(data: data, fileExtension: url.pathExtension, name: url.deletingPathExtension().lastPathComponent)
        }
    }

    static func read(_ pasteboard: NSPasteboard) throws -> [ImageAttachment] {
        let files = fileURLs(from: pasteboard)
        if !files.isEmpty { return try read(files: files) }
        if let png = pasteboard.data(forType: .png) {
            try validate(png)
            return [ImageAttachment(data: png, fileExtension: "png", name: L10n.text(.image))]
        }
        if let tiff = pasteboard.data(forType: .tiff) {
            try validate(tiff)
            guard let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { throw AttachmentStore.Failure.unsupportedImage }
            guard png.count <= AttachmentStore.maximumBytes else { throw AttachmentStore.Failure.tooLarge }
            return [ImageAttachment(data: png, fileExtension: "png", name: L10n.text(.image))]
        }
        return []
    }

    private static func validate(_ data: Data) throws {
        guard data.count <= AttachmentStore.maximumBytes else { throw AttachmentStore.Failure.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = info[kCGImagePropertyPixelWidth] as? Int,
              let height = info[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0,
              width <= 40_000_000 / height else { throw AttachmentStore.Failure.unsupportedImage }
    }
}
