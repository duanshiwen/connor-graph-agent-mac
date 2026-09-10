import XCTest
import ConnorGraphCore
@testable import ConnorGraphAgent

/// M7 双面硬切：base.* 小程序操作免用户审批——六个 base 能力在任何权限模式下都
/// 静默放行（approved），不进审批队列、不弹人工确认；唯一边界是工具面
/// （authoring/runtime 硬门禁在 BaseAgentTool.execute() 内）。
/// basePublish（发布/公开动作）是 R7 硬门禁例外：任何模式都不静默放行。
final class BasePermissionPolicyTests: XCTestCase {
    private func outcome(_ mode: AgentPermissionMode, _ capability: AgentPermissionCapability) async -> AgentPermissionOutcome {
        let engine = AgentPolicyEngine(permissionMode: mode)
        let decision = await engine.evaluate(capability: capability, runID: "run", sessionID: "session")
        return decision.outcome
    }

    /// 六个 base 能力（覆盖全部 base.* 工具执行）在四种权限模式下全部免审批静默放行。
    func testBaseCapabilitiesAlwaysApprovedInEveryMode() async {
        let baseCapabilities: [AgentPermissionCapability] = [
            .baseRead, .baseWrite, .baseManageSchema, .baseManageMethods, .baseManageApps, .baseExecute
        ]
        XCTAssertEqual(Set(baseCapabilities), AgentPolicyEngine.baseSurfaceCapabilities)
        for mode in AgentPermissionMode.allCases {
            for capability in baseCapabilities {
                let o = await outcome(mode, capability)
                XCTAssertEqual(o, .approved, "\(mode.rawValue) 下 \(capability.rawValue) 应免审批静默放行")
            }
        }
    }

    /// basePublish 是 R7 硬门禁例外：不属 M7 免审批面。
    /// readOnly 下 denied；askToWrite 下需审批；trustedWrite/allowAll 下仍需人工确认。
    func testBasePublishRemainsHardGate() async {
        let readOnly = await outcome(.readOnly, .basePublish)
        XCTAssertEqual(readOnly, .denied)
        let ask = await outcome(.askToWrite, .basePublish)
        XCTAssertEqual(ask, .needsApproval)
        let trusted = await outcome(.trustedWrite, .basePublish)
        XCTAssertEqual(trusted, .needsApproval)
        let allowAll = await outcome(.allowAll, .basePublish)
        XCTAssertEqual(allowAll, .needsApproval)
    }

    /// 免审批不影响非 base 能力的既有口径（抽查只读/浏览器/邮件）。
    func testNonBaseCapabilitiesUnchanged() async {
        let readGraph = await outcome(.readOnly, .readGraph)
        XCTAssertEqual(readGraph, .approved)
        let navigate = await outcome(.readOnly, .navigateBrowser)
        XCTAssertEqual(navigate, .denied)
        let interact = await outcome(.askToWrite, .interactBrowser)
        XCTAssertEqual(interact, .needsApproval)
        let sendMail = await outcome(.trustedWrite, .sendMail)
        XCTAssertEqual(sendMail, .approved)
    }

    /// 免审批口径下 base 工具在工具发现（definitions(availableUnder:)）中任何模式都可见
    /// （discoveryOutcome != denied）。
    func testBaseToolsAlwaysDiscoverable() async {
        for mode in AgentPermissionMode.allCases {
            let engine = AgentPolicyEngine(permissionMode: mode)
            for capability in AgentPolicyEngine.baseSurfaceCapabilities {
                let outcome = await engine.discoveryOutcome(for: capability)
                XCTAssertNotEqual(outcome, .denied, "\(mode.rawValue) 下 \(capability.rawValue) 不应被发现面拒绝")
            }
        }
    }
}
