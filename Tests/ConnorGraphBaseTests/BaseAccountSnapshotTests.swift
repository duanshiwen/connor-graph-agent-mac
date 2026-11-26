import Foundation
import XCTest
@testable import ConnorGraphBase

final class BaseAccountSnapshotTests:XCTestCase {
    func testApplyPreservesKeysVersionsAndRecordsAndRejectsConcurrentEdits() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let a = try BaseLibraryStore(directory:root.appendingPathComponent("a"));defer{a.close()}
        let b = try BaseLibraryStore(directory:root.appendingPathComponent("b"));defer{b.close()}
        _ = try a.createApp(manifest:["appID":"demo","name":"示例"],schemaObject:["tables":[["name":"entries","fields":[["name":"body","type":"text"],["name":"done","type":"boolean"]]]]],guide:["authoring":["summary":"制作"],"usage":["summary":"使用"]])
        let rows = try a.openStore(appID:"demo");defer{rows.close()}
        try rows.insert(id:"rec_7",table:"entries",values:["body":.string("中文😀"),"done":.bool(true)],meta:["version":1])
        let key = try a.syncAppKey(appID:"demo")
        let first = try XCTUnwrap(a.accountSnapshots(account:"owner")["demo"])
        try b.applyAccountSnapshot(first,account:"owner",expectedFingerprint:nil)
        XCTAssertEqual(try b.syncKeyPayload(kind:"app",appID:"demo"),key)
        XCTAssertEqual(try BaseLibraryStore.snapshotFingerprint(first),try BaseLibraryStore.snapshotFingerprint(b.accountSnapshot(appID:"demo")))
        let before = try BaseLibraryStore.snapshotFingerprint(b.accountSnapshot(appID:"demo"))
        let target = try b.openStore(appID:"demo");defer{target.close()}
        try target.insert(id:"rec_8",table:"entries",values:["body":.string("离线修改")],meta:[:])
        XCTAssertThrowsError(try b.applyAccountSnapshot(first,account:"owner",expectedFingerprint:before))
        XCTAssertEqual(try target.rowCount(in:"entries"),2)
        XCTAssertThrowsError(try b.applyAccountSnapshot(first,account:"different-account",expectedFingerprint:nil))
        let current = try BaseLibraryStore.snapshotFingerprint(b.accountSnapshot(appID:"demo"))
        try b.applyAccountSnapshot(first,account:"owner",expectedFingerprint:current)
        let reopened = try b.openStore(appID:"demo");defer{reopened.close()}
        XCTAssertEqual(try reopened.nextRecordID(),"rec_8")
        XCTAssertEqual(try b.exportRecords(appID:"demo").tables.count,1)
        try a.deleteApp(appID:"demo")
        XCTAssertNotNil(try a.pendingAccountDeletions("owner")["demo"])
        try b.applyAccountSnapshot(["format":"connor-base-sync-v1","appID":"demo","deleted":true],account:"owner",expectedFingerprint:try BaseLibraryStore.snapshotFingerprint(b.accountSnapshot(appID:"demo")))
        XCTAssertFalse(try b.appExists("demo"))
    }
    func testTransportChecksMissingAndDamagedParts() throws {
        let bytes = try JSONSerialization.data(withJSONObject:["appID":"chunked","body":String(repeating:"😀",count:160_000)])
        let projection = try BaseAccountTransport.project(appID:"chunked",snapshot:bytes)
        var cache:[String:Data] = [:]
        XCTAssertThrowsError(try BaseAccountTransport.resolve(id:"chunked",payload:projection["chunked"]!,cache:&cache))
        for (id,data) in projection where id != "chunked" {XCTAssertNil(try BaseAccountTransport.resolve(id:id,payload:data,cache:&cache))}
        XCTAssertEqual(try BaseAccountTransport.resolve(id:"chunked",payload:projection["chunked"]!,cache:&cache),bytes)
        cache.removeValue(forKey:try XCTUnwrap(cache.keys.first))
        XCTAssertThrowsError(try BaseAccountTransport.resolve(id:"chunked",payload:projection["chunked"]!,cache:&cache))
    }
    func testRecoveryReplaysIncompleteGenerationAndKeepsWritesAfterCompletedGeneration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let a = try BaseLibraryStore(directory:root.appendingPathComponent("a"));defer{a.close()}
        _ = try a.createApp(manifest:["appID":"demo","name":"示例"],schemaObject:["tables":[["name":"entries","fields":[["name":"body","type":"text"]]]]],guide:["authoring":["summary":"制作"],"usage":["summary":"使用"]])
        let snapshot = try XCTUnwrap(a.accountSnapshots(account:"owner")["demo"])
        let text = String(decoding:try JSONSerialization.data(withJSONObject:snapshot),as:UTF8.self)
        let destination = root.appendingPathComponent("b")
        let b = try BaseLibraryStore(directory:destination)
        try b.registryExecuteVoid("INSERT INTO base_sync_journal VALUES('demo','owner',?1,'incomplete')",parameters:[text]);b.close()
        let recovered = try BaseLibraryStore(directory:destination)
        XCTAssertTrue(try recovered.appExists("demo"))
        let rows = try recovered.openStore(appID:"demo")
        try rows.insert(id:"rec_9",table:"entries",values:["body":.string("提交后继续编辑")],meta:[:]);rows.close()
        let generation = try XCTUnwrap(recovered.registryExecute("SELECT generation FROM base_sync_applied WHERE app_id='demo'").first?["generation"] as? String)
        try recovered.registryExecuteVoid("INSERT INTO base_sync_journal VALUES('demo','owner',?1,?2)",parameters:[text,generation]);recovered.close()
        let reopened = try BaseLibraryStore(directory:destination);defer{reopened.close()}
        let after = try reopened.openStore(appID:"demo");defer{after.close()}
        XCTAssertEqual(try after.rowCount(in:"entries"),1)
        XCTAssertTrue(try reopened.registryExecute("SELECT * FROM base_sync_journal").isEmpty)
    }
}
