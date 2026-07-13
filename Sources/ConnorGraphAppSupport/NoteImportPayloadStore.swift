import Foundation
import CryptoKit
import ConnorGraphCore

public enum NoteImportPayloadStoreError: Error, Equatable {
    case invalidReference(String)
    case hashMismatch(String)
}

/// File-backed staging for full imported-note payloads.
///
/// The import ledger retains only a relative reference and SHA-256 digest,
/// avoiding base64 expansion and large metadata_json writes in the graph DB.
public struct NoteImportPayloadStore: Sendable {
    public static let referenceMetadataKey = "imported_note_payload_ref"
    public static let hashMetadataKey = "imported_note_payload_sha256"

    public let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory.standardizedFileURL
    }

    public func save(_ note: ImportedNote, jobID: String, itemID: String) throws -> [String: String] {
        let directory = rootDirectory.appendingPathComponent(jobID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(note)
        let relativePath = "\(jobID)/\(itemID).json"
        let destination = rootDirectory.appendingPathComponent(relativePath)
        try data.write(to: destination, options: [.atomic])
        return [
            Self.referenceMetadataKey: relativePath,
            Self.hashMetadataKey: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        ]
    }

    public func load(metadata: [String: String]) throws -> ImportedNote? {
        guard let reference = metadata[Self.referenceMetadataKey] else { return nil }
        guard !reference.hasPrefix("/"), !reference.split(separator: "/").contains("..") else {
            throw NoteImportPayloadStoreError.invalidReference(reference)
        }
        let url = rootDirectory.appendingPathComponent(reference).standardizedFileURL
        guard url.path.hasPrefix(rootDirectory.path + "/") else {
            throw NoteImportPayloadStoreError.invalidReference(reference)
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        if let expected = metadata[Self.hashMetadataKey] {
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else { throw NoteImportPayloadStoreError.hashMismatch(reference) }
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ImportedNote.self, from: data)
    }

    public func removeJob(jobID: String) throws {
        let directory = rootDirectory.appendingPathComponent(jobID, isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}
