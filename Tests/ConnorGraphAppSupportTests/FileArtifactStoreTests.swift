import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("File Artifact Store Tests")
struct FileArtifactStoreTests {
    private func makeStore() throws -> (paths: AppStoragePaths, store: FileArtifactStore) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-file-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        return (paths, FileArtifactStore(paths: paths))
    }

    private func writeSource(name: String, data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-file-store-src-\(UUID().uuidString)-\(name)")
        try data.write(to: url)
        return url
    }

    @Test func registerStoresBytesAndManifest() throws {
        let (_, store) = try makeStore()
        let source = try writeSource(name: "handoff.bin", data: Data([0x00, 0x01, 0x02, 0x03]))
        let record = try store.register(from: source, filename: "handoff.bin", source: .session, summary: "客服交接文件")
        #expect(record.fileID.hasPrefix("file:"))
        #expect(record.originalName == "handoff.bin")
        #expect(record.byteCount == 4)
        #expect(record.extractionStatus == .unreadable)
        #expect(record.summary == "客服交接文件")
        let bytes = try store.readBytes(fileID: record.fileID)
        #expect(bytes == Data([0x00, 0x01, 0x02, 0x03]))
    }

    @Test func sameContentReusesFileID() throws {
        let (_, store) = try makeStore()
        let data = Data("identical content".utf8)
        let a = try store.register(from: try writeSource(name: "a.txt", data: data), filename: "a.txt", source: .session)
        let b = try store.register(from: try writeSource(name: "b.txt", data: data), filename: "b.txt", source: .imported)
        #expect(a.fileID == b.fileID)
        #expect(store.lookup(query: nil, limit: 50).count == 1)
    }

    @Test func changedContentCreatesNewVersion() throws {
        let (_, store) = try makeStore()
        let v1 = try store.register(from: try writeSource(name: "doc.txt", data: Data("version 1".utf8)), filename: "doc.txt")
        let v2 = try store.register(from: try writeSource(name: "doc.txt", data: Data("version 2 - changed".utf8)), filename: "doc.txt")
        #expect(v1.fileID != v2.fileID)
        #expect(store.lookup(query: "doc", limit: 50).count == 2)
    }

    @Test func lookupMatchesNameAndSourceAndSummary() throws {
        let (_, store) = try makeStore()
        _ = try store.register(
            from: try writeSource(name: "service-report.pdf", data: Data("%PDF-1.4 fake".utf8)),
            filename: "service-report.pdf",
            source: .session,
            summary: "客服日报"
        )
        _ = try store.register(
            from: try writeSource(name: "contract.docx", data: Data("contract".utf8)),
            filename: "contract.docx",
            source: .imported,
            summary: "合同"
        )
        #expect(store.lookup(query: "service-report", limit: 50).count == 1)
        #expect(store.lookup(query: "客服日报", limit: 50).count == 1)
        #expect(store.lookup(query: "contract", limit: 50).count == 1)
        #expect(store.lookup(query: "nonexistent", limit: 50).isEmpty)
    }

    @Test func oversizedFileIsRejected() throws {
        let (_, store) = try makeStore()
        let small = FileArtifactStore(paths: store.paths, maxRegistrationBytes: 10, maxTotalBytes: 1_000)
        let source = try writeSource(name: "big.bin", data: Data(repeating: 0xAB, count: 64))
        #expect(throws: FileArtifactStoreError.self) {
            _ = try small.register(from: source, filename: "big.bin")
        }
    }

    @Test func deleteRemovesBytesAndManifest() throws {
        let (_, store) = try makeStore()
        let record = try store.register(from: try writeSource(name: "tmp.txt", data: Data("tmp".utf8)), filename: "tmp.txt")
        try store.delete(fileID: record.fileID)
        #expect(store.lookup(query: "tmp", limit: 50).isEmpty)
        #expect(throws: FileArtifactStoreError.self) {
            _ = try store.artifact(fileID: record.fileID)
        }
    }
}
