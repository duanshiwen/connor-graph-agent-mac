import Testing
@testable import ConnorGraphAgentMac
import ConnorGraphCore

@Suite("Person Mention Picker Presentation Tests")
struct PersonMentionPickerPresentationTests {
    @Test func emptyQueryPromptsUserToChoosePerson() {
        let presentation = PersonMentionPickerPresentation(
            query: "",
            profiles: [],
            selectionIndex: 0
        )

        #expect(presentation.title == "选择人物")
        #expect(presentation.subtitle == "输入姓名、别名或联系方式筛选")
        #expect(presentation.emptyTitle == "选择人物")
        #expect(presentation.emptySubtitle == "继续输入姓名、别名或联系方式筛选")
        #expect(presentation.keyboardHint == "↑↓ 选择   Return 确认   Esc 关闭")
    }

    @Test func nonEmptyQueryWithoutResultsShowsHelpfulEmptyState() {
        let presentation = PersonMentionPickerPresentation(
            query: "不存在",
            profiles: [Self.profile(id: "person-a", name: "小王")],
            selectionIndex: 0
        )

        #expect(presentation.title == "选择人物")
        #expect(presentation.subtitle == "搜索“不存在”")
        #expect(presentation.emptyTitle == "没有匹配的人物")
        #expect(presentation.emptySubtitle == "继续输入，或调整姓名、别名、联系方式关键词")
    }

    @Test func resultsSubtitleShowsMatchCountAndClampsSelectionIndex() {
        let presentation = PersonMentionPickerPresentation(
            query: "小",
            profiles: [
                Self.profile(id: "person-a", name: "小王"),
                Self.profile(id: "person-b", name: "小李"),
                Self.profile(id: "person-c", name: "小张")
            ],
            selectionIndex: 99
        )

        #expect(presentation.subtitle == "3 个匹配人物")
        #expect(presentation.clampedSelectionIndex == 2)
        #expect(presentation.rows.count == 3)
    }

    @Test func rowAccessibilityLabelIncludesNameAndSubtitle() throws {
        let presentation = PersonMentionPickerPresentation(
            query: "王",
            profiles: [Self.profile(id: "person-a", name: "王诗闻", email: "shiwen@example.com")],
            selectionIndex: 0
        )

        let row = try #require(presentation.rows.first)
        #expect(row.displayName == "王诗闻")
        #expect(row.subtitle.contains("shiwen@example.com"))
        #expect(row.accessibilityLabel.contains("选择人物"))
        #expect(row.accessibilityLabel.contains("王诗闻"))
        #expect(row.accessibilityLabel.contains("shiwen@example.com"))
    }

    private static func profile(id: String, name: String, email: String? = nil) -> PersonProfile {
        PersonProfile(
            id: ContactID(rawValue: id),
            displayName: name,
            emails: email.map { [ContactEmailAddress(email: $0)] } ?? []
        )
    }
}
