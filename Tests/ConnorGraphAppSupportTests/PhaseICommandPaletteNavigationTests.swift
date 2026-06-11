import Foundation
import Testing
import ConnorGraphAppSupport

@Suite("Phase I Command Palette Deep-link Navigation Tests")
struct PhaseICommandPaletteNavigationTests {
    @Test func commandPaletteBuildsSearchableEntriesFromShellItemsAndCommands() {
        let palette = ConnorCommandPalettePresentation.build(shell: ConnorNativeShellPresentation.default)

        #expect(palette.entries.contains { $0.id == "command.openRuntimeCenter" && $0.kind == ConnorCommandPaletteEntryKind.command })
        #expect(palette.entries.contains { $0.id == "item.sources" && $0.kind == ConnorCommandPaletteEntryKind.destination })
        #expect(palette.entries.contains { $0.id == "item.skills" && $0.kind == ConnorCommandPaletteEntryKind.destination })
        #expect(palette.entries.contains { $0.id == "item.automation" && $0.kind == ConnorCommandPaletteEntryKind.destination })
        #expect(palette.search("source").map(\.target).contains(ConnorNativeShellItem.sources))
        #expect(palette.search("⌘1").first?.target == ConnorNativeShellItem.runtimeCenter)
        #expect(palette.search("approval").contains { $0.target == ConnorNativeShellItem.approvals })
    }

    @Test func shellCommandsIncludeRuntimeSystemDestinationsForNativeMenuBinding() {
        let commands = ConnorNativeShellPresentation.default.commands
        let sources = commands.first { $0.id == ConnorNativeShellCommandID.openSources }
        let skills = commands.first { $0.id == ConnorNativeShellCommandID.openSkills }
        let automation = commands.first { $0.id == ConnorNativeShellCommandID.openAutomation }

        #expect(sources?.target == ConnorNativeShellItem.sources)
        #expect(sources?.keyboardShortcut == "⌘4")
        #expect(skills?.target == ConnorNativeShellItem.skills)
        #expect(skills?.keyboardShortcut == "⌘5")
        #expect(automation?.target == ConnorNativeShellItem.automation)
        #expect(automation?.keyboardShortcut == "⌘6")
    }
}
