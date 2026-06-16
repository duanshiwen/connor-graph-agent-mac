import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Agent Runtime Preference Settings Tests")
struct AgentRuntimePreferenceSettingsTests {
    @Test func defaultsAreEmptyUntilSystemOrUserFillsThem() {
        let preferences = AgentRuntimePreferenceSettings()

        #expect(preferences.displayName.isEmpty)
        #expect(preferences.timezone.isEmpty)
        #expect(preferences.preferredLanguage.isEmpty)
        #expect(preferences.city.isEmpty)
        #expect(preferences.country.isEmpty)
        #expect(preferences.notes.isEmpty)
    }

    @Test func decodesLegacyPreferencesWithoutLanguage() throws {
        let data = Data("""
        {
          "displayName": "Alex",
          "timezone": "Europe/London",
          "city": "London",
          "country": "United Kingdom",
          "notes": "Prefers concise answers."
        }
        """.utf8)

        let preferences = try JSONDecoder().decode(AgentRuntimePreferenceSettings.self, from: data)

        #expect(preferences.displayName == "Alex")
        #expect(preferences.timezone == "Europe/London")
        #expect(preferences.preferredLanguage == "")
        #expect(preferences.city == "London")
        #expect(preferences.country == "United Kingdom")
        #expect(preferences.notes == "Prefers concise answers.")
    }

    @Test func promptBuilderIncludesOnlyFilledUserBasicInfo() {
        let preferences = AgentRuntimePreferenceSettings(
            displayName: "诗闻",
            timezone: "Asia/Shanghai",
            preferredLanguage: "简体中文",
            city: "杭州",
            country: "中国",
            notes: "数学公式使用块级 LaTeX。"
        )

        let prompt = UserBasicInfoPromptBuilder(preferences: preferences).promptSection

        #expect(prompt.contains("## 用户基本信息"))
        #expect(prompt.contains("- 称呼：诗闻"))
        #expect(prompt.contains("- 时区：Asia/Shanghai"))
        #expect(prompt.contains("- 语言偏好：简体中文"))
        #expect(prompt.contains("- 城市：杭州"))
        #expect(prompt.contains("- 国家/地区：中国"))
        #expect(prompt.contains("- 备注：数学公式使用块级 LaTeX。"))
    }
}
