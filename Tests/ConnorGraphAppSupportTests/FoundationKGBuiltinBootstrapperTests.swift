import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphStore

private func temporaryFoundationKGURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(name)
}

@Test func foundationKGBuiltinBootstrapperCopiesSeedWhenMemoryDatabaseIsMissing() throws {
    let source = temporaryFoundationKGURL("foundation-source-\(UUID().uuidString).sqlite")
    let destination = temporaryFoundationKGURL("foundation-destination-\(UUID().uuidString).sqlite")
    let sourceStore = try SQLiteMemoryOSStore(path: source.path)
    try sourceStore.migrate()
    try sourceStore.saveBuiltinDataset(id: FoundationKGMemoryOSMapper.builtinDatasetID, kind: "foundation_kg", version: FoundationKGMemoryOSMapper.sourceVersion)

    let copied = try FoundationKGBuiltinBootstrapper.ensureBuiltinDatabaseIfNeeded(memoryOSDatabaseURL: destination, builtinDatabaseURL: source)

    #expect(copied)
    #expect(FileManager.default.fileExists(atPath: destination.path))
    let destinationStore = try SQLiteMemoryOSStore(path: destination.path)
    let dataset = try destinationStore.builtinDataset(id: FoundationKGMemoryOSMapper.builtinDatasetID)
    #expect(dataset?["version"] == FoundationKGMemoryOSMapper.sourceVersion)
}

@Test func foundationKGBuiltinBootstrapperDoesNotOverwriteExistingMemoryDatabase() throws {
    let source = temporaryFoundationKGURL("foundation-source-\(UUID().uuidString).sqlite")
    let destination = temporaryFoundationKGURL("foundation-destination-\(UUID().uuidString).sqlite")
    let sourceStore = try SQLiteMemoryOSStore(path: source.path)
    try sourceStore.migrate()
    try sourceStore.saveBuiltinDataset(id: FoundationKGMemoryOSMapper.builtinDatasetID, kind: "foundation_kg", version: "source")
    let destinationStore = try SQLiteMemoryOSStore(path: destination.path)
    try destinationStore.migrate()
    try destinationStore.saveBuiltinDataset(id: FoundationKGMemoryOSMapper.builtinDatasetID, kind: "foundation_kg", version: "existing")

    let copied = try FoundationKGBuiltinBootstrapper.ensureBuiltinDatabaseIfNeeded(memoryOSDatabaseURL: destination, builtinDatabaseURL: source)

    #expect(!copied)
    let reopened = try SQLiteMemoryOSStore(path: destination.path)
    let dataset = try reopened.builtinDataset(id: FoundationKGMemoryOSMapper.builtinDatasetID)
    #expect(dataset?["version"] == "existing")
}
