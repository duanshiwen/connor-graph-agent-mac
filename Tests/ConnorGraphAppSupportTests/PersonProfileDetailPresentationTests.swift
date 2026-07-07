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
}
