import Testing
import ConnorGraphCore

@Test func memoryOSEntityTypeKeepsControlledTypesStable() {
    #expect(MemoryOSEntityType.normalizeRawType("concept") == "concept")
    #expect(MemoryOSEntityType.normalizeRawType("organization") == "organization")
}

@Test func memoryOSEntityTypeNormalizesFormattingVariants() {
    #expect(MemoryOSEntityType.normalizeRawType("Creative Work") == "creative_work")
    #expect(MemoryOSEntityType.normalizeRawType("spatial-object") == "spatial_object")
}

@Test func memoryOSEntityTypeNormalizesCommonAliases() {
    #expect(MemoryOSEntityType.normalizeRawType("university") == "organization")
    #expect(MemoryOSEntityType.normalizeRawType("scientist") == "person")
    #expect(MemoryOSEntityType.normalizeRawType("parameter") == "metric")
}

@Test func memoryOSEntityTypeFallsBackToUnknownForUnsupportedLabels() {
    #expect(MemoryOSEntityType.normalizeRawType("whatever-new-llm-label") == "unknown")
    #expect(MemoryOSEntityType.fromRawType("whatever-new-llm-label") == .unknown)
}
