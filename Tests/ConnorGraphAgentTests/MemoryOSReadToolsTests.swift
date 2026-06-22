import Testing
import ConnorGraphAgent
import ConnorGraphCore

@Test func memoryOSReadToolsIncludeEntityTypeInProfile() {
    let text = MemoryOSReadTools().renderEntityProfile(MemoryOSEntity(stableKey: "k", entityType: "concept", name: "Evidence", summary: "Traceable source material"))
    #expect(text.contains("[concept]"))
}
