import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Phase G Craft-grade Native UI Tests")
struct PhaseGCraftGradeNativeUITests {
    @Test func nativeShellBuildsCraftGradeSidebarGroupsAndCommands() {
        let shell = ConnorNativeShellPresentation.default

        #expect(shell.title == "Connor")
        #expect(shell.defaultSelection == .runtimeCenter)
        #expect(shell.sidebarGroups.map(\.title) == ["Run", "Memory", "Governance", "System"])
        #expect(shell.sidebarGroups.flatMap(\.items).map(\.id).prefix(5) == [
            ConnorNativeShellItem.runtimeCenter,
            .agentChat,
            .browserWorkspace,
            .graphMemory,
            .search
        ])
        #expect(shell.sidebarGroups.flatMap(\.items).allSatisfy { !$0.title.isEmpty && !$0.systemImage.isEmpty })
        #expect(shell.commands.map(\.id) == [
            .newSession,
            .toggleBrowser,
            .openRuntimeCenter,
            .openGraphMemoryReview,
            .openApprovals,
            .openSettings
        ])
        #expect(shell.commands.first?.keyboardShortcut == "⌘N")
        #expect(shell.commands[2].target == .runtimeCenter)
    }

    @Test func nativeShellFindsItemsByIdentifierForDeepLinks() {
        let shell = ConnorNativeShellPresentation.default

        #expect(shell.item(for: .graphMemory)?.title == "Graph Memory")
        #expect(shell.item(for: .automation)?.badgeStyle == .warning)
        #expect(shell.command(for: .openSettings)?.target == .settings)
    }
}
