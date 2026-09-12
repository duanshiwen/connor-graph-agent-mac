import XCTest
@testable import ConnorGraphAgent
import ConnorGraphCore

/// 控制电脑工具族（macos_*）：键码映射、会话授权存续与 schema 合法性（不注入真实键鼠）。
final class SystemControlAgentToolsTests: XCTestCase {
    func testVirtualKeyCodeMapsNamedKeysLettersDigitsAndFunctions() throws {
        XCTAssertEqual(try SystemControlSupport.virtualKeyCode(for: "command"), 55)
        XCTAssertEqual(try SystemControlSupport.virtualKeyCode(for: "Ctrl"), 59)
        XCTAssertEqual(try SystemControlSupport.virtualKeyCode(for: "enter"), 36)
        XCTAssertEqual(try SystemControlSupport.virtualKeyCode(for: "a"), 0)
        XCTAssertEqual(try SystemControlSupport.virtualKeyCode(for: "c"), 8)
        XCTAssertEqual(try SystemControlSupport.virtualKeyCode(for: "1"), 18)
        XCTAssertEqual(try SystemControlSupport.virtualKeyCode(for: "0"), 29)
        XCTAssertEqual(try SystemControlSupport.virtualKeyCode(for: "f1"), 122)
        XCTAssertThrowsError(try SystemControlSupport.virtualKeyCode(for: " PF5 "))
    }

    func testComputerControlConsentGrantsPerSessionAndRevokes() async {
        let consent = ComputerControlConsent()
        await consent.grant(sessionID: "s1")
        await consent.grant(sessionID: "s2")
        let grantedBefore = await consent.isGranted(sessionID: "s1")
        XCTAssertTrue(grantedBefore)
        await consent.revokeAll()
        let grantedAfter = await consent.isGranted(sessionID: "s1")
        XCTAssertFalse(grantedAfter)
    }

    func testSystemControlToolSchemasAreValid() {
        let tools: [any AgentTool] = [
            MacosScreenshotTool(),
            MacosAXTreeTool(),
            MacosAXActionTool(),
            MacosInputClickTool(),
            MacosInputTypeTool(),
            MacosInputKeyTool(),
            MacosInputScrollTool(),
            MacosInputDragTool(),
        ]
        for tool in tools {
            XCTAssertEqual(tool.inputSchema.validationIssues(toolName: tool.name), [], tool.name)
        }
    }

    func testControlInputToolsRequireControlSystemInputCapability() {
        let tools: [any AgentTool] = [
            MacosAXActionTool(),
            MacosInputClickTool(),
            MacosInputTypeTool(),
            MacosInputKeyTool(),
            MacosInputScrollTool(),
            MacosInputDragTool(),
        ]
        for tool in tools {
            XCTAssertEqual(tool.permission, .controlSystemInput, tool.name)
        }
        XCTAssertEqual(MacosScreenshotTool().permission, .readSystemScreen)
        XCTAssertEqual(MacosAXTreeTool().permission, .readSystemAccessibility)
    }
}
