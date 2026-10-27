import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Cross-platform session transport")
struct SessionChunksTests {
    private func session(_ body: String) -> ConnorJSONValue {
        .object(["id":.string("large"),"title":.string("笔记"),"kind":.string("note"),"createdAt":.number(1234),"updatedAt":.number(3456),
                 "messages":.array([.object(["id":.string("m"),"role":.string("user"),"createdAt":.number(2345),"content":.string(body)])])])
    }
    @Test func sharedWireFixtureMatchesOtherClients() throws {
        let url = try #require(Bundle.module.url(forResource:"session-chunks-v1",withExtension:"json",subdirectory:"SessionSync"))
        guard case .object(let fixture) = try JSONDecoder().decode(ConnorJSONValue.self,from:Data(contentsOf:url)), case .object(let records) = fixture["records"] else { Issue.record("invalid fixture"); return }
        var parts: [String:ConnorJSONValue] = [:]
        for (id,payload) in records where id != "session-v1" { #expect(try SessionChunks.resolve(id:id,payload:payload,parts:&parts) == nil) }
        let root = try #require(records["session-v1"])
        #expect(try SessionChunks.resolve(id:"session-v1",payload:root,parts:&parts) == fixture["session"])
        #expect(try SessionChunks.semanticHash(#require(fixture["session"])) == SessionChunks.tag(root))
    }
    @Test func largeMessageRestartsAndArrivesOutOfOrder() throws {
        let original = session(String(repeating:"汉😀x/",count:220_000))
        let records = try SessionChunks.project(id:"large",payload:original)
        let root = try #require(records["large"])
        #expect(records.count > 4)
        var parts: [String:ConnorJSONValue] = [:]
        #expect(throws:SessionChunks.Failure.self) { try SessionChunks.resolve(id:"large",payload:root,parts:&parts) }
        let cipher = try AccountSyncPayloadCipher(keyData:Data(repeating:0,count:32))
        for (id,payload) in records where id != "large" {
            #expect(try SessionChunks.resolve(id:id,payload:payload,parts:&parts) == nil)
            #expect(try JSONEncoder().encode(cipher.encrypt(payload,collection:"sessions",recordID:id)).count < 1_048_576)
        }
        parts = try JSONDecoder().decode([String:ConnorJSONValue].self,from:JSONEncoder().encode(parts))
        #expect(try SessionChunks.resolve(id:"large",payload:root,parts:&parts) == SessionChunks.normalize(original))
        #expect(try SessionChunks.semanticHash(original) != SessionChunks.semanticHash(session("edited")))
    }
}
