import XCTest
import ConnorGraphCore
@testable import ConnorGraphAgent

final class BasePermissionPolicyTests: XCTestCase {
    private func outcome(_ mode: AgentPermissionMode, _ capability: AgentPermissionCapability) async -> AgentPermissionOutcome {
        let engine = AgentPolicyEngine(permissionMode: mode)
        let decision = await engine.evaluate(capability: capability, runID: "run", sessionID: "session")
        return decision.outcome
    }

    func testReadOnlyModeBase() async {
        let read = await outcome(.readOnly, .baseRead)
        XCTAssertEqual(read, .approved)
        for c in [AgentPermissionCapability.baseWrite, .baseManageSchema, .baseManageMethods, .baseManageApps, .baseExecute, .basePublish] {
            let o = await outcome(.readOnly, c)
            XCTAssertEqual(o, .denied, "readOnly 下 \(c.rawValue) 应被拒绝")
        }
    }

    func testAskToWriteModeBase() async {
        let read = await outcome(.askToWrite, .baseRead)
        XCTAssertEqual(read, .approved)
        for c in [AgentPermissionCapability.baseWrite, .baseManageSchema, .baseManageMethods, .baseManageApps, .baseExecute, .basePublish] {
            let o = await outcome(.askToWrite, c)
            XCTAssertEqual(o, .needsApproval, "askToWrite 下 \(c.rawValue) 应需审批")
        }
    }

    func testTrustedWriteModeBasePublishStillNeedsApproval() async {
        let read = await outcome(.trustedWrite, .baseRead)
        let write = await outcome(.trustedWrite, .baseWrite)
        let schema = await outcome(.trustedWrite, .baseManageSchema)
        let methods = await outcome(.trustedWrite, .baseManageMethods)
        let apps = await outcome(.trustedWrite, .baseManageApps)
        let execute = await outcome(.trustedWrite, .baseExecute)
        let publish = await outcome(.trustedWrite, .basePublish)
        XCTAssertEqual(read, .approved)
        XCTAssertEqual(write, .approved)
        XCTAssertEqual(schema, .approved)
        XCTAssertEqual(methods, .approved)
        XCTAssertEqual(apps, .approved)
        XCTAssertEqual(execute, .approved)
        // R7 硬门禁：trustedWrite 下发布/公开仍弹审批
        XCTAssertEqual(publish, .needsApproval)
    }

    func testAllowAllModeBasePublishStillNeedsApproval() async {
        let read = await outcome(.allowAll, .baseRead)
        let write = await outcome(.allowAll, .baseWrite)
        let publish = await outcome(.allowAll, .basePublish)
        XCTAssertEqual(read, .approved)
        XCTAssertEqual(write, .approved)
        // R7 硬门禁：allowAll 下发布/公开仍弹审批
        XCTAssertEqual(publish, .needsApproval)
    }
}
