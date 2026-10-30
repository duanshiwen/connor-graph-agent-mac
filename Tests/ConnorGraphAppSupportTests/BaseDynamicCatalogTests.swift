import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphBase

struct BaseDynamicCatalogTests {
    @Test func runtimeCatalogRefreshesAfterEnteringAndLeavingAuthoring() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let runtime = try BaseToolRuntime(directory: root)
        var registry = AgentToolRegistry()
        registry.registerBaseTools(runtime: runtime)
        await registry.refreshDynamicTools()
        #expect(registry.definitions.count == 4)
        await runtime.enterAuthoring(appID: "test_app")
        await registry.refreshDynamicTools()
        #expect(registry.definition(named: "base.table.create") != nil)
        await runtime.exitAuthoring()
        await registry.refreshDynamicTools()
        #expect(registry.definitions.count == 4)
        await runtime.close()
        try? FileManager.default.removeItem(at: root)
    }
    @Test func formalImportIsPrivateCompleteAndDoesNotOverwriteOrDiscardData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = try BaseLibraryStore(directory: root)
        defer { library.close(); try? FileManager.default.removeItem(at: root) }
        let json = #"{"manifest":{"appID":"test_app","name":"测试","visibility":"public"},"schema":{"tables":[]},"guide":{"authoring":{"summary":"制作"},"usage":{"summary":"使用"}},"methods":[]}"#
        let reviewed = try BasePackageImporter.review(Data(json.utf8))
        #expect(reviewed.contains("private"))
        #expect(try BasePackageImporter.install(reviewed, library: library) == "test_app")
        #expect(throws: Error.self) { try BasePackageImporter.install(reviewed, library: library) }
        #expect(throws: Error.self) { try BasePackageImporter.review(Data(#"{"manifest":{}}"#.utf8)) }
        #expect(throws: Error.self) { try BasePackageImporter.review(Data((String(json.dropLast()) + ",\"data\":{}}").utf8)) }
    }
}
