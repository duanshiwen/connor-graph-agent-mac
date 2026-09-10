import Foundation
import Testing
import ConnorGraphBase
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphAppSupport

/// M4-K3：base.app.grant 工具层封装（shared 态授权/回收 envelope + baseManageApps 门控）。
@Suite struct BaseGrantToolsTests {

    private func makeRuntime() throws -> BaseToolRuntime {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("base-m4-grant-tools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try BaseToolRuntime(directory: dir)
    }

    private func manifest(_ appID: String, visibility: String) -> [String: Any] {
        ["appID": appID, "name": "共享应用", "domain": "test", "purpose": "授权测试",
         "visibility": visibility]
    }

    private func schema() -> [String: Any] {
        ["tables": [["name": "items", "fields": [
            ["name": "amount", "type": "number", "required": true]
        ]]]]
    }

    /// M7 双态硬切：guide 须为 {authoring, usage}（测试夹具与内核同一口径）。
    private func guide(_ appID: String) -> [String: Any] {
        let state: [String: Any] = ["appID": appID, "whenToUse": "记一笔时用",
                                    "whenNotToUse": "闲聊时不用", "sections": []]
        return ["authoring": state, "usage": state]
    }

    private func intValue(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }

    /// shared 应用授权/回收：成功返回新包版本号，授权状态随包提交。
    @Test func grantEnvelopeSharedRoundtrip() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.createAppEnvelope(
            manifest: manifest("shared", visibility: "shared"),
            schema: schema(), guide: guide("shared"), methods: [])

        let env = await runtime.grantAccessEnvelope(appID: "shared", peer: "alice", grant: true)
        #expect(env.ok == true)
        #expect(env.error == nil)
        let data = env.data?.jsonObject as? [String: Any]
        #expect(data?["peer"] as? String == "alice")
        #expect(data?["grant"] as? Bool == true)
        #expect(intValue(data?["packageVersion"]) == 2) // v1 → v2（授权状态变更即新版本记录）

        let revoke = await runtime.grantAccessEnvelope(appID: "shared", peer: "alice", grant: false)
        #expect(revoke.ok == true)
        let revokeData = revoke.data?.jsonObject as? [String: Any]
        #expect(intValue(revokeData?["packageVersion"]) == 3)
        await runtime.close()
    }

    /// private 应用授权 → PERMISSION_DENIED（仅 shared 可授权）。
    @Test func grantEnvelopeRejectsPrivate() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.createAppEnvelope(
            manifest: manifest("priv", visibility: "private"),
            schema: schema(), guide: guide("priv"), methods: [])

        let env = await runtime.grantAccessEnvelope(appID: "priv", peer: "alice", grant: true)
        #expect(env.ok == false)
        #expect(env.error?.code == BaseErrorCode.permissionDenied.rawValue)
        await runtime.close()
    }
}
