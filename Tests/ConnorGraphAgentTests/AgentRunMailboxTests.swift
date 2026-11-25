import Foundation
import XCTest
@testable import ConnorGraphAgent

final class AgentRunMailboxTests: XCTestCase {
    private func fixture() throws -> (URL, AgentRunMailbox) {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (directory, try AgentRunMailbox(file: directory.appendingPathComponent("inbox.json")))
    }
    func testInstructionDuringPreparationAndRecoveryKeepsGoal() throws {
        let (directory, inbox) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let first = try inbox.begin(runID: "old", initial: [.init(role: .user, content: "old")], user: .init(role: .user, content: "old"))
        _ = try inbox.complete(first)
        try inbox.prepare(runID: "new", user: .init(role: .user, content: "new goal"))
        XCTAssertTrue(try inbox.submit(.init(text: "constraint"), steer: true))
        try inbox.pause()
        let restored = try AgentRunMailbox(file: directory.appendingPathComponent("inbox.json"))
        var messages = try restored.begin(runID: "new", initial: [], user: .init(role: .user, content: "continue"))
        _ = try restored.apply(to: &messages)
        XCTAssertEqual(messages.map(\.content), ["old", "new goal", "continue", "constraint"])
    }
    func testSteerRetainsContextAndCompletionIsSerialized() throws {
        let (directory, inbox)=try fixture(); defer { try? FileManager.default.removeItem(at:directory) }
        var messages=try inbox.begin(runID:"run",initial:[.init(role:.user,content:"original")],user:.init(role:.user,content:"original"))
        let instruction=AgentRunInstruction(text:"new constraint")
        XCTAssertTrue(try inbox.submit(instruction,steer:true))
        XCTAssertFalse(try inbox.complete(messages))
        XCTAssertEqual(try inbox.apply(to:&messages),[instruction])
        XCTAssertEqual(messages.map(\.content),["original","new constraint"])
        XCTAssertTrue(try inbox.complete(messages))
        XCTAssertFalse(try inbox.submit(.init(text:"late"),steer:true))
        XCTAssertEqual(inbox.queued.map(\.text),["late"])
    }
    func testQueueIsFIFOAndIsolatedFromCurrentContext() throws {
        let (directory,inbox)=try fixture();defer{try? FileManager.default.removeItem(at:directory)}
        var messages=try inbox.begin(runID:"run",initial:[.init(role:.user,content:"original")],user:.init(role:.user,content:"original"))
        let first=AgentRunInstruction(text:"first"),second=AgentRunInstruction(text:"second")
        try inbox.submit(first,steer:false);try inbox.submit(second,steer:false);try inbox.submit(first,steer:false)
        XCTAssertTrue(try inbox.apply(to:&messages).isEmpty);XCTAssertEqual(messages.count,1)
        try inbox.pause()
        let recovered=try AgentRunMailbox(file:directory.appendingPathComponent("inbox.json"))
        XCTAssertTrue(recovered.paused);XCTAssertEqual(recovered.queued,[first,second])
        recovered.prepareClaim(first.id)
        _=try recovered.begin(runID:"run",initial:[],user:.init(role:.user,content:first.text))
        XCTAssertEqual(recovered.queued,[second])
    }
    func testRecoveryKeepsFullToolResultAndProviderEnvelope() throws {
        let (directory,inbox)=try fixture();defer{try? FileManager.default.removeItem(at:directory)}
        var metadata=AgentModelProviderMetadata(providerID:"p");metadata.encryptedContent="opaque envelope"
        let call=AgentToolCall(id:"call",name:"lookup",argumentsJSON:"{}")
        let initial: [AgentModelMessage]=[.init(role:.user,content:"original"),.init(role:.assistant,content:"",toolCalls:[call],providerMetadata:metadata)]
        _=try inbox.begin(runID:"run",initial:initial,user:initial[0])
        var result=AgentToolResult(toolCallID:"call",toolName:"lookup",contentText:String(repeating:"x",count:50_000)+"TAIL")
        result.contentJSON = String(repeating: "z", count: 50_000) + "JSON_TAIL"
        result.modelContentParts = [.imageDataURL("data:image/png;base64,fixture", mimeType: "image/png")]
        try inbox.record(result);try inbox.pause()
        let recovered=try AgentRunMailbox(file:directory.appendingPathComponent("inbox.json"))
        XCTAssertEqual(recovered.recoveryRunID,"run")
        XCTAssertEqual(recovered.result(callID: "call")?.contentJSON, result.contentJSON)
        let context=try recovered.begin(runID:"run",initial:[],user:.init(role:.user,content:"continue"))
        XCTAssertEqual(context.first{$0.role == .tool}?.content,result.contentText)
        XCTAssertEqual(context.first{$0.role == .assistant}?.providerMetadata,metadata)
        XCTAssertTrue(context.contains { $0.contentParts == result.modelContentParts })
    }
    func testPartialAndPendingInstructionSurviveStopAndRestart() throws {
        let (directory,inbox)=try fixture();defer{try? FileManager.default.removeItem(at:directory)}
        _=try inbox.begin(runID:"run",initial:[.init(role:.user,content:"original")],user:.init(role:.user,content:"original"))
        inbox.updatePartial("partial answer");try inbox.submit(.init(text:"change"),steer:true);try inbox.pause()
        let recovered=try AgentRunMailbox(file:directory.appendingPathComponent("inbox.json"))
        var context=try recovered.begin(runID:"run",initial:[],user:.init(role:.user,content:"continue"))
        XCTAssertTrue(context.contains{$0.content == "partial answer"})
        XCTAssertEqual(try recovered.apply(to:&context).map(\.text),["change"])
    }
    func testUnknownWriteResultIsNeverAssumedSuccessful() throws {
        let (directory,inbox)=try fixture();defer{try? FileManager.default.removeItem(at:directory)}
        let call=AgentToolCall(id:"send",name:"mail_send",argumentsJSON:"{}")
        _=try inbox.begin(runID:"run",initial:[.init(role:.assistant,content:"",toolCalls:[call])],user:.init(role:.user,content:"send"))
        try inbox.pause()
        let context=try inbox.begin(runID:"run",initial:[],user:.init(role:.user,content:"continue"))
        XCTAssertTrue(context.first{$0.role == .tool}?.content.contains("不要自动重复写入") == true)
    }
    func testFailedPersistenceNeverAcknowledgesOrEnqueuesInstruction() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:directory)}
        try Data("blocked".utf8).write(to:directory)
        let inbox=try AgentRunMailbox(file:directory.appendingPathComponent("inbox.json"))
        XCTAssertThrowsError(try inbox.submit(.init(text:"must remain unsent"),steer:false))
        XCTAssertTrue(inbox.queued.isEmpty)
    }
}
