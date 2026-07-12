import Foundation
import ConnorGraphCore

public enum AttachmentImageExportError: Error, LocalizedError, Equatable {
    case notImage
    case sourceUnavailable
    case sourceIsNotRegularFile
    case destinationAlreadyExists

    public var errorDescription: String? {
        switch self {
        case .notImage:
            return "当前附件不是图片，无法下载。"
        case .sourceUnavailable:
            return "图片原件不存在或已不可用。"
        case .sourceIsNotRegularFile:
            return "图片原件不是可导出的普通文件。"
        case .destinationAlreadyExists:
            return "目标位置已存在同名文件。"
        }
    }
}

public struct AttachmentImageExportService {
    public var fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func canExport(_ model: AttachmentPreviewModel) -> Bool {
        guard model.attachment.kind == .image, let sourceURL = model.sourceFileURL else { return false }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else { return false }
        return !isDirectory.boolValue
    }

    public func defaultFilename(for model: AttachmentPreviewModel) -> String? {
        guard model.attachment.kind == .image, let sourceURL = model.sourceFileURL else { return nil }
        let displayName = AppSessionAttachmentStore.sanitizedFilename(model.attachment.displayName)
        guard !displayName.isEmpty else { return sourceURL.lastPathComponent }
        if URL(fileURLWithPath: displayName).pathExtension.isEmpty, !sourceURL.pathExtension.isEmpty {
            return "\(displayName).\(sourceURL.pathExtension.lowercased())"
        }
        return displayName
    }

    public func export(model: AttachmentPreviewModel, to destinationURL: URL) throws {
        guard model.attachment.kind == .image else {
            throw AttachmentImageExportError.notImage
        }
        guard let sourceURL = model.sourceFileURL, fileManager.fileExists(atPath: sourceURL.path) else {
            throw AttachmentImageExportError.sourceUnavailable
        }
        let resourceValues = try sourceURL.resourceValues(forKeys: [.isRegularFileKey])
        guard resourceValues.isRegularFile == true else {
            throw AttachmentImageExportError.sourceIsNotRegularFile
        }
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw AttachmentImageExportError.destinationAlreadyExists
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }
}
