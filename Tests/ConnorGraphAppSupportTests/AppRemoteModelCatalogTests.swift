import Foundation
import Testing
@testable import ConnorGraphAppSupport

private let fixture = Data(#"{"schema_version":1,"revision":"test","refresh_after_seconds":21600,"providers":[{"id":"openai","default_model":"current","models":["current","new-model"]}]}"#.utf8)
private let catalogURL = URL(string: "https://connor-agent.connor.run/api/v1/model-catalog")!

@Test func remoteCatalogValidationRejectsUnsupportedAndInvalidDefaults() throws {
    let valid = try RemoteModelCatalogDocument.parse(fixture)
    #expect(valid.providers[0].models.contains("new-model"))
    let text = String(decoding: fixture, as: UTF8.self)
    for invalid in [text.replacingOccurrences(of: "\"schema_version\":1", with: "\"schema_version\":2"), text.replacingOccurrences(of: "\"default_model\":\"current\"", with: "\"default_model\":\"missing\"")] {
        #expect(throws: (any Error).self) { try RemoteModelCatalogDocument.parse(Data(invalid.utf8)) }
    }
}

@Test @MainActor func remoteCatalogRetainsLastGoodCacheAndHandles304() async throws {
    let name = "catalog-tests-" + UUID().uuidString
    let preferences = try #require(UserDefaults(suiteName: name))
    defer { preferences.removePersistentDomain(forName: name) }
    let store = AppRemoteModelCatalog(preferences: preferences)
    await store.refreshIfNeeded(force: true) { request in
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        return (fixture, HTTPURLResponse(url: catalogURL, statusCode: 200, httpVersion: nil, headerFields: ["ETag": "\"test\""])!)
    }
    #expect(store.provider("openai-eu")?.models == ["current", "new-model"])
    await store.refreshIfNeeded(force: true) { _ in
        (Data("invalid".utf8), HTTPURLResponse(url: catalogURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    #expect(store.document?.revision == "test")
    let reopened = AppRemoteModelCatalog(preferences: preferences)
    #expect(reopened.provider("openai")?.default_model == "current")
    await reopened.refreshIfNeeded(force: true) { request in
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"test\"")
        return (Data(), HTTPURLResponse(url: catalogURL, statusCode: 304, httpVersion: nil, headerFields: nil)!)
    }
    #expect(reopened.document?.revision == "test")
    let rollback = Data(String(decoding: fixture, as: UTF8.self).replacingOccurrences(of: "\"test\"", with: "\"previous\"").utf8)
    await reopened.refreshIfNeeded(force: true) { _ in
        (rollback, HTTPURLResponse(url: catalogURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    #expect(reopened.document?.revision == "previous")
}

@Test @MainActor func remoteCatalogFiltersUnknownClientCapabilities() throws {
    let name = "catalog-capability-tests-" + UUID().uuidString
    let preferences = try #require(UserDefaults(suiteName: name))
    defer { preferences.removePersistentDomain(forName: name) }
    let guarded = Data(#"{"schema_version":1,"revision":"guarded","refresh_after_seconds":21600,"providers":[{"id":"openai","default_model":"future-model","models":["current","future-model"],"model_requirements":{"future-model":["future_adapter_v9"]}}]}"#.utf8)
    preferences.set(guarded, forKey: "official-model-catalog-v1")
    let store = AppRemoteModelCatalog(preferences: preferences)
    #expect(store.provider("openai")?.models == ["current"])
    #expect(store.provider("openai")?.default_model == "current")
}
