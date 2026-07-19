import Foundation
import Testing
@testable import ConnorGraphAgentMac

@Suite("Browser Form Assistant Tests")
struct BrowserFormAssistantTests {
    @Test func classifiesCommentFieldsAndProvidesContextualTasks() {
        let field = makeField(label: "回复评论", placeholder: "写下你的回复")

        let semantic = BrowserFormAssistantClassifier.semantic(for: field)
        let tasks = BrowserFormAssistantClassifier.quickTasks(for: semantic, hasText: false)

        #expect(semantic == .comment)
        #expect(tasks.map(\.title).contains("礼貌回复"))
        #expect(tasks.count == 3)
    }

    @Test func parsesStrictAndFencedCandidateJSON() {
        let response = """
        ```json
        {"candidates":[{"label":"简短","text":"谢谢你的反馈。"},{"label":"友好","text":"感谢分享，我会认真考虑。"}]}
        ```
        """

        let candidates = BrowserFormCandidateParser.parse(response)

        #expect(candidates.count == 2)
        #expect(candidates.first?.label == "简短")
        #expect(candidates.first?.text == "谢谢你的反馈。")
    }

    @Test func fallsBackToPlainTextWhenModelDoesNotReturnJSON() {
        let candidates = BrowserFormCandidateParser.parse("可以直接使用的回复")

        #expect(candidates.count == 1)
        #expect(candidates.first?.text == "可以直接使用的回复")
    }

    @MainActor
    @Test func sitePreferencePersistsByHost() throws {
        let suite = "BrowserFormAssistantTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = BrowserFeatureModel(historyStore: nil, bookmarkStore: nil, nativeSourceSearchBackend: nil, userDefaults: defaults)

        model.setFormAssistantEnabled(false, for: "Example.COM")
        let reloaded = BrowserFeatureModel(historyStore: nil, bookmarkStore: nil, nativeSourceSearchBackend: nil, userDefaults: defaults)

        #expect(!model.isFormAssistantEnabled(for: "example.com"))
        #expect(!reloaded.isFormAssistantEnabled(for: "EXAMPLE.COM"))
        model.shutdown()
        reloaded.shutdown()
    }

    private func makeField(label: String, placeholder: String) -> BrowserEditableFieldPayload {
        BrowserEditableFieldPayload(
            event: .focused,
            pageURL: "https://example.com/article",
            pageTitle: "示例文章",
            token: "field-1",
            tag: "textarea",
            type: "",
            role: "",
            name: "comment",
            label: label,
            placeholder: placeholder,
            ariaLabel: "",
            autocomplete: "",
            maxLength: -1,
            currentValue: "",
            selectedText: "",
            nearbyText: "文章内容",
            formTitle: "评论",
            sectionTitle: "讨论",
            rect: BrowserSelectionRect(x: 10, y: 20, width: 200, height: 40),
            sensitive: false,
            sensitiveReason: ""
        )
    }
}
