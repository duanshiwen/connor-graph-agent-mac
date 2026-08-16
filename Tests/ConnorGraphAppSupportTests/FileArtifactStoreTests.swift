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

    @Test func libraryListPaginatesFiltersAndOrdersByRecent() throws {
        let (_, store) = try makeStore()
        _ = try store.register(from: try writeSource(name: "photo.png", data: Data("png-bytes".utf8)), filename: "photo.png", source: .session, summary: "最近的照片")
        _ = try store.register(from: try writeSource(name: "report.pdf", data: Data("%PDF-1.4 fake".utf8)), filename: "report.pdf", source: .imported, summary: "季度报告")
        _ = try store.register(from: try writeSource(name: "notes.md", data: Data("# 笔记".utf8)), filename: "notes.md", source: .generated, summary: "会议纪要")
        _ = try store.register(from: try writeSource(name: "clip.mp3", data: Data("mp3-bytes".utf8)), filename: "clip.mp3", source: .forwarded, summary: "语音片段")

        // 分页：每页 2 条，共 2 页
        let page0 = store.list(page: 0, pageSize: 2)
        #expect(page0.items.count == 2)
        #expect(page0.total == 4)
        #expect(page0.hasMore)
        let page1 = store.list(page: 1, pageSize: 2)
        #expect(page1.items.count == 2)
        #expect(!page1.hasMore)

        // 类型筛选：只看 PDF
        let pdfs = store.list(kind: .pdf, pageSize: 50)
        #expect(pdfs.total == 1)
        #expect(pdfs.items.first?.originalName == "report.pdf")

        // 来源筛选
        let generated = store.list(source: .generated, pageSize: 50)
        #expect(generated.total == 1)
        #expect(generated.items.first?.originalName == "notes.md")

        // 关键词筛选
        let matched = store.list(query: "报告", pageSize: 50)
        #expect(matched.total == 1)
        #expect(matched.items.first?.originalName == "report.pdf")

        // 最近使用优先：重新登记 photo.png（同内容复用并刷新 lastSeenAt）后它应排最前
        let newest = store.list(pageSize: 50)
        let namesBefore = newest.items.map { $0.originalName }
        #expect(newest.items.first?.originalName == "clip.mp3")
        _ = try store.register(from: try writeSource(name: "photo.png", data: Data("png-bytes".utf8)), filename: "photo.png", source: .session)
        let namesAfter = store.list(pageSize: 50).items.map { $0.originalName }
        #expect(namesAfter.first == "photo.png")
        #expect(namesAfter == ["photo.png"] + namesBefore.filter { $0 != "photo.png" })
    }
}