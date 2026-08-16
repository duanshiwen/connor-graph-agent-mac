import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor
@Suite("Attachment library picker model")
struct AttachmentLibraryPickerModelTests {
    private func makeModel(pageSize: Int = 2) throws -> (paths: AppStoragePaths, model: AttachmentLibraryPickerModel) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-library-picker-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let store = FileArtifactStore(paths: paths)
        let model = AttachmentLibraryPickerModel(store: store, allowsMultipleSelection: true, pageSize: pageSize)
        return (paths, model)
    }

    private func register(_ paths: AppStoragePaths, name: String, data: Data, source: FileArtifactSource = .session) throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-picker-src-\(UUID().uuidString)-\(name)")
        try data.write(to: url)
        _ = try FileArtifactStore(paths: paths).register(from: url, filename: name, source: source)
    }

    @Test func loadsPagesAndSelectsMultiple() async throws {
        let (paths, model) = try makeModel(pageSize: 2)
        try register(paths, name: "a.txt", data: Data("a".utf8))
        try register(paths, name: "b.txt", data: Data("b".utf8))
        try register(paths, name: "c.pdf", data: Data("%PDF-1.4 fake".utf8))

        model.reload()
        #expect(model.items.count == 2)
        #expect(model.total == 3)
        #expect(model.hasMore)
        #expect(model.items.first?.originalName == "c.pdf")  // 最近使用优先

        model.loadMoreIfNeeded(current: model.items.last!)
        #expect(model.items.count == 3)
        #expect(!model.hasMore)

        model.toggle(model.items[0])
        model.toggle(model.items[1])
        #expect(model.selectedIDs.count == 2)
        #expect(model.localURL(for: model.items[0]).path.contains("files"))
    }

    @Test func sendingRegistersFileIntoLibrary() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-library-reg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-reg-src-\(UUID().uuidString).txt")
        try "发送的附件内容".write(to: source, atomically: true, encoding: .utf8)

        AttachmentLibraryRegistration.register(urls: [source], paths: paths)

        let recent = FileArtifactStore(paths: paths).recent(limit: 10)
        #expect(recent.map(\.originalName).contains(source.lastPathComponent))
    }

    @Test func filtersByKind() async throws {
        let (paths, model) = try makeModel(pageSize: 10)
        try register(paths, name: "photo.png", data: Data("png".utf8))
        try register(paths, name: "report.pdf", data: Data("%PDF-1.4 fake".utf8))
        try register(paths, name: "note.md", data: Data("# 笔记".utf8))

        model.kindFilter = .pdf
        model.reload()
        #expect(model.total == 1)
        #expect(model.items.first?.originalName == "report.pdf")

        model.kindFilter = .image
        model.reload()
        #expect(model.total == 1)
        #expect(model.items.first?.originalName == "photo.png")
    }
}
