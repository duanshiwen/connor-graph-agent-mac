import AppKit
import UniformTypeIdentifiers

struct ComposerPasteboardAttachmentExtractor {
    func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) ?? []
        return objects.compactMap { object in
            guard let nsURL = object as? NSURL, let url = nsURL as URL? else { return nil }
            return url.isFileURL ? url : nil
        }
    }

    func imageDataItems(from pasteboard: NSPasteboard) -> [Data] {
        var items: [Data] = []
        for item in pasteboard.pasteboardItems ?? [] {
            if let png = item.data(forType: .png) {
                items.append(png)
                continue
            }
            if let tiff = item.data(forType: .tiff), let png = Self.pngData(fromTIFFData: tiff) {
                items.append(png)
                continue
            }
            if let png = item.data(forType: NSPasteboard.PasteboardType(UTType.png.identifier)) {
                items.append(png)
                continue
            }
            if let tiff = item.data(forType: NSPasteboard.PasteboardType(UTType.tiff.identifier)), let png = Self.pngData(fromTIFFData: tiff) {
                items.append(png)
            }
        }
        if items.isEmpty, let image = NSImage(pasteboard: pasteboard), let png = Self.pngData(from: image) {
            items.append(png)
        }
        return items
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation else { return nil }
        return pngData(fromTIFFData: tiff)
    }

    private static func pngData(fromTIFFData data: Data) -> Data? {
        guard let bitmap = NSBitmapImageRep(data: data) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
