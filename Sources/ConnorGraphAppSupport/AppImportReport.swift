import Foundation
import ConnorGraphImport

public struct AppImportWarning: Sendable, Equatable, Identifiable {
    public var id: String { "\(path):\(message)" }
    public var path: String
    public var message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

public struct AppImportReport: Sendable, Equatable {
    public var scannedFiles: Int
    public var importedNodes: Int
    public var importedEdges: Int
    public var skippedFiles: Int
    public var warnings: [AppImportWarning]

    public init(
        scannedFiles: Int,
        importedNodes: Int,
        importedEdges: Int,
        skippedFiles: Int,
        warnings: [AppImportWarning]
    ) {
        self.scannedFiles = scannedFiles
        self.importedNodes = importedNodes
        self.importedEdges = importedEdges
        self.skippedFiles = skippedFiles
        self.warnings = warnings
    }

    public init(_ report: LegacyDirectoryImportReport) {
        self.init(
            scannedFiles: report.scannedFiles,
            importedNodes: report.importedNodes,
            importedEdges: report.importedEdges,
            skippedFiles: report.skippedFiles,
            warnings: report.warnings.map { AppImportWarning(path: $0.path, message: $0.message) }
        )
    }
}
