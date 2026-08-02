import Foundation
import Testing
@testable import ConnorGraphAppSupport

struct InteractiveWebPlatformTests {
    @Test func validatesChoiceBatch() throws {
        let request = InteractiveWebChoiceRequest(choiceRequestID: "cr", accountID: "account", conversationID: "conversation", contextRevision: 1, selectors: [
            .init(id: "access", prompt: "访问方式", mode: .single, options: [.init(id: "public", label: "公开")])
        ])
        try InteractiveWebChoiceValidator.validate(.init(choiceRequestID: "cr", selections: [.init(selectorID: "access", optionIDs: ["public"])]), for: request)
        #expect(throws: InteractiveWebChoiceError.self) { try InteractiveWebChoiceValidator.validate(.init(choiceRequestID: "cr", selections: []), for: request) }
    }

    @Test func packagesStaticFilesDeterministically() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        try Data("<h1>Hello</h1>".utf8).write(to: root.appendingPathComponent("index.html")); try Data("body{}".utf8).write(to: root.appendingPathComponent("style.css"))
        let manifest = try InteractiveWebPackager().package(rootURL: root)
        #expect(manifest.files.map(\.path) == ["index.html", "style.css"])
    }
}
