import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Browser Task Checkpoints")
struct BrowserTaskStoreTests {
    private func fixture() throws -> Data { try Data(contentsOf:URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/browser-task-v1.json")) }
    private func directory() throws -> URL { let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);return url }
    @Test func portableFixtureKeepsSourcesAndExcludesLocalIdentity() throws {
        let task=try BrowserTaskCheckpoint.decode(fixture());#expect(task.title=="比较供应商");#expect(task.sources.count==2)
        #expect(try BrowserTaskCheckpoint.decode(Data([0xef,0xbb,0xbf])+fixture()).id==task.id)
        let wire=try task.encode();#expect(try BrowserTaskCheckpoint.decode(wire)==task)
        let text=String(decoding:wire,as:UTF8.self);#expect(!text.contains("ownerSessionId"));#expect(!text.contains("nodeRef"))
    }
    @Test func continuationCarriesOnlyRelatedProgress() throws {
        let task=try BrowserTaskCheckpoint.decode(fixture());let context=try task.resumeContext(currentURLs:["https://example.com/a"])
        #expect(context.contains("不可信历史快照"));#expect(context.contains("请确认交期"));#expect(context.contains("100 元"));#expect(!context.contains("报价 120 元，交期待确认"))
        #expect(try task.resumeContext(currentURLs:["https://unrelated.example/"]).isEmpty)
    }
    @Test func restartSearchAndTransferKeepIndependentCopies() throws {
        let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
        let store=BrowserTaskStore(root:root);let task=try store.importTask(session:"a",data:fixture())
        #expect(task.id != (try BrowserTaskCheckpoint.decode(fixture())).id)
        let restarted=BrowserTaskStore(root:root);#expect(try restarted.search(session:"a",query:"交期").count==1);#expect(try restarted.search(session:"a",query:"120").count==1);#expect(try restarted.search(session:"b").isEmpty)
        let imported=try restarted.importTask(session:"b",data:task.encode());#expect(imported.id != task.id);#expect(imported.draft==task.draft)
    }
    @Test func staleAndForeignUpdatesCannotOverwrite() throws {
        let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
        let store=BrowserTaskStore(root:root);let task=try store.importTask(session:"a",data:fixture());var changed=task;changed.draft="新草稿";let current=try store.save(session:"a",task:changed)
        #expect(throws:(any Error).self){try store.save(session:"a",task:task)};#expect(throws:(any Error).self){try store.delete(session:"a",task:task)};#expect(throws:(any Error).self){try store.save(session:"b",task:current)}
        try store.delete(session:"a",task:current);#expect(throws:(any Error).self){try store.save(session:"a",task:current)}
    }
    @Test func invalidFilesDoNotCreateRecords() throws {
        let parent=try directory();defer{try? FileManager.default.removeItem(at:parent)};let root=parent.appendingPathComponent("tasks");let store=BrowserTaskStore(root:root)
        for kind in ["version","url","extra","path","oversize"] {
            var object=try #require(JSONSerialization.jsonObject(with:fixture()) as? [String:Any])
            switch kind {case "version":object["version"]=2;case "url":var sources=try #require(object["sources"] as? [[String:Any]]);sources[0]["url"]="javascript:alert(1)";object["sources"]=sources;case "extra":object["commands"]=["submit"];case "path":object["id"]="../../data";default:object["answer"]=String(repeating:"x",count:BrowserTaskStore.maxBytes)}
            let data=try JSONSerialization.data(withJSONObject:object);#expect(throws:(any Error).self){try store.importTask(session:"a",data:data)};#expect(!FileManager.default.fileExists(atPath:root.path))
        }
    }
    @Test func interruptedPreparationAndCorruptionAreExplicit() throws {
        let root=try directory();defer{try? FileManager.default.removeItem(at:root)};let store=BrowserTaskStore(root:root);var prepared=try BrowserTaskCheckpoint.decode(fixture());prepared.state="prepared";let task=try store.importTask(session:"a",data:prepared.encode());#expect(task.state=="interrupted")
        let file=root.appendingPathComponent(task.id+".json");try Data("{broken".utf8).write(to:file);#expect(throws:(any Error).self){try store.search(session:"a")};#expect(throws:(any Error).self){try store.save(session:"a",task:task)};#expect(try String(contentsOf:file,encoding:.utf8)=="{broken")
    }
}
