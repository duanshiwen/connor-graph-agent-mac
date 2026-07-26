import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Person Profile Detail Presentation Tests")
struct PersonProfileDetailPresentationTests {
    @Test func detailPresentationShowsAliasesAndMemoryBindingStatus() {
        let profile = PersonProfile(
            id: ContactID(rawValue: "person-wang"),
            displayName: "小王",
            aliases: ["王同学", "Wang"],
            organizationName: "Connor Labs",
            notes: "杭州朋友",
            memoryEntityID: "person:person-profile:person-wang",
            memoryStableKey: "person-profile:person-wang"
        )

        let presentation = PersonProfileDetailPresentation(profile: profile)

        #expect(presentation.aliasesText == "王同学, Wang")
        #expect(presentation.memoryBindingTitle == "已连接 Memory OS")
        #expect(presentation.memoryBindingDetail.contains("person-profile:person-wang"))
        #expect(presentation.memorySummary == "杭州朋友")
    }

    @Test func detailPresentationShowsUnboundMemoryStatusWhenMissingBinding() {
        let profile = PersonProfile(id: ContactID(rawValue: "person-unbound"), displayName: "小李")

        let presentation = PersonProfileDetailPresentation(profile: profile)

        #expect(presentation.aliasesText == "暂无别名")
        #expect(presentation.memoryBindingTitle == "尚未连接 Memory OS")
        #expect(presentation.memorySummary == "暂无人物记忆摘要")
    }

    @Test func detailPresentationIncludesPersonMemoryItemsAndCounts() {
        let profile = PersonProfile(id: ContactID(rawValue: "person-memory"), displayName: "小陈")
        let items = [
            PersonMemoryItem(
                id: "memory-1",
                personID: profile.id,
                memoryEntityID: "person:person-profile:person-memory",
                predicate: "RELATED_TO",
                text: "小陈喜欢冲浪。",
                status: .active,
                validAt: Date(timeIntervalSince1970: 1),
                committedAt: Date(timeIntervalSince1970: 2)
            ),
            PersonMemoryItem(
                id: "memory-2",
                personID: profile.id,
                memoryEntityID: "person:person-profile:person-memory",
                predicate: "RELATED_TO",
                text: "小陈在杭州工作。",
                status: .active,
                validAt: Date(timeIntervalSince1970: 3),
                committedAt: Date(timeIntervalSince1970: 4)
            )
        ]

        let presentation = PersonProfileDetailPresentation(profile: profile, memoryItems: items)

        #expect(presentation.activeMemoryCountText == "2 条 active 记忆")
        #expect(presentation.memoryItems.map(\.text) == ["小陈喜欢冲浪。", "小陈在杭州工作。"])
        #expect(presentation.memorySummary.contains("小陈喜欢冲浪。"))
    }
}
