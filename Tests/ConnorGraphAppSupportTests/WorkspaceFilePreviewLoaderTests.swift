import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Workspace File Preview Loader")
struct WorkspaceFilePreviewLoaderTests {
    @Test("Classifies common preview renderers")
    func classifiesRenderers() {
        #expect(WorkspaceFilePreviewLoader.renderer(for: URL(fileURLWithPath: "/tmp/index.html")) == .html)
        #expect(WorkspaceFilePreviewLoader.renderer(for: URL(fileURLWithPath: "/tmp/README.md")) == .markdown)
        #expect(WorkspaceFilePreviewLoader.renderer(for: URL(fileURLWithPath: "/tmp/App.swift")) == .monospacedText)
        #expect(WorkspaceFilePreviewLoader.renderer(for: URL(fileURLWithPath: "/tmp/report.pdf")) == .pdf)
        #expect(WorkspaceFilePreviewLoader.renderer(for: URL(fileURLWithPath: "/tmp/photo.png")) == .quickLook)
        #expect(WorkspaceFilePreviewLoader.renderer(for: URL(fileURLWithPath: "/tmp/archive.zip")) == .unsupported)
    }

    @Test("Loads text content and encoding away from presentation")
    func loadsText() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID().uuidString).swift")
        defer { try? FileManager.default.removeItem(at: url) }
        try "let answer = 42".write(to: url, atomically: true, encoding: .utf8)

        let model = await WorkspaceFilePreviewLoader().load(node(for: url, byteCount: 15))

        #expect(model.renderer == .monospacedText)
        #expect(model.body == "let answer = 42")
        #expect(model.encodingName == "utf-8")
        #expect(model.codeHighlightSpans.contains { $0.kind == .keyword })
    }

    @Test("Detects extensionless text and code files")
    func detectsExtensionlessText() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let readme = root.appendingPathComponent("LICENSE")
        let makefile = root.appendingPathComponent("Makefile")
        try "Plain license text".write(to: readme, atomically: true, encoding: .utf8)
        try "build:\n\techo done".write(to: makefile, atomically: true, encoding: .utf8)

        let loader = WorkspaceFilePreviewLoader()
        let plain = await loader.load(node(for: readme, byteCount: 18))
        let code = await loader.load(node(for: makefile, byteCount: 17))

        #expect(plain.renderer == .plainText)
        #expect(code.renderer == .monospacedText)
    }

    @Test("Large text is truncated instead of rejected")
    func truncatesLargeText() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 65, count: 32).write(to: url)

        let model = await WorkspaceFilePreviewLoader(maximumTextByteCount: 8).load(node(for: url, byteCount: 32))

        #expect(model.renderer == .plainText)
        #expect(model.body == "AAAAAAAA")
        #expect(model.loadedByteCount == 8)
        #expect(model.isTruncated == true)
        #expect(model.message?.contains("继续加载") == true)
    }

    private func node(for url: URL, byteCount: Int64) -> WorkspaceFileNode {
        WorkspaceFileNode(
            id: "root:\(url.lastPathComponent)",
            rootID: "root",
            name: url.lastPathComponent,
            relativePath: url.lastPathComponent,
            url: url,
            kind: .file,
            isHidden: false,
            byteCount: byteCount
        )
    }
}
