import Testing
@testable import ConnorGraphAgentMac

@Test func sidebarItemsDoNotExposeMemoryOSAsUserVisibleRoute() {
    #expect(!SidebarItem.allCases.map(\.rawValue).contains("Memory OS"))
}

@MainActor
@Test func graphMemoryNavigationFallsBackToAgentChat() {
    let model = AppShellFeatureModel()

    model.applyNavigation(.graphMemory)

    #expect(model.selection == .agentChat)
}
